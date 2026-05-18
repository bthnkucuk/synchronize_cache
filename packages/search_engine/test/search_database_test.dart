import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/pending_search_item.dart';
import 'package:search_engine/src/models/search_highlight_config.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/tables/pending_search_items.dart';
import 'package:search_engine/src/tables/search_index_cursors.dart';
import 'package:search_engine/src/tables/search_lookup.dart';

import 'search_database_test.drift.dart';

@DriftDatabase(
  include: {'package:search_engine/src/tables/search_tables.drift'},
  tables: [PendingSearchItems, SearchLookup, SearchIndexCursors],
)
class TestSearchDatabase extends $TestSearchDatabase with SearchDatabaseMixin {
  TestSearchDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

GlobalSearch makeRow({
  String originalId = 'r1',
  String userId = 'u',
  String kind = 'k',
  String title = 'Hello world',
  String description = 'A friendly greeting',
  String content = 'Lorem ipsum dolor sit amet',
  String? titleNormalized,
  String? descriptionNormalized,
  String? contentNormalized,
}) {
  String norm(String s) => s.toLowerCase();
  return GlobalSearch(
    originalId: originalId,
    userId: userId,
    kind: kind,
    title: title,
    description: description,
    content: content,
    titleNormalized: titleNormalized ?? norm(title),
    descriptionNormalized: descriptionNormalized ?? norm(description),
    contentNormalized: contentNormalized ?? norm(content),
  );
}

void main() {
  late TestSearchDatabase db;

  setUp(() {
    db = TestSearchDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('pending_search_items queue', () {
    Future<dynamic> decode(String s) async => jsonDecode(s);

    test('upsertPendingUserItems is a no-op for empty input', () async {
      await db.upsertPendingUserItems(const []);
      final items = await db.getPendingUserItems(
        userId: 'u',
        jsonDecoder: decode,
      );
      expect(items, isEmpty);
    });

    test('upsertPendingUserItems persists a row that getPendingUserItems reads back',
        () async {
      const item = PendingSearchItem(
        userId: 'u',
        kind: 'note',
        id: 'n1',
        data: {'text': 'hello'},
      );

      await db.upsertPendingUserItems([item]);

      final items = await db.getPendingUserItems(
        userId: 'u',
        jsonDecoder: decode,
      );
      expect(items, hasLength(1));
      expect(items.first.id, equals('n1'));
      expect(items.first.kind, equals('note'));
      expect(items.first.data, equals({'text': 'hello'}));
      expect(items.first.deleted, isFalse);
    });

    test('upsertPendingUserItems replaces on (id, kind) conflict', () async {
      const a = PendingSearchItem(
        userId: 'u',
        kind: 'note',
        id: 'n1',
        data: {'v': 1},
      );
      const b = PendingSearchItem(
        userId: 'u',
        kind: 'note',
        id: 'n1',
        data: {'v': 2},
        deleted: true,
      );

      await db.upsertPendingUserItems([a]);
      await db.upsertPendingUserItems([b]);

      final items = await db.getPendingUserItems(
        userId: 'u',
        jsonDecoder: decode,
      );
      expect(items, hasLength(1));
      expect(items.first.data, equals({'v': 2}));
      expect(items.first.deleted, isTrue);
    });

    test('getPendingUserItems honours the limit and userId scope', () async {
      await db.upsertPendingUserItems([
        const PendingSearchItem(userId: 'u', kind: 'k', id: '1', data: {}),
        const PendingSearchItem(userId: 'u', kind: 'k', id: '2', data: {}),
        const PendingSearchItem(userId: 'u', kind: 'k', id: '3', data: {}),
        const PendingSearchItem(userId: 'other', kind: 'k', id: '4', data: {}),
      ]);

      final scoped =
          await db.getPendingUserItems(userId: 'u', jsonDecoder: decode);
      expect(scoped.map((e) => e.id), containsAll(['1', '2', '3']));
      expect(scoped, hasLength(3));

      final limited = await db.getPendingUserItems(
        userId: 'u',
        jsonDecoder: decode,
        limit: 2,
      );
      expect(limited, hasLength(2));
    });

    test('deletePendingUserItem removes a single (id, kind) entry', () async {
      await db.upsertPendingUserItems([
        const PendingSearchItem(userId: 'u', kind: 'a', id: '1', data: {}),
        const PendingSearchItem(userId: 'u', kind: 'b', id: '1', data: {}),
      ]);

      await db.deletePendingUserItem(id: '1', kind: 'a');

      final items =
          await db.getPendingUserItems(userId: 'u', jsonDecoder: decode);
      expect(items, hasLength(1));
      expect(items.first.kind, equals('b'));
    });

    test(
        'incrementPendingTryCount + maxTryCount filter dead-letters poison rows',
        () async {
      await db.upsertPendingUserItems([
        const PendingSearchItem(userId: 'u', kind: 'k', id: 'live', data: {}),
        const PendingSearchItem(userId: 'u', kind: 'k', id: 'dead', data: {}),
      ]);

      await db.incrementPendingTryCount(id: 'dead', kind: 'k');
      await db.incrementPendingTryCount(id: 'dead', kind: 'k');

      final visible = await db.getPendingUserItems(
        userId: 'u',
        jsonDecoder: decode,
        maxTryCount: 2,
      );
      expect(visible.map((e) => e.id), equals(['live']));

      final dead = await db.getDeadLetterPendingItems(
        userId: 'u',
        minTryCount: 2,
        jsonDecoder: decode,
      );
      expect(dead.map((e) => e.id), equals(['dead']));
    });

    test('resetPendingTryCount clears the counter (scoped + global)', () async {
      await db.upsertPendingUserItems([
        const PendingSearchItem(userId: 'u', kind: 'a', id: '1', data: {}),
        const PendingSearchItem(userId: 'u', kind: 'b', id: '2', data: {}),
      ]);
      await db.incrementPendingTryCount(id: '1', kind: 'a');
      await db.incrementPendingTryCount(id: '1', kind: 'a');
      await db.incrementPendingTryCount(id: '2', kind: 'b');

      // Scoped reset
      await db.resetPendingTryCount(userId: 'u', id: '1', kind: 'a');
      var dead = await db.getDeadLetterPendingItems(
        userId: 'u',
        minTryCount: 1,
        jsonDecoder: decode,
      );
      expect(dead.map((e) => e.id), equals(['2']));

      // Global reset
      await db.resetPendingTryCount(userId: 'u');
      dead = await db.getDeadLetterPendingItems(
        userId: 'u',
        minTryCount: 1,
        jsonDecoder: decode,
      );
      expect(dead, isEmpty);
    });
  });

  group('search_index_cursors', () {
    test('readSearchIndexCursor returns null when no cursor is pinned',
        () async {
      final cursor = await db.readSearchIndexCursor(userId: 'u', kind: 'k');
      expect(cursor, isNull);
    });

    test('writeSearchIndexCursor pins (since, lastId) and is idempotent',
        () async {
      final t1 = DateTime.utc(2026, 1, 1, 12);
      await db.writeSearchIndexCursor(
        userId: 'u',
        kind: 'k',
        updatedAt: t1,
        lastId: 'a',
      );

      var cursor = await db.readSearchIndexCursor(userId: 'u', kind: 'k');
      expect(cursor, isNotNull);
      expect(cursor!.since.toUtc(), equals(t1));
      expect(cursor.lastId, equals('a'));

      final t2 = DateTime.utc(2026, 2, 2, 13);
      await db.writeSearchIndexCursor(
        userId: 'u',
        kind: 'k',
        updatedAt: t2,
        lastId: 'b',
      );

      cursor = await db.readSearchIndexCursor(userId: 'u', kind: 'k');
      expect(cursor!.since.toUtc(), equals(t2));
      expect(cursor.lastId, equals('b'));
    });

    test('clearSearchIndexCursors drops one or all cursors for a user',
        () async {
      final ts = DateTime.utc(2026);
      await db.writeSearchIndexCursor(
        userId: 'u',
        kind: 'a',
        updatedAt: ts,
        lastId: '1',
      );
      await db.writeSearchIndexCursor(
        userId: 'u',
        kind: 'b',
        updatedAt: ts,
        lastId: '2',
      );
      await db.writeSearchIndexCursor(
        userId: 'other',
        kind: 'a',
        updatedAt: ts,
        lastId: '9',
      );

      await db.clearSearchIndexCursors(userId: 'u', kind: 'a');
      expect(await db.readSearchIndexCursor(userId: 'u', kind: 'a'), isNull);
      expect(
        await db.readSearchIndexCursor(userId: 'u', kind: 'b'),
        isNotNull,
      );
      expect(
        await db.readSearchIndexCursor(userId: 'other', kind: 'a'),
        isNotNull,
      );

      await db.clearSearchIndexCursors(userId: 'u');
      expect(await db.readSearchIndexCursor(userId: 'u', kind: 'b'), isNull);
      expect(
        await db.readSearchIndexCursor(userId: 'other', kind: 'a'),
        isNotNull,
      );
    });
  });

  group('FTS5 global_search index', () {
    test('upsertSearchItem inserts a row that searchGlobal can find', () async {
      await db.upsertSearchItem(makeRow(title: 'Brown fox'));

      final hits = await db.searchGlobal(userId: 'u', query: 'fox');
      expect(hits, hasLength(1));
      expect(hits.first.originalId, equals('r1'));
      expect(hits.first.title, equals('Brown fox'));
      // Default highlight wraps the matched term in spans.
      expect(hits.first.hlTitle, contains('fox'));
      expect(hits.first.hlTitle, contains('<span class="h-title">'));
    });

    test('upsertSearchItem replaces an existing row in place', () async {
      await db.upsertSearchItem(makeRow(title: 'Original title'));
      await db.upsertSearchItem(makeRow(title: 'Updated title'));

      final hitsOriginal = await db.searchGlobal(userId: 'u', query: 'Original');
      expect(hitsOriginal, isEmpty);

      final hitsUpdated = await db.searchGlobal(userId: 'u', query: 'Updated');
      expect(hitsUpdated, hasLength(1));
    });

    test('deleteSearchItem removes the row from the index', () async {
      await db.upsertSearchItem(makeRow(title: 'Brown fox'));
      await db.deleteSearchItem(originalId: 'r1', kind: 'k', userId: 'u');

      expect(
        await db.searchGlobal(userId: 'u', query: 'fox'),
        isEmpty,
      );
    });

    test('deleteSearchItem on an unknown row is a no-op', () async {
      await expectLater(
        db.deleteSearchItem(originalId: 'missing', kind: 'k', userId: 'u'),
        completes,
      );
    });

    test('searchGlobal scopes results by userId', () async {
      await db.upsertSearchItem(
        makeRow(originalId: 'a', userId: 'u', title: 'Brown fox'),
      );
      await db.upsertSearchItem(
        makeRow(originalId: 'b', userId: 'other', title: 'Brown fox'),
      );

      final hits = await db.searchGlobal(userId: 'u', query: 'fox');
      expect(hits.map((e) => e.originalId), equals(['a']));
    });

    test('searchGlobal scopes results by kinds when provided', () async {
      await db.upsertSearchItem(
        makeRow(originalId: 'a', kind: 'note', title: 'Brown fox'),
      );
      await db.upsertSearchItem(
        makeRow(originalId: 'b', kind: 'task', title: 'Brown fox'),
      );

      final notesOnly = await db.searchGlobal(
        userId: 'u',
        query: 'fox',
        kinds: const {'note'},
      );
      expect(notesOnly.map((e) => e.originalId), equals(['a']));
    });

    test('searchGlobal returns empty list for blank queries', () async {
      await db.upsertSearchItem(makeRow(title: 'Brown fox'));

      expect(await db.searchGlobal(userId: 'u', query: ''), isEmpty);
      expect(await db.searchGlobal(userId: 'u', query: '   '), isEmpty);
    });

    test('whitespace-only queries are treated as blank', () async {
      await db.upsertSearchItem(makeRow(title: 'foxes'));

      expect(await db.searchGlobal(userId: 'u', query: '\n\t '), isEmpty);
      expect(
        await db.searchGlobal(userId: 'u', query: 'fox'),
        hasLength(1),
      );
    });

    test('searchGlobal honours offset and limit', () async {
      for (var i = 0; i < 5; i++) {
        await db.upsertSearchItem(
          makeRow(originalId: 'r$i', title: 'foxy match $i'),
        );
      }

      final firstPage = await db.searchGlobal(
        userId: 'u',
        query: 'foxy',
        limit: 2,
      );
      expect(firstPage, hasLength(2));

      final secondPage = await db.searchGlobal(
        userId: 'u',
        query: 'foxy',
        limit: 2,
        offset: 2,
      );
      expect(secondPage, hasLength(2));
      expect(
        firstPage.map((e) => e.originalId),
        isNot(equals(secondPage.map((e) => e.originalId))),
      );
    });

    test('SearchHighlightConfig.none returns raw text in highlight columns',
        () async {
      await db.upsertSearchItem(makeRow(title: 'Brown fox'));

      final hits = await db.searchGlobal(
        userId: 'u',
        query: 'fox',
        highlight: SearchHighlightConfig.none,
      );
      expect(hits.first.hlTitle, equals('Brown fox'));
    });

    test('searchGlobal uses normalized columns when a normalizer is supplied',
        () async {
      String stripDiacritics(String s) =>
          s.replaceAll('ş', 's').replaceAll('Ş', 's').toLowerCase();

      await db.upsertSearchItem(
        makeRow(
          title: 'şehir',
          titleNormalized: stripDiacritics('şehir'),
        ),
      );

      final ascii = await db.searchGlobal(
        userId: 'u',
        query: 'sehir',
        normalizer: stripDiacritics,
      );
      expect(ascii, hasLength(1));
      expect(ascii.first.title, equals('şehir'));
    });

    test('watchSearchGlobal emits a fresh page on every mutation', () async {
      final stream = db.watchSearchGlobal(userId: 'u', query: 'fox');
      final emitted = <int>[];
      final sub = stream.listen((page) => emitted.add(page.length));

      await pumpEventQueue();
      await db.upsertSearchItem(makeRow(title: 'fox 1'));
      await pumpEventQueue();
      await db.upsertSearchItem(
        makeRow(originalId: 'r2', title: 'fox 2'),
      );
      await pumpEventQueue();
      await db.deleteSearchItem(originalId: 'r1', kind: 'k', userId: 'u');
      await pumpEventQueue();

      await sub.cancel();
      // Initial empty page + three mutations.
      expect(emitted, contains(0));
      expect(emitted, contains(1));
      expect(emitted, contains(2));
    });

    test('watchSearchGlobal returns an empty stream for blank queries',
        () async {
      final stream = db.watchSearchGlobal(userId: 'u', query: '');
      expect(await stream.first, isEmpty);
    });
  });

  group('FTS5 query escaping + edge cases', () {
    test('quotes inside the query are doubled and do not break the MATCH',
        () async {
      // Indexed body literally contains a quote character.
      await db.upsertSearchItem(
        makeRow(originalId: 'q1', title: 'say "hello" world'),
      );

      // User types `"hello"` (with quotes) — this would be a syntax error
      // unless the builder doubles internal quotes.
      final hits = await db.searchGlobal(userId: 'u', query: '"hello"');
      expect(hits, hasLength(1));
      expect(hits.first.originalId, equals('q1'));
    });

    test(
        'parentheses in the query do not raise a syntax error (FTS5 treats '
        'them as operators outside quotes, but the builder wraps the query)',
        () async {
      await db.upsertSearchItem(
        makeRow(originalId: 'p1', title: 'before parens after'),
      );

      // Whether the phrase actually hits depends on FTS5's tokenizer; the
      // crucial invariant is "no SQL syntax error".
      await expectLater(
        db.searchGlobal(userId: 'u', query: '(parens)'),
        completion(isA<List<GlobalSearch>>()),
      );
    });

    test('asterisks in the query are treated as literal text', () async {
      await db.upsertSearchItem(
        makeRow(originalId: 'a1', title: 'star wars'),
      );

      // `*` is a prefix operator outside quotes; inside the builder's quotes
      // it is just an unmatched literal. Should not raise a syntax error.
      final hits = await db.searchGlobal(userId: 'u', query: '*star*');
      // Whether or not it matches is FTS5-dependent — what matters is that
      // it does not raise a SQL error.
      expect(hits, isA<List<GlobalSearch>>());
    });

    test(
        'concurrent upsertSearchItem for the same key produces exactly one row',
        () async {
      final futures = <Future<void>>[
        for (var i = 0; i < 10; i++)
          db.upsertSearchItem(
            makeRow(originalId: 'same', title: 'version $i'),
          ),
      ];
      await Future.wait(futures);

      // Search by stem common to every version.
      final hits = await db.searchGlobal(userId: 'u', query: 'version');
      expect(hits, hasLength(1),
          reason: 'upsert must collapse to exactly one row');
      expect(hits.first.originalId, equals('same'));
    });

    test('searchGlobal with kinds filter containing a single kind', () async {
      await db.upsertSearchItem(
        makeRow(originalId: 'a', kind: 'note', title: 'shared word'),
      );
      await db.upsertSearchItem(
        makeRow(originalId: 'b', kind: 'task', title: 'shared word'),
      );

      final hits = await db.searchGlobal(
        userId: 'u',
        query: 'shared',
        kinds: const {'note'},
      );
      expect(hits.map((e) => e.originalId), equals(['a']));
    });

    test('searchGlobal with kinds filter containing many entries', () async {
      await db.upsertSearchItem(
        makeRow(originalId: 'a', kind: 'note', title: 'shared word'),
      );
      await db.upsertSearchItem(
        makeRow(originalId: 'b', kind: 'task', title: 'shared word'),
      );
      await db.upsertSearchItem(
        makeRow(originalId: 'c', kind: 'event', title: 'shared word'),
      );
      await db.upsertSearchItem(
        makeRow(originalId: 'd', kind: 'archived', title: 'shared word'),
      );

      final hits = await db.searchGlobal(
        userId: 'u',
        query: 'shared',
        kinds: const {'note', 'task', 'event'},
      );
      expect(hits.map((e) => e.originalId), unorderedEquals(['a', 'b', 'c']));
    });

    test('searchGlobal with limit:0 returns an empty list and no SQL error',
        () async {
      await db.upsertSearchItem(makeRow(title: 'foxes'));
      final hits =
          await db.searchGlobal(userId: 'u', query: 'fox', limit: 0);
      expect(hits, isEmpty);
    });

    test(
        'SearchHighlightConfig.none with explicit empty snippetEllipsis still '
        'returns the raw matched text', () async {
      await db.upsertSearchItem(makeRow(title: 'Brown fox'));

      const cfg = SearchHighlightConfig(
        titleOpen: '',
        titleClose: '',
        descOpen: '',
        descClose: '',
        contentOpen: '',
        contentClose: '',
        snippetEllipsis: '',
      );

      final hits = await db.searchGlobal(
        userId: 'u',
        query: 'fox',
        highlight: cfg,
      );
      expect(hits.first.hlTitle, equals('Brown fox'));
    });
  });
}
