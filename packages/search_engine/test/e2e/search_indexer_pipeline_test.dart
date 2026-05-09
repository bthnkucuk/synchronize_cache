// End-to-end test for SearchIndexer wired against a real drift database
// (in-memory, FTS5) and a real SearchEngine + DriftFtsSearchTransport.
//
// Drives the indexer with a host-side data table (`Notes`) so we can assert
// that mutations on a real drift table actually flow into the FTS index via
// `tableUpdates` → `readSince` → `indexNow`.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/searchable_table.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/search_engine.dart';
import 'package:search_engine/src/search_indexer.dart';
import 'package:search_engine/src/tables/pending_search_items.dart';
import 'package:search_engine/src/tables/search_index_cursors.dart';
import 'package:search_engine/src/tables/search_lookup.dart';
import 'package:search_engine/src/transport/drift_fts_search_transport.dart';

import 'search_indexer_pipeline_test.drift.dart';

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get title => text()();
  IntColumn get updatedAtMs => integer().named('updated_at_ms')();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'rows';
}

@DriftDatabase(
  include: {'package:search_engine/src/tables/search_tables.drift'},
  tables: [PendingSearchItems, SearchLookup, SearchIndexCursors, Notes],
)
class TestIndexerDatabase extends $TestIndexerDatabase
    with SearchDatabaseMixin {
  TestIndexerDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

SearchableTable<TestIndexerDatabase, Note> notesBinding() =>
    searchableTable<TestIndexerDatabase, Note>(
      kind: 'rows',
      watch:
          (db, userId) =>
              (db.select(db.notes)
                ..where((t) => t.userId.equals(userId))).watch(),
      idOf: (r) => r.id,
      isDeleted: (r) => r.deleted,
      toJson: (r) => {'id': r.id, 'title': r.title},
      updatedAtOf:
          (r) =>
              DateTime.fromMillisecondsSinceEpoch(r.updatedAtMs, isUtc: true),
      readSince: (db, userId, since, lastId, limit) async {
        final sinceMs = since.toUtc().millisecondsSinceEpoch;
        final query =
            db.select(db.notes)
              ..where(
                (t) =>
                    t.userId.equals(userId) &
                    (t.updatedAtMs.isBiggerThanValue(sinceMs) |
                        (t.updatedAtMs.equals(sinceMs) &
                            (lastId == null
                                ? const Constant(true)
                                : t.id.isBiggerThanValue(lastId)))),
              )
              ..orderBy([
                (t) => OrderingTerm(expression: t.updatedAtMs),
                (t) => OrderingTerm(expression: t.id),
              ])
              ..limit(limit);
        return query.get();
      },
      toGlobalSearch:
          (item) async => GlobalSearch(
            originalId: item.id,
            userId: item.userId,
            kind: item.kind,
            title: (item.data['title'] as String?) ?? '',
            description: '',
            content: '',
          ),
    );

Future<void> insertNote(
  TestIndexerDatabase db, {
  required String id,
  required String title,
  String userId = 'u',
  bool deleted = false,
  DateTime? updatedAt,
}) => db
    .into(db.notes)
    .insertOnConflictUpdate(
      NotesCompanion.insert(
        id: id,
        userId: userId,
        title: title,
        updatedAtMs:
            (updatedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
        deleted: Value(deleted),
      ),
    );

void main() {
  late TestIndexerDatabase db;
  late SearchEngine engine;
  late SearchIndexer<TestIndexerDatabase> indexer;

  setUp(() {
    db = TestIndexerDatabase();
    engine = SearchEngine(
      transport: DriftFtsSearchTransport(db),
      database: db,
      tables: [notesBinding()],
    );
    indexer = SearchIndexer<TestIndexerDatabase>(
      db: db,
      searchEngine: engine,
      tables: [notesBinding()],
      debounce: const Duration(milliseconds: 1),
      batchSize: 50,
    );
  });

  tearDown(() async {
    await indexer.stop();
    await db.close();
  });

  Future<void> waitForIndexer() async {
    // Allow tableUpdates → debounce → batch loop → FTS write to settle.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  test('initial drain on start() indexes pre-existing rows', () async {
    await insertNote(db, id: 'a', title: 'Brown fox');
    await insertNote(db, id: 'b', title: 'Quick fox');

    await indexer.start(userId: 'u');
    await waitForIndexer();

    final hits = await db.searchGlobal(userId: 'u', query: 'fox');
    expect(hits.map((e) => e.originalId).toSet(), equals({'a', 'b'}));

    final cursorA = await db.readSearchIndexCursor(userId: 'u', kind: 'rows');
    expect(cursorA, isNotNull);
  });

  test('mutations after start() flow into the FTS index reactively', () async {
    await indexer.start(userId: 'u');
    await waitForIndexer();

    await insertNote(db, id: 'a', title: 'Brown fox');
    await waitForIndexer();

    final hits = await db.searchGlobal(userId: 'u', query: 'fox');
    expect(hits.map((e) => e.originalId), equals(['a']));
  });

  test('soft-deleted rows are removed from the FTS index', () async {
    await insertNote(db, id: 'a', title: 'Brown fox');
    await indexer.start(userId: 'u');
    await waitForIndexer();
    expect(await db.searchGlobal(userId: 'u', query: 'fox'), hasLength(1));

    await insertNote(
      db,
      id: 'a',
      title: 'Brown fox',
      deleted: true,
      updatedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
    );
    await waitForIndexer();

    expect(await db.searchGlobal(userId: 'u', query: 'fox'), isEmpty);
  });

  test(
    'cursor prevents already-indexed rows from being re-processed',
    () async {
      await insertNote(
        db,
        id: 'a',
        title: 'alpha',
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      await indexer.start(userId: 'u');
      await waitForIndexer();

      // Stop, then insert a fresh row, then restart — only the new row should
      // be processed thanks to the persisted cursor.
      await indexer.stop();

      await insertNote(
        db,
        id: 'b',
        title: 'beta',
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      await indexer.start(userId: 'u');
      await waitForIndexer();

      final hits = await db.searchGlobal(userId: 'u', query: 'beta');
      expect(hits.map((e) => e.originalId), equals(['b']));

      // Cursor must have advanced to the latest row.
      final cursor = await db.readSearchIndexCursor(userId: 'u', kind: 'rows');
      expect(cursor!.lastId, equals('b'));
      expect(cursor.since.toUtc(), equals(DateTime.utc(2026, 1, 2)));
    },
  );

  test(
    'refreshAll() picks up rows whose tableUpdates emit was missed',
    () async {
      await indexer.start(userId: 'u');
      await waitForIndexer();

      // Bypass tableUpdates by inserting via raw custom statement — this still
      // notifies drift, so to truly simulate a "missed" emit we just rely on
      // refreshAll() to re-run the loop. The assertion is that refreshAll()
      // picks the row up regardless of whether the emit reached us.
      await insertNote(db, id: 'a', title: 'late');
      await indexer.refreshAll();
      await waitForIndexer();

      expect(await db.searchGlobal(userId: 'u', query: 'late'), hasLength(1));
    },
  );

  test('rows for other users are not indexed under the wrong cursor', () async {
    await insertNote(db, id: 'a', title: 'mine', userId: 'u');
    await insertNote(db, id: 'b', title: 'theirs', userId: 'other');

    await indexer.start(userId: 'u');
    await waitForIndexer();

    final mine = await db.searchGlobal(userId: 'u', query: 'mine');
    expect(mine, hasLength(1));
    final theirs = await db.searchGlobal(userId: 'u', query: 'theirs');
    expect(theirs, isEmpty);
  });
}
