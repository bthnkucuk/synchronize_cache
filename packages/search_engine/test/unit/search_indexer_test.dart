import 'dart:async';

import 'package:drift/drift.dart'
    show GeneratedDatabase, TableUpdate, TableUpdateQuery;
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/pending_search_item.dart';
import 'package:search_engine/src/models/searchable_table.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/search_engine.dart';
import 'package:search_engine/src/search_indexer.dart';

class _MockDb extends Mock implements GeneratedDatabase {}

class _MockEngine extends Mock implements SearchEngine {}

class _MockSearchDb extends Mock implements SearchDatabaseMixin {}

class _FakeGlobalSearch extends Fake implements GlobalSearch {}

class _FakeTableUpdateQuery extends Fake implements TableUpdateQuery {}

/// Test row — `updatedAt` and `id` mirror the cursor's tie-break shape.
class _Row {
  const _Row({
    required this.id,
    required this.updatedAt,
    this.deleted = false,
    this.title = 't',
  });

  final String id;
  final DateTime updatedAt;
  final bool deleted;
  final String title;
}

/// Test binding: drives `readSince` from an in-memory list. Tests mutate the
/// list to simulate fresh rows arriving between batches.
class _TestBinding extends SearchableTable<GeneratedDatabase, _Row> {
  _TestBinding();

  final List<_Row> _rows = [];
  int readSinceCalls = 0;

  void seed(Iterable<_Row> rows) {
    _rows
      ..clear()
      ..addAll(rows);
  }

  @override
  String get kind => 'rows';

  @override
  Stream<List<_Row>> watch(GeneratedDatabase db, String userId) =>
      const Stream.empty();

  @override
  String idOf(_Row row) => row.id;

  @override
  bool isDeleted(_Row row) => row.deleted;

  @override
  DateTime updatedAtOf(_Row row) => row.updatedAt;

  @override
  Map<String, dynamic> toJson(_Row row) =>
      {'id': row.id, 'title': row.title};

  @override
  Future<GlobalSearch> toGlobalSearch(PendingSearchItem item) async =>
      GlobalSearch(
        originalId: item.id,
        userId: item.userId,
        kind: item.kind,
        title: (item.data['title'] as String?) ?? '',
        description: '',
        content: '',
      );

  @override
  Future<List<_Row>> readSince(
    GeneratedDatabase db,
    String userId,
    DateTime since,
    String? lastId,
    int limit,
  ) async {
    readSinceCalls++;
    final filtered = _rows
        .where(
          (r) =>
              r.updatedAt.isAfter(since) ||
              (r.updatedAt.isAtSameMomentAs(since) &&
                  (lastId == null || r.id.compareTo(lastId) > 0)),
        )
        .toList()
      ..sort((a, b) {
        final byTime = a.updatedAt.compareTo(b.updatedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return filtered.take(limit).toList();
  }
}

class _ExplodingBinding extends SearchableTable<GeneratedDatabase, _Row> {
  @override
  String get kind => 'boom';

  @override
  Stream<List<_Row>> watch(GeneratedDatabase db, String userId) =>
      const Stream.empty();

  @override
  String idOf(_Row row) => row.id;

  @override
  bool isDeleted(_Row row) => row.deleted;

  @override
  Map<String, dynamic> toJson(_Row row) => {};

  @override
  DateTime updatedAtOf(_Row row) => row.updatedAt;

  @override
  Future<List<_Row>> readSince(
    GeneratedDatabase db,
    String userId,
    DateTime since,
    String? lastId,
    int limit,
  ) async =>
      throw StateError('boom');
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeGlobalSearch());
    registerFallbackValue(_FakeTableUpdateQuery());
  });

  late _MockDb db;
  late _MockEngine engine;
  late _MockSearchDb searchDb;
  late StreamController<Set<TableUpdate>> tableUpdates;
  late _TestBinding binding;

  setUp(() {
    db = _MockDb();
    engine = _MockEngine();
    searchDb = _MockSearchDb();
    tableUpdates = StreamController<Set<TableUpdate>>.broadcast();
    binding = _TestBinding();

    when(() => db.tableUpdates(any())).thenAnswer((_) => tableUpdates.stream);
    when(() => engine.indexNow(any())).thenAnswer((_) async {});
    when(
      () => engine.removeNow(
        originalId: any(named: 'originalId'),
        kind: any(named: 'kind'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});
    when(() => engine.database).thenReturn(searchDb);

    when(
      () => searchDb.readSearchIndexCursor(
        userId: any(named: 'userId'),
        kind: any(named: 'kind'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => searchDb.writeSearchIndexCursor(
        userId: any(named: 'userId'),
        kind: any(named: 'kind'),
        updatedAt: any(named: 'updatedAt'),
        lastId: any(named: 'lastId'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    await tableUpdates.close();
  });

  // Drains microtasks so the indexer's async batch loop can settle.
  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  SearchIndexer<GeneratedDatabase> makeIndexer({int batchSize = 100}) =>
      SearchIndexer<GeneratedDatabase>(
        db: db,
        searchEngine: engine,
        tables: [binding],
        batchSize: batchSize,
        debounce: const Duration(milliseconds: 1),
      );

  group('start / stop / currentUserId', () {
    test('currentUserId is null before start and after stop', () async {
      final indexer = makeIndexer();
      expect(indexer.currentUserId, isNull);

      await indexer.start(userId: 'u');
      expect(indexer.currentUserId, equals('u'));

      await indexer.stop();
      expect(indexer.currentUserId, isNull);
    });

    test('start runs an initial drain even before any tableUpdates emit',
        () async {
      binding.seed([
        _Row(id: 'a', updatedAt: DateTime.utc(2026)),
      ]);

      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      expect(binding.readSinceCalls, greaterThanOrEqualTo(1));
      verify(() => engine.indexNow(any())).called(1);

      await indexer.stop();
    });

    test('start replaces the previous subscription atomically', () async {
      final indexer = makeIndexer();
      await indexer.start(userId: 'u1');
      await flush();

      await indexer.start(userId: 'u2');
      expect(indexer.currentUserId, equals('u2'));

      await indexer.stop();
    });

    test('stop is safe to call before start', () async {
      final indexer = makeIndexer();
      await indexer.stop();
      // No assertion — completing is the contract.
    });
  });

  group('indexing path', () {
    test('non-deleted rows go through engine.indexNow with parsed GlobalSearch',
        () async {
      binding.seed([
        _Row(id: 'a', updatedAt: DateTime.utc(2026, 1, 1), title: 'alpha'),
      ]);

      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      final captured = verify(() => engine.indexNow(captureAny())).captured;
      final pushed = captured.single as GlobalSearch;
      expect(pushed.originalId, equals('a'));
      expect(pushed.title, equals('alpha'));
      expect(pushed.userId, equals('u'));
      expect(pushed.kind, equals('rows'));

      verifyNever(
        () => engine.removeNow(
          originalId: any(named: 'originalId'),
          kind: any(named: 'kind'),
          userId: any(named: 'userId'),
        ),
      );

      await indexer.stop();
    });

    test('tombstone rows go through engine.removeNow, not indexNow', () async {
      binding.seed([
        _Row(id: 'a', updatedAt: DateTime.utc(2026), deleted: true),
      ]);

      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      verify(
        () => engine.removeNow(originalId: 'a', kind: 'rows', userId: 'u'),
      ).called(1);
      verifyNever(() => engine.indexNow(any()));

      await indexer.stop();
    });

    test('mix of deleted + alive rows is dispatched to the right channels',
        () async {
      binding.seed([
        _Row(id: 'a', updatedAt: DateTime.utc(2026, 1, 1), title: 'alpha'),
        _Row(id: 'b', updatedAt: DateTime.utc(2026, 1, 2), deleted: true),
        _Row(id: 'c', updatedAt: DateTime.utc(2026, 1, 3), title: 'gamma'),
      ]);

      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      verify(() => engine.indexNow(any())).called(2);
      verify(
        () => engine.removeNow(originalId: 'b', kind: 'rows', userId: 'u'),
      ).called(1);

      await indexer.stop();
    });

    test('empty readSince returns immediately without any indexNow calls',
        () async {
      // No seed → readSince returns empty.
      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      verifyNever(() => engine.indexNow(any()));
      verifyNever(
        () => engine.removeNow(
          originalId: any(named: 'originalId'),
          kind: any(named: 'kind'),
          userId: any(named: 'userId'),
        ),
      );
      verifyNever(
        () => searchDb.writeSearchIndexCursor(
          userId: any(named: 'userId'),
          kind: any(named: 'kind'),
          updatedAt: any(named: 'updatedAt'),
          lastId: any(named: 'lastId'),
        ),
      );

      await indexer.stop();
    });
  });

  group('cursor advance', () {
    test('writes the cursor of the last indexed row after a batch', () async {
      binding.seed([
        _Row(id: 'a', updatedAt: DateTime.utc(2026, 1, 1)),
        _Row(id: 'b', updatedAt: DateTime.utc(2026, 1, 2)),
      ]);

      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      verify(
        () => searchDb.writeSearchIndexCursor(
          userId: 'u',
          kind: 'rows',
          updatedAt: DateTime.utc(2026, 1, 2),
          lastId: 'b',
        ),
      ).called(1);

      await indexer.stop();
    });

    test('paginates: keeps fetching while the batch is full', () async {
      binding.seed([
        for (var i = 1; i <= 5; i++)
          _Row(id: 'r$i', updatedAt: DateTime.utc(2026, 1, i)),
      ]);

      final indexer = makeIndexer(batchSize: 2);
      await indexer.start(userId: 'u');
      await flush();

      // 5 rows / batch size 2 → 3 readSince calls (2, 2, 1) since the last
      // batch is partial (terminates the loop).
      expect(binding.readSinceCalls, equals(3));
      verify(() => engine.indexNow(any())).called(5);
      verify(
        () => searchDb.writeSearchIndexCursor(
          userId: 'u',
          kind: 'rows',
          updatedAt: DateTime.utc(2026, 1, 5),
          lastId: 'r5',
        ),
      ).called(1);

      await indexer.stop();
    });

    test('starts from the persisted cursor, not from epoch', () async {
      when(
        () => searchDb.readSearchIndexCursor(
          userId: 'u',
          kind: 'rows',
        ),
      ).thenAnswer(
        (_) async => SearchIndexCursor(
          since: DateTime.utc(2026, 1, 5),
          lastId: 'r5',
        ),
      );

      binding.seed([
        _Row(id: 'r3', updatedAt: DateTime.utc(2026, 1, 3)),
        _Row(id: 'r5', updatedAt: DateTime.utc(2026, 1, 5)),
        _Row(id: 'r7', updatedAt: DateTime.utc(2026, 1, 7)),
      ]);

      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      // Only `r7` is past the cursor.
      verify(() => engine.indexNow(any())).called(1);
      verify(
        () => searchDb.writeSearchIndexCursor(
          userId: 'u',
          kind: 'rows',
          updatedAt: DateTime.utc(2026, 1, 7),
          lastId: 'r7',
        ),
      ).called(1);

      await indexer.stop();
    });
  });

  group('reactivity', () {
    test('subsequent tableUpdates emit re-runs the batch', () {
      FakeAsync().run((fake) {
        final indexer = makeIndexer();
        unawaited(indexer.start(userId: 'u'));
        fake.flushMicrotasks();

        binding.seed([
          _Row(id: 'late', updatedAt: DateTime.utc(2026, 6)),
        ]);
        tableUpdates.add(<TableUpdate>{});
        // Advance past the rxdart debounce window (1ms) to release the timer.
        fake.elapse(const Duration(milliseconds: 5));
        fake.flushMicrotasks();

        verify(() => engine.indexNow(any())).called(1);

        unawaited(indexer.stop());
        fake.flushMicrotasks();
      });
    });

    test('emits arriving after stop are ignored', () {
      FakeAsync().run((fake) {
        final indexer = makeIndexer();
        unawaited(indexer.start(userId: 'u'));
        fake.flushMicrotasks();
        unawaited(indexer.stop());
        fake.flushMicrotasks();

        binding.seed([_Row(id: 'late', updatedAt: DateTime.utc(2026))]);
        tableUpdates.add(<TableUpdate>{});
        // Advance past the rxdart debounce window (1ms); even if a timer fires
        // it should be a no-op because the subscription has been cancelled.
        fake.elapse(const Duration(milliseconds: 5));
        fake.flushMicrotasks();

        verifyNever(() => engine.indexNow(any()));
      });
    });
  });

  group('refreshAll', () {
    test('no-op when no user is bound', () async {
      final indexer = makeIndexer();
      await indexer.refreshAll();
      verifyNever(() => engine.indexNow(any()));
    });

    test('triggers a fresh batch for every registered table', () async {
      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();
      final initialCalls = binding.readSinceCalls;

      binding.seed([_Row(id: 'late', updatedAt: DateTime.utc(2026, 6))]);
      await indexer.refreshAll();
      await flush();

      expect(binding.readSinceCalls, greaterThan(initialCalls));
      verify(() => engine.indexNow(any())).called(1);

      await indexer.stop();
    });
  });

  group('cursor edge cases', () {
    test(
        'rows sharing updatedAt are tie-broken lexicographically by id and '
        'every row gets indexed', () async {
      final ts = DateTime.utc(2026, 3, 1);
      // Insert in non-lexicographic order to make sure the indexer's sort
      // path is what produces the cursor advance.
      binding.seed([
        _Row(id: 'c', updatedAt: ts, title: 'c-title'),
        _Row(id: 'a', updatedAt: ts, title: 'a-title'),
        _Row(id: 'b', updatedAt: ts, title: 'b-title'),
      ]);

      final indexer = makeIndexer(batchSize: 2);
      await indexer.start(userId: 'u');
      await flush();

      // 3 rows / batchSize 2 → expect 2 readSince calls (2 + 1).
      expect(binding.readSinceCalls, equals(2));
      verify(() => engine.indexNow(any())).called(3);

      // The cursor lands on the last (largest id) row.
      verify(
        () => searchDb.writeSearchIndexCursor(
          userId: 'u',
          kind: 'rows',
          updatedAt: ts,
          lastId: 'c',
        ),
      ).called(1);

      await indexer.stop();
    });

    test(
        'switching users mid-flight stops the in-flight u1 batch from '
        'advancing the u1 cursor', () async {
      // Hold the cursor read until we release it manually — that way we can
      // drive a second start() while the first batch is parked.
      final firstReadStarted = Completer<void>();
      final releaseFirstRead = Completer<void>();
      when(
        () => searchDb.readSearchIndexCursor(
          userId: 'u1',
          kind: 'rows',
        ),
      ).thenAnswer((_) async {
        firstReadStarted.complete();
        await releaseFirstRead.future;
        return null;
      });
      when(
        () => searchDb.readSearchIndexCursor(
          userId: 'u2',
          kind: 'rows',
        ),
      ).thenAnswer((_) async => null);

      binding.seed([_Row(id: 'r1', updatedAt: DateTime.utc(2026))]);

      final indexer = makeIndexer();
      unawaited(indexer.start(userId: 'u1'));
      await firstReadStarted.future;

      // While u1's batch is parked on the cursor read, switch user.
      await indexer.start(userId: 'u2');
      releaseFirstRead.complete();
      await flush();

      // The u1 cursor must not have been written — the in-flight batch
      // bailed at the `_userId != userId` guard after the cursor read
      // returned.
      verifyNever(
        () => searchDb.writeSearchIndexCursor(
          userId: 'u1',
          kind: any(named: 'kind'),
          updatedAt: any(named: 'updatedAt'),
          lastId: any(named: 'lastId'),
        ),
      );
      // u2's batch proceeds and writes its own cursor.
      verify(
        () => searchDb.writeSearchIndexCursor(
          userId: 'u2',
          kind: 'rows',
          updatedAt: any(named: 'updatedAt'),
          lastId: any(named: 'lastId'),
        ),
      ).called(1);

      await indexer.stop();
    });

    test('empty tables list: start() completes without throwing', () async {
      final indexer = SearchIndexer<GeneratedDatabase>(
        db: db,
        searchEngine: engine,
        tables: const [],
        batchSize: 100,
        debounce: const Duration(milliseconds: 1),
      );

      await expectLater(indexer.start(userId: 'u'), completes);
      expect(indexer.currentUserId, equals('u'));

      verifyNever(() => db.tableUpdates(any()));
      verifyNever(() => engine.indexNow(any()));

      await expectLater(indexer.refreshAll(), completes);
      await indexer.stop();
    });

    test(
        'tableUpdates events fired before start() are ignored (no listener '
        "exists yet) and don't crash a later start", () async {
      // Push an emit on the broadcast controller before anyone listens.
      tableUpdates.add(<TableUpdate>{});
      // A bit more to be sure: drain microtasks first.
      await Future<void>.delayed(Duration.zero);

      binding.seed([
        _Row(id: 'a', updatedAt: DateTime.utc(2026, 1, 1)),
      ]);

      final indexer = makeIndexer();
      await expectLater(indexer.start(userId: 'u'), completes);
      await flush();

      // Initial drain still runs once, and the lost pre-start emit doesn't
      // cause a second batch.
      verify(() => engine.indexNow(any())).called(1);

      await indexer.stop();
    });
  });

  group('error handling', () {
    test('readSince errors are swallowed (best-effort)', () async {
      final exploding = _ExplodingBinding();
      final indexer = SearchIndexer<GeneratedDatabase>(
        db: db,
        searchEngine: engine,
        tables: [exploding],
        batchSize: 100,
        debounce: const Duration(milliseconds: 1),
      );

      await expectLater(indexer.start(userId: 'u'), completes);
      await flush();
      verifyNever(() => engine.indexNow(any()));
      expect(indexer.currentUserId, equals('u'));

      await indexer.stop();
    });

    test('indexNow errors are swallowed and cursor is NOT advanced',
        () async {
      when(() => engine.indexNow(any())).thenThrow(StateError('engine down'));
      binding.seed([
        _Row(id: 'a', updatedAt: DateTime.utc(2026, 1, 1)),
      ]);

      final indexer = makeIndexer();
      await indexer.start(userId: 'u');
      await flush();

      verifyNever(
        () => searchDb.writeSearchIndexCursor(
          userId: any(named: 'userId'),
          kind: any(named: 'kind'),
          updatedAt: any(named: 'updatedAt'),
          lastId: any(named: 'lastId'),
        ),
      );

      await indexer.stop();
    });
  });
}
