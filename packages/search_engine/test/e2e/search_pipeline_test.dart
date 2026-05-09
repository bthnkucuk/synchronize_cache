import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:search_engine/src/models/pending_search_item.dart';
import 'package:search_engine/src/models/searchable_table.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/search_engine.dart';
import 'package:search_engine/src/tables/pending_search_items.dart';
import 'package:search_engine/src/tables/search_index_cursors.dart';
import 'package:search_engine/src/tables/search_lookup.dart';
import 'package:search_engine/src/transport/drift_fts_search_transport.dart';

import 'search_pipeline_test.drift.dart';

@DriftDatabase(
  include: {'package:search_engine/src/tables/search_tables.drift'},
  tables: [PendingSearchItems, SearchLookup, SearchIndexCursors],
)
class TestSearchDatabase extends $TestSearchDatabase with SearchDatabaseMixin {
  TestSearchDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

PendingSearchItem makeItem({
  String id = '1',
  String userId = 'u',
  String kind = 'note',
  bool deleted = false,
  Map<String, dynamic> data = const {
    'title': 'Brown fox',
    'description': 'jumps over',
    'content': 'lazy dog',
  },
}) =>
    PendingSearchItem(
      userId: userId,
      kind: kind,
      id: id,
      data: data,
      deleted: deleted,
    );

void main() {
  late TestSearchDatabase db;
  late SearchEngine engine;

  setUp(() {
    db = TestSearchDatabase();
    engine = SearchEngine(
      transport: DriftFtsSearchTransport(db),
      database: db,
      tables: [
        // Default toGlobalSearch maps title/description/content from
        // PendingSearchItem.data — exactly the wiring documented for the
        // engine in normal usage.
        searchableTable<GeneratedDatabase, Map<String, dynamic>>(
          kind: 'note',
          watch: (_, __) => const Stream.empty(),
          idOf: (row) => row['id'] as String,
          toJson: (row) => row,
        ),
      ],
      jsonDecoder: (s) async => jsonDecode(s),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('addSearchItems(processNow: true) writes to FTS and clears the queue',
      () async {
    await engine.addSearchItems([makeItem()], processNow: true);

    final hits = await db.searchGlobal(userId: 'u', query: 'fox');
    expect(hits, hasLength(1));
    expect(hits.first.originalId, equals('1'));
    expect(hits.first.title, equals('Brown fox'));

    final pending = await db.getPendingUserItems(
      userId: 'u',
      jsonDecoder: (s) async => jsonDecode(s),
    );
    expect(pending, isEmpty,
        reason: 'successfully indexed rows must be removed from the queue');
  });

  test('processPendingItems drains the queue into the FTS index', () async {
    // Enqueue without processing — simulates a sync that wrote to the queue
    // but did not flush yet.
    await engine.addSearchItems([
      makeItem(id: '1', data: const {'title': 'fox one'}),
      makeItem(id: '2', data: const {'title': 'fox two'}),
    ]);

    expect(
      await db.searchGlobal(userId: 'u', query: 'fox'),
      isEmpty,
      reason: 'index should be empty before processPendingItems runs',
    );

    await engine.processPendingItems(userId: 'u');

    final hits = await db.searchGlobal(userId: 'u', query: 'fox');
    expect(hits.map((e) => e.originalId).toSet(), equals({'1', '2'}));

    final pending = await db.getPendingUserItems(
      userId: 'u',
      jsonDecoder: (s) async => jsonDecode(s),
    );
    expect(pending, isEmpty);
  });

  test('deleted pending item removes the row from the FTS index', () async {
    // First seed the index with a row.
    await engine.addSearchItems([makeItem(id: '1')], processNow: true);
    expect(await db.searchGlobal(userId: 'u', query: 'fox'), hasLength(1));

    // Then enqueue a tombstone for the same (id, kind) and drain.
    await engine.addSearchItems(
      [makeItem(id: '1', deleted: true)],
      processNow: true,
    );

    expect(await db.searchGlobal(userId: 'u', query: 'fox'), isEmpty);
    final pending = await db.getPendingUserItems(
      userId: 'u',
      jsonDecoder: (s) async => jsonDecode(s),
    );
    expect(pending, isEmpty);
  });
}
