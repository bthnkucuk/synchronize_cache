// A queued delete that meets an edit made on another device.
//
// Under `merge` and `autoPreserve` (the DEFAULT strategy) the conflict was
// answered with `AcceptMerged`, which cannot be pushed for a delete. The op
// was reported unresolved, never counted as an attempt, never became stuck,
// and was sent again by every sync, forever.
import 'package:drift/drift.dart' show Value;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

const _kind = 'test_item';

/// Holds a newer version of `a`: every delete that is not forced conflicts.
class _Server implements TransportAdapter {
  int deleteAttempts = 0;
  int forcedDeletes = 0;

  final Map<String, Object?> current = {
    'id': 'a',
    'name': 'edited on another device',
    'updated_at': '2026-05-02T10:00:00.000Z',
  };

  @override
  Future<BatchPushResult> push(List<Op> ops) async => BatchPushResult(
    results: [
      for (final op in ops) OpPushResult(opId: op.opId, result: _answer(op)),
    ],
  );

  PushResult _answer(Op op) {
    if (op is! DeleteOp) return const PushSuccess();
    deleteAttempts++;
    return PushConflict(
      serverData: current,
      serverTimestamp: DateTime.utc(2026, 5, 2, 10),
    );
  }

  @override
  Future<PushResult> forcePush(Op op) async {
    forcedDeletes++;
    return const PushSuccess();
  }

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async => const PullPage(items: []);

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

void main() {
  late TestDatabase db;
  late _Server server;

  setUp(() {
    db = TestDatabase();
    server = _Server();
  });

  tearDown(() => db.close());

  SyncEngine<TestDatabase> engineWith(SyncConfig config) {
    final engine = SyncEngine<TestDatabase>(
      db: db,
      transport: server,
      tables: [
        SyncableTable<TestItem>(
          kind: _kind,
          table: db.testItems,
          fromJson: TestItem.fromJson,
          toJson: (e) => e.toJson(),
          toInsertable: (e) => e.toInsertable(),
          getId: (e) => e.id,
          getUpdatedAt: (e) => e.updatedAt,
        ),
      ],
      config: config,
    );
    addTearDown(engine.dispose);
    return engine;
  }

  /// The row as the app left it: soft-deleted locally, delete queued.
  Future<void> deleteLocally() async {
    await db
        .into(db.testItems)
        .insert(
          TestItemsCompanion.insert(
            id: 'a',
            name: 'before the edit',
            updatedAt: DateTime.utc(2026, 5, 1),
            deletedAtLocal: Value(DateTime.utc(2026, 5, 3)),
          ),
        );
    await db.enqueue(
      DeleteOp(
        opId: 'del-a',
        kind: _kind,
        id: 'a',
        localTimestamp: DateTime.utc(2026, 5, 3),
        baseUpdatedAt: DateTime.utc(2026, 5, 1),
      ),
    );
  }

  for (final strategy in [
    ConflictStrategy.autoPreserve,
    ConflictStrategy.merge,
  ]) {
    test('${strategy.name}: the edit survives, the delete is dropped, and the '
        'op is not sent again', () async {
      await deleteLocally();
      final engine = engineWith(SyncConfig(conflictStrategy: strategy));
      final merged = <DataMergedEvent>[];
      final sub = engine.events
          .where((e) => e is DataMergedEvent)
          .cast<DataMergedEvent>()
          .listen(merged.add);
      addTearDown(sub.cancel);

      final first = await engine.sync();
      await engine.sync();
      await engine.sync();

      expect(first.conflicts, 1);
      expect(first.conflictsResolved, 1);
      expect(server.deleteAttempts, 1, reason: 'later syncs have nothing left');
      expect(server.forcedDeletes, 0, reason: 'the edit must not be deleted');
      expect(await db.takeOutbox(), isEmpty);

      // The row is back, as the other device left it.
      final row = await db.select(db.testItems).getSingle();
      expect(row.name, 'edited on another device');
      expect(row.deletedAtLocal, isNull);

      // Nothing was merged, so no merge is announced.
      expect(merged, isEmpty);
    });
  }

  test('clientWins still deletes, serverWins still keeps', () async {
    await deleteLocally();
    await engineWith(
      const SyncConfig(conflictStrategy: ConflictStrategy.clientWins),
    ).sync();
    expect(server.forcedDeletes, 1);
    expect(await db.takeOutbox(), isEmpty);
  });

  test('a manual resolver that answers AcceptMerged for a delete keeps the '
      'server version instead of leaving the op unresolved', () async {
    await deleteLocally();
    final engine = engineWith(
      SyncConfig(
        conflictStrategy: ConflictStrategy.manual,
        conflictResolver: (conflict) async =>
            AcceptMerged({...conflict.serverData}),
      ),
    );

    final stats = await engine.sync();

    expect(stats.conflictsResolved, 1);
    expect(server.forcedDeletes, 0);
    expect(await db.takeOutbox(), isEmpty);
    expect(
      (await db.select(db.testItems).getSingle()).name,
      'edited on another device',
    );
  });
}
