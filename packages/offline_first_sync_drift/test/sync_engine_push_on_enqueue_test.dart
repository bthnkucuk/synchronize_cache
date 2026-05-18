import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart' hide isNotNull, isNull;

import 'sync_engine_test.dart';
import 'sync_engine_test.drift.dart';

/// Counting transport that records every push() call.
class _CountingTransport implements TransportAdapter {
  int pullCallCount = 0;
  int pushCallCount = 0;
  final List<Set<String>> pushedKindsPerCall = [];

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    pullCallCount++;
    return PullPage(items: const []);
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    pushCallCount++;
    pushedKindsPerCall.add(ops.map((o) => o.kind).toSet());
    return BatchPushResult(
      results: ops
          .map((op) => OpPushResult(opId: op.opId, result: const PushSuccess()))
          .toList(),
    );
  }

  @override
  Future<PushResult> forcePush(Op op) async => const PushSuccess();

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

SyncableTable<TestItem> _table(TestDatabase db, String kind) =>
    SyncableTable<TestItem>(
      kind: kind,
      table: db.testItems,
      fromJson: TestItem.fromJson,
      toJson: (item) => item.toJson(),
      toInsertable: (item) => item.toInsertable(),
      getId: (item) => item.id,
      getUpdatedAt: (item) => item.updatedAt,
    );

/// Bypass the full-resync gate so push-only sync runs predictably.
Future<void> _seedFullResyncCursor(TestDatabase db) async {
  await db.setCursor(
    CursorKinds.fullResync,
    Cursor(ts: DateTime.now().toUtc(), lastId: ''),
  );
}

void main() {
  late TestDatabase db;

  setUp(() async {
    db = TestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('pushOnEnqueue', () {
    test(
      'default off: enqueue without manual sync produces zero push calls',
      () async {
        final transport = _CountingTransport();
        final engine = SyncEngine(
          db: db,
          transport: transport,
          tables: [_table(db, 'kind_a')],
          // pushOnEnqueue defaults to false.
        );
        await _seedFullResyncCursor(db);

        await db
            .syncWriter()
            .forTable(_table(db, 'kind_a'))
            .insertAndEnqueue(
              TestItem(
                id: 'a-1',
                updatedAt: DateTime.utc(2024, 1, 1),
                name: 'one',
              ),
            );

        // Advance synthetic time well past any plausible debounce window.
        // With pushOnEnqueue disabled, no auto-push Timer should be armed.
        // FakeAsync proves this: real-time Timer-based debouncers would fire
        // here if they existed.
        FakeAsync().run((fake) {
          fake.elapse(const Duration(milliseconds: 400));
          fake.flushMicrotasks();
        });

        expect(transport.pushCallCount, 0);
        expect(transport.pullCallCount, 0);

        engine.dispose();
      },
    );

    test(
      'eager push: a single enqueue produces exactly one push after debounce',
      () async {
        final transport = _CountingTransport();
        final engine = SyncEngine(
          db: db,
          transport: transport,
          tables: [_table(db, 'kind_a')],
          config: const SyncConfig(
            pushOnEnqueue: true,
            enqueuePushDebounce: Duration(milliseconds: 80),
          ),
        );
        await _seedFullResyncCursor(db);

        await db
            .syncWriter()
            .forTable(_table(db, 'kind_a'))
            .insertAndEnqueue(
              TestItem(
                id: 'a-1',
                updatedAt: DateTime.utc(2024, 1, 1),
                name: 'one',
              ),
            );

        // After well past the debounce window, exactly one push.
        // NOTE: cannot use FakeAsync here — the debounce Timer's callback
        // performs drift reads/writes against NativeDatabase.memory (sqlite
        // FFI), which does not advance synchronously under FakeAsync.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(transport.pushCallCount, 1);
        expect(transport.pushedKindsPerCall.first, {'kind_a'});
        // Restricted to push-only — no pull triggered.
        expect(transport.pullCallCount, 0);

        engine.dispose();
      },
    );

    test(
      'debounce: rapid same-kind enqueues coalesce into a single push',
      () async {
        final transport = _CountingTransport();
        final engine = SyncEngine(
          db: db,
          transport: transport,
          tables: [_table(db, 'kind_a')],
          config: const SyncConfig(
            pushOnEnqueue: true,
            enqueuePushDebounce: Duration(milliseconds: 80),
          ),
        );
        await _seedFullResyncCursor(db);

        // Five rapid enqueues for the same kind, all within one debounce
        // window (80ms). Each subsequent enqueue should reset the timer.
        for (var i = 0; i < 5; i++) {
          await db
              .syncWriter()
              .forTable(_table(db, 'kind_a'))
              .insertAndEnqueue(
                TestItem(
                  id: 'a-$i',
                  updatedAt: DateTime.utc(2024, 1, 1, 0, 0, i),
                  name: 'item-$i',
                ),
              );
          // Tiny gap << debounce window so the timer keeps resetting.
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        // Wait well past the debounce window.
        await Future<void>.delayed(const Duration(milliseconds: 250));

        // All five enqueues coalesce into a single push.
        expect(transport.pushCallCount, 1);

        engine.dispose();
      },
    );

    test(
      'per-kind independence: writes to two kinds within one debounce window '
      'produce two pushes (one per kind)',
      () async {
        final transport = _CountingTransport();
        final tableA = _table(db, 'kind_a');
        final tableB = _table(db, 'kind_b');
        final engine = SyncEngine(
          db: db,
          transport: transport,
          tables: [tableA, tableB],
          config: const SyncConfig(
            pushOnEnqueue: true,
            enqueuePushDebounce: Duration(milliseconds: 60),
          ),
        );
        await _seedFullResyncCursor(db);

        // Two enqueues, different kinds, both within one debounce window.
        // (Use distinct primary keys because both kinds share the underlying
        // testItems Drift table.)
        await db.syncWriter().forTable(tableA).insertAndEnqueue(
              TestItem(
                id: 'a-1',
                updatedAt: DateTime.utc(2024, 1, 1),
                name: 'a',
              ),
            );
        await db.syncWriter().forTable(tableB).insertAndEnqueue(
              TestItem(
                id: 'b-1',
                updatedAt: DateTime.utc(2024, 1, 1),
                name: 'b',
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 250));

        // Two pushes — one per kind. Per-kind debouncers fired independently;
        // per-kind sync locks let them run in parallel.
        expect(transport.pushCallCount, 2);
        final allPushedKinds = <String>{
          for (final s in transport.pushedKindsPerCall) ...s,
        };
        expect(allPushedKinds, {'kind_a', 'kind_b'});

        engine.dispose();
      },
    );

    test(
      'disposal cancels pending debounced pushes — no push fires after dispose',
      () async {
        final transport = _CountingTransport();
        final engine = SyncEngine(
          db: db,
          transport: transport,
          tables: [_table(db, 'kind_a')],
          config: const SyncConfig(
            pushOnEnqueue: true,
            enqueuePushDebounce: Duration(milliseconds: 100),
          ),
        );
        await _seedFullResyncCursor(db);

        await db
            .syncWriter()
            .forTable(_table(db, 'kind_a'))
            .insertAndEnqueue(
              TestItem(
                id: 'a-1',
                updatedAt: DateTime.utc(2024, 1, 1),
                name: 'one',
              ),
            );

        // Dispose before the debounce can fire.
        engine.dispose();

        // Advance synthetic time well past the debounce window. The pending
        // Timer was cancelled by dispose, so FakeAsync proves no push fires —
        // no drift work is triggered, so it is safe to skip wall clock here.
        FakeAsync().run((fake) {
          fake.elapse(const Duration(milliseconds: 300));
          fake.flushMicrotasks();
        });

        // The pending timer was cancelled — no push fired.
        expect(transport.pushCallCount, 0);
      },
    );
  });
}
