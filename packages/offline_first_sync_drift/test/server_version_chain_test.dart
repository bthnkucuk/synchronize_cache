// How the push path decides which server version an op is based on.
//
// The server in these tests follows the documented protocol to the letter
// (docs/backend-transport.md): it stores `updated_at` with microsecond
// precision, bumps it on every write, and answers 409 whenever
// `existing.updated_at != _baseUpdatedAt`.
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import 'fixtures/test_database.dart';

const _kind = 'test_item';

DateTime? _baseOf(Op op) => switch (op) {
  UpsertOp(:final baseUpdatedAt) => baseUpdatedAt,
  DeleteOp(:final baseUpdatedAt) => baseUpdatedAt,
};

/// An in-memory server with exact-match optimistic concurrency.
class _ExactMatchServer implements TransportAdapter {
  final Map<String, Map<String, Object?>> rows = {};

  /// Every op in the order it reached the server (push and force push).
  final List<Op> dispatched = [];

  /// How many ops each `push` call carried.
  final List<int> batchSizes = [];

  /// Ids whose (non-forced) push fails with a server error.
  final Set<String> failingIds = {};

  /// When false the server answers a successful write without a body.
  bool returnsRow = true;

  /// Rows handed out by the next `pull`.
  List<Map<String, Object?>> nextPull = [];

  int conflicts = 0;

  // Microsecond precision, like PostgreSQL `timestamptz` or `DateTime.now()`.
  DateTime _clock = DateTime.utc(2026, 5, 1, 12, 0, 0, 0, 111);

  DateTime versionOf(String id) =>
      DateTime.parse(rows[id]!['updated_at']! as String);

  /// A write by another client: bumps the version behind our back.
  DateTime writeAsAnotherClient(String id, String name) {
    rows[id] = {'id': id, 'name': name, 'updated_at': _tick()};
    return versionOf(id);
  }

  String _tick() {
    _clock = _clock.add(const Duration(seconds: 1, microseconds: 7));
    return _clock.toIso8601String();
  }

  PushResult _apply(Op op, {required bool force}) {
    dispatched.add(op);
    if (!force && failingIds.contains(op.id)) {
      return PushError(StateError('server error for ${op.id}'));
    }

    final current = rows[op.id];
    final base = _baseOf(op);
    if (!force && current != null && base != null && versionOf(op.id) != base) {
      conflicts++;
      return PushConflict(
        serverData: current,
        serverTimestamp: versionOf(op.id),
      );
    }

    if (op is! UpsertOp) {
      rows.remove(op.id);
      return const PushSuccess();
    }
    final row = {...op.payloadJson, 'updated_at': _tick()};
    rows[op.id] = row;
    return returnsRow ? PushSuccess(serverData: row) : const PushSuccess();
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    batchSizes.add(ops.length);
    return BatchPushResult(
      results: [
        for (final op in ops)
          OpPushResult(opId: op.opId, result: _apply(op, force: false)),
      ],
    );
  }

  @override
  Future<PushResult> forcePush(Op op) async => _apply(op, force: true);

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    final items = nextPull;
    nextPull = [];
    return PullPage(items: items);
  }

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

void main() {
  late TestDatabase db;
  late _ExactMatchServer server;
  late SyncableTable<TestItem> table;
  late SyncEntityWriter<TestItem, TestDatabase> writer;

  setUp(() {
    db = TestDatabase();
    server = _ExactMatchServer();
    table = SyncableTable<TestItem>(
      kind: _kind,
      table: db.testItems,
      fromJson: TestItem.fromJson,
      toJson: (item) => item.toJson(),
      toInsertable: (item) => item.toInsertable(),
      getId: (item) => item.id,
      getUpdatedAt: (item) => item.updatedAt,
    );
    writer = SyncWriter<TestDatabase>(db).forTable(table);
  });

  tearDown(() => db.close());

  SyncEngine<TestDatabase> engine({SyncConfig config = const SyncConfig()}) {
    final engine = SyncEngine<TestDatabase>(
      db: db,
      transport: server,
      tables: [table],
      config: config,
    );
    addTearDown(engine.dispose);
    return engine;
  }

  Future<TestItem> local(String id) async => (await (db.select(
    db.testItems,
  )..where((t) => t.id.equals(id))).get()).single;

  /// Creates an item and syncs it, so the local row carries the server version.
  Future<TestItem> createSynced(
    SyncEngine<TestDatabase> engine,
    String id,
  ) async {
    await writer.insertAndEnqueue(
      TestItem(id: id, name: 'created', updatedAt: DateTime.now().toUtc()),
    );
    await engine.sync(pullKinds: const {});
    final synced = await local(id);
    expect(synced.updatedAt, server.versionOf(id), reason: 'write-back');
    return synced;
  }

  /// An app that, like most, stamps `updatedAt` with "now" on every edit and
  /// passes the version it edited as the base.
  Future<void> editLikeAnApp(String id, String name) async {
    final before = await local(id);
    await writer.replaceAndEnqueue(
      TestItem(id: id, name: name, updatedAt: DateTime.now().toUtc()),
      baseUpdatedAt: before.updatedAt,
      changedFields: {'name'},
    );
  }

  group('an app that bumps updatedAt on every edit', () {
    test('an edit after sync is accepted without a conflict', () async {
      // Regression (K1-10): the base used to be overwritten with the local
      // row's `updated_at` just before dispatch. The edit itself had set that
      // column to "now", so every edit was rejected as a conflict although
      // nobody else had touched the entity.
      final e = engine();
      final synced = await createSynced(e, 'a');

      await editLikeAnApp('a', 'edited');
      final stats = await e.sync(pullKinds: const {});

      expect(server.conflicts, 0);
      expect(stats.conflicts, 0);
      expect(stats.pushed, 1);
      expect(_baseOf(server.dispatched.last), synced.updatedAt);
      expect(server.rows['a']!['name'], 'edited');
    });

    test('several edits before one sync are chained, in one run', () async {
      // Each edit is based on the row the previous edit left behind, whose
      // `updated_at` is a local clock value. Only the first base is a real
      // server version; the others must be re-based as the chain advances.
      final e = engine();
      await createSynced(e, 'a');

      await editLikeAnApp('a', 'first');
      await editLikeAnApp('a', 'second');
      await editLikeAnApp('a', 'third');
      final stats = await e.sync(pullKinds: const {});

      expect(server.conflicts, 0);
      expect(stats.pushed, 3);
      expect(server.rows['a']!['name'], 'third');
      expect((await local('a')).updatedAt, server.versionOf('a'));
      expect(await db.takeOutbox(), isEmpty);
    });
  });

  group('ops of one entity', () {
    test('reach the server one per batch, oldest first, with the default '
        'page size', () async {
      final e = engine();
      await createSynced(e, 'a');
      await createSynced(e, 'b');
      server.dispatched.clear();
      server.batchSizes.clear();

      await editLikeAnApp('a', 'a-1');
      await editLikeAnApp('b', 'b-1');
      await editLikeAnApp('a', 'a-2');
      await e.sync(pullKinds: const {});

      // First pass: the first op of each entity. Second pass: the rest.
      expect(server.batchSizes, [2, 1]);
      expect(
        [
          for (final op in server.dispatched)
            (op as UpsertOp).payloadJson['name'],
        ],
        ['a-1', 'b-1', 'a-2'],
      );
      expect(server.conflicts, 0);
    });

    test(
      'a later op is based on the version the earlier one produced',
      () async {
        final e = engine();
        await createSynced(e, 'a');
        server.dispatched.clear();

        await editLikeAnApp('a', 'first');
        await editLikeAnApp('a', 'second');

        final versions = <DateTime>[];
        final subscription = e.events.listen((event) {
          if (event is OperationPushedEvent) {
            versions.add(server.versionOf('a'));
          }
        });
        addTearDown(subscription.cancel);
        await e.sync(pullKinds: const {});

        expect(server.dispatched, hasLength(2));
        expect(
          _baseOf(server.dispatched[1]),
          versions.first,
          reason: 'the version the server assigned to the first edit',
        );
      },
    );

    test('are not sent past one that failed', () async {
      // Applying "second" while "first" is still queued would let the older
      // payload overwrite the newer one when "first" is retried.
      final e = engine();
      await createSynced(e, 'a');
      server.dispatched.clear();

      await editLikeAnApp('a', 'first');
      await editLikeAnApp('a', 'second');
      server.failingIds.add('a');
      await e.sync(pullKinds: const {});

      expect(
        [
          for (final op in server.dispatched)
            (op as UpsertOp).payloadJson['name'],
        ],
        ['first'],
      );
      expect(await db.takeOutbox(), hasLength(2));

      server.failingIds.clear();
      await e.sync(pullKinds: const {});

      expect(server.rows['a']!['name'], 'second');
      expect(server.conflicts, 0);
      expect(await db.takeOutbox(), isEmpty);
    });
  });

  group('another client wrote in the meantime', () {
    test('the conflict is reported even after a pull refreshed the local '
        'row', () async {
      // The base used to be replaced by the local row's `updated_at`. A pull
      // that stored the other client's version there made the queued edit
      // look up to date, and it silently overwrote that client's write.
      final e = engine(
        config: const SyncConfig(conflictStrategy: ConflictStrategy.serverWins),
      );
      final synced = await createSynced(e, 'a');
      server.dispatched.clear();

      await editLikeAnApp('a', 'mine');
      final theirs = server.writeAsAnotherClient('a', 'theirs');
      server.nextPull = [server.rows['a']!];
      await e.sync(pushKinds: const {}, pullKinds: {_kind});
      expect((await local('a')).updatedAt, theirs, reason: 'pulled');

      final stats = await e.sync(pullKinds: const {});

      expect(_baseOf(server.dispatched.first), synced.updatedAt);
      expect(stats.conflicts, 1);
      expect(server.rows['a']!['name'], 'theirs', reason: 'serverWins');
    });

    test(
      'after a merge is force-pushed, the next edit is not a conflict',
      () async {
        // The force push bumps the server version. The local row used to keep
        // the merged data with the version it replaced, so the very next edit
        // conflicted again.
        final e = engine();
        await createSynced(e, 'a');

        await editLikeAnApp('a', 'mine');
        server.writeAsAnotherClient('a', 'theirs');
        final first = await e.sync(pullKinds: const {});
        expect(first.conflicts, 1);
        expect(first.conflictsResolved, 1);
        expect((await local('a')).updatedAt, server.versionOf('a'));

        server.conflicts = 0;
        await editLikeAnApp('a', 'mine again');
        final second = await e.sync(pullKinds: const {});

        expect(server.conflicts, 0);
        expect(second.pushed, 1);
      },
    );

    test('an op queued behind a resolved conflict is re-based too', () async {
      final e = engine();
      await createSynced(e, 'a');

      await editLikeAnApp('a', 'first');
      await editLikeAnApp('a', 'second');
      server.writeAsAnotherClient('a', 'theirs');
      final stats = await e.sync(pullKinds: const {});

      expect(
        stats.conflicts,
        1,
        reason: 'only the first edit really conflicts',
      );
      expect(server.rows['a']!['name'], 'second');
      expect(await db.takeOutbox(), isEmpty);
    });
  });

  group('a server that answers writes without a body', () {
    test('cannot re-base, so a queued follow-up edit is resolved as a '
        'conflict instead of being lost', () async {
      server.returnsRow = false;
      final e = engine();
      await writer.insertAndEnqueue(
        TestItem(id: 'a', name: 'created', updatedAt: DateTime.now().toUtc()),
      );
      await e.sync(pullKinds: const {});

      // No write-back happened: the app only knows its own local timestamp.
      await editLikeAnApp('a', 'edited');
      final stats = await e.sync(pullKinds: const {});

      expect(stats.conflicts, 1);
      expect(stats.conflictsResolved, 1);
      expect(server.rows['a']!['name'], 'edited');
    });
  });

  group('ops enqueued by a version that stored milliseconds', () {
    test('recover the full-precision version from an unchanged local '
        'row', () async {
      final e = engine();
      final synced = await createSynced(e, 'a');
      expect(synced.updatedAt.microsecond, isNot(0));
      server.dispatched.clear();

      final truncated = DateTime.fromMillisecondsSinceEpoch(
        synced.updatedAt.millisecondsSinceEpoch,
        isUtc: true,
      );
      await db.customStatement(
        'INSERT INTO sync_outbox '
        '(op_id, kind, entity_id, op, payload, ts, try_count, base_updated_at) '
        "VALUES ('legacy', '$_kind', 'a', 'upsert', ?, ?, 0, ?)",
        [
          '{"id":"a","name":"legacy edit"}',
          truncated.millisecondsSinceEpoch,
          truncated.millisecondsSinceEpoch,
        ],
      );

      await e.sync(pullKinds: const {});

      expect(_baseOf(server.dispatched.single), synced.updatedAt);
      expect(server.conflicts, 0);
    });
  });
}
