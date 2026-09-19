// The outbox is a queue the engine reads once per batch and updates once per
// pushed op. Without indexes each of those statements scans (and sorts) the
// whole queue, so draining N ops costs O(N²). These tests pin down that:
//  * new databases get the indexes, old ones get them without a migration;
//  * the statements the push path really issues are served by them.
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift/src/tables/outbox.drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

const _kind = 'test_item';

const _indexNames = [
  'idx_sync_outbox_kind_entity',
  'idx_sync_outbox_kind_ts',
  'idx_sync_outbox_ts',
];

/// A database as an older version of this package created it: the sync
/// tables exist, the outbox indexes do not.
class _LegacyDatabase extends TestDatabase {
  _LegacyDatabase([super.executor]);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final table in allTables) {
        await m.createTable(table);
      }
    },
  );
}

/// Records every statement that reaches the database; optionally fails the
/// ones matching [failWhen].
class _Recorder extends QueryInterceptor {
  final List<(String, List<Object?>)> statements = [];
  bool Function(String statement)? failWhen;

  void _see(String statement, List<Object?> args) {
    statements.add((statement, args));
    if (failWhen?.call(statement) ?? false) {
      throw StateError('refused: $statement');
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(statement, args);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(statement, args);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(statement, args);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _see(statement, args);
    return super.runCustom(executor, statement, args);
  }
}

/// Acknowledges every op and returns the row with a fresh server version.
class _AcceptingServer implements TransportAdapter {
  var _clock = DateTime.utc(2026, 5, 1, 12);

  @override
  Future<BatchPushResult> push(List<Op> ops) async => BatchPushResult(
    results: [
      for (final op in ops)
        OpPushResult(
          opId: op.opId,
          result: switch (op) {
            UpsertOp() => PushSuccess(
              serverData: {
                ...op.payloadJson,
                'updated_at': (_clock = _clock.add(
                  const Duration(seconds: 1),
                )).toIso8601String(),
              },
            ),
            DeleteOp() => const PushSuccess(),
          },
        ),
    ],
  );

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
  Future<PushResult> forcePush(Op op) async => const PushSuccess();

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

Future<List<String>> _outboxIndexes(GeneratedDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = 'sync_outbox' AND name LIKE 'idx_%' ORDER BY name",
      )
      .get();
  return [for (final row in rows) row.read<String>('name')];
}

Future<List<String>> _planOf(
  GeneratedDatabase db,
  String statement,
  List<Object?> args,
) async {
  final rows = await db
      .customSelect(
        'EXPLAIN QUERY PLAN $statement',
        variables: [for (final arg in args) Variable<Object>(arg!)],
      )
      .get();
  return [for (final row in rows) row.read<String>('detail')];
}

SyncEngine<TestDatabase> _engine(TestDatabase db, TransportAdapter transport) =>
    SyncEngine(
      db: db,
      transport: transport,
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
      // The scheduled full resync pushes without a kind filter; keep it out
      // of the way unless a test asks for it.
      config: const SyncConfig(fullResyncInterval: Duration(days: 3650)),
    );

UpsertOp _op(int n, {required String id, String kind = _kind}) => UpsertOp(
  opId: 'op-$n',
  kind: kind,
  id: id,
  localTimestamp: DateTime.utc(2026, 5, 1).add(Duration(seconds: n)),
  payloadJson: {
    'id': id,
    'name': 'edit $n',
    'updated_at': '2026-05-01T00:00:00.000Z',
  },
  baseUpdatedAt: DateTime.utc(2026, 4, 30),
);

void main() {
  group('outbox indexes', () {
    test('a new database is created with them', () async {
      final db = TestDatabase();
      addTearDown(db.close);

      expect(await _outboxIndexes(db), _indexNames);
    });

    test('ensureSyncIndexes adds them to a database created without them '
        'and can be repeated', () async {
      final db = _LegacyDatabase();
      addTearDown(db.close);
      expect(await _outboxIndexes(db), isEmpty);

      await db.ensureSyncIndexes();
      await db.ensureSyncIndexes();

      expect(await _outboxIndexes(db), _indexNames);
    });

    test('a migration that creates them afterwards is harmless', () async {
      final db = _LegacyDatabase();
      addTearDown(db.close);
      await db.ensureSyncIndexes();

      final migrator = db.createMigrator();
      await migrator.createIndex(idxSyncOutboxKindTs);
      await migrator.createIndex(idxSyncOutboxTs);
      await migrator.createIndex(idxSyncOutboxKindEntity);
      await migrator.createAll();

      expect(await _outboxIndexes(db), _indexNames);
    });

    test('SyncEngine creates them before its first sync', () async {
      final db = _LegacyDatabase();
      addTearDown(db.close);
      final engine = _engine(db, _AcceptingServer());
      addTearDown(engine.dispose);

      await engine.sync();

      expect(await _outboxIndexes(db), _indexNames);
    });

    test('fullResync creates them as well', () async {
      final db = _LegacyDatabase();
      addTearDown(db.close);
      final engine = _engine(db, _AcceptingServer());
      addTearDown(engine.dispose);

      await engine.fullResync();

      expect(await _outboxIndexes(db), _indexNames);
    });

    test('a database that refuses them still syncs, and the engine tries '
        'again with the next sync', () async {
      final recorder = _Recorder()
        ..failWhen = (statement) => statement.startsWith('CREATE INDEX');
      final db = _LegacyDatabase(
        NativeDatabase.memory().interceptWith(recorder),
      );
      addTearDown(db.close);
      final engine = _engine(db, _AcceptingServer());
      addTearDown(engine.dispose);
      await db.enqueue(_op(1, id: 'a'));

      final stats = await engine.sync();

      expect(stats.pushed, 1);
      expect(await _outboxIndexes(db), isEmpty);

      recorder.failWhen = null;
      await engine.sync();

      expect(await _outboxIndexes(db), _indexNames);
    });

    test('the engine asks for them once, not before every sync', () async {
      final recorder = _Recorder();
      final db = TestDatabase(NativeDatabase.memory().interceptWith(recorder));
      addTearDown(db.close);
      final engine = _engine(db, _AcceptingServer());
      addTearDown(engine.dispose);

      int asked() => recorder.statements
          .where((s) => s.$1.startsWith('CREATE INDEX IF NOT EXISTS'))
          .length;

      await engine.sync();
      final afterFirstSync = asked();
      await engine.sync();
      await engine.fullResync();

      expect(afterFirstSync, _indexNames.length);
      expect(asked(), afterFirstSync);
    });
  });

  group('outbox statements of the push path', () {
    late _Recorder recorder;
    late TestDatabase db;
    late SyncEngine<TestDatabase> engine;

    setUp(() async {
      recorder = _Recorder();
      db = TestDatabase(NativeDatabase.memory().interceptWith(recorder));
      engine = _engine(db, _AcceptingServer());
      // The first sync of a database is a full resync, which pushes without
      // a kind filter. Get it out of the way: `sync()` is per kind from now on.
      await engine.fullResync();
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    /// Queues edits for several entities (two of them edited more than once,
    /// so the re-base has work to do) plus ops of another kind.
    Future<void> seed() async {
      var n = 0;
      for (final id in ['a', 'b', 'a', 'c', 'b', 'a']) {
        await db.enqueue(_op(++n, id: id));
      }
      await db.enqueue(_op(++n, id: 'x', kind: 'other_kind'));
      recorder.statements.clear();
    }

    Future<void> expectIndexed(bool Function(String statement) which) async {
      final matching = recorder.statements.where((s) => which(s.$1)).toList();
      expect(matching, isNotEmpty, reason: 'no such statement was issued');
      recorder.statements.clear();

      for (final (statement, args) in matching) {
        final plan = await _planOf(db, statement, args);
        final reason = '$statement\n  plan: $plan';
        expect(
          plan.where((step) => step.contains('TEMP B-TREE')),
          isEmpty,
          reason: 'sorts the queue: $reason',
        );
        for (final step in plan.where((s) => s.contains('sync_outbox'))) {
          expect(step, contains('INDEX'), reason: 'scans the queue: $reason');
        }
      }
    }

    test('taking the next batch of one kind walks (kind, ts)', () async {
      await seed();

      await engine.sync();

      await expectIndexed(
        (s) =>
            s.startsWith('SELECT * FROM sync_outbox') &&
            s.contains('LIMIT') &&
            s.contains('kind IN'),
      );
    });

    test('taking the next batch of every kind walks (ts)', () async {
      await seed();

      await engine.fullResync();

      await expectIndexed(
        (s) =>
            s.startsWith('SELECT * FROM sync_outbox') &&
            s.contains('LIMIT') &&
            !s.contains('kind IN'),
      );
    });

    test('finding and re-basing the ops still queued for a pushed entity '
        'uses (kind, entity_id)', () async {
      await seed();

      await engine.sync();

      await expectIndexed(
        (s) => s.contains('sync_outbox') && s.contains('entity_id'),
      );
    });

    test('acknowledging ops is a primary key lookup', () async {
      await seed();

      await engine.sync();

      await expectIndexed((s) => s.startsWith('DELETE FROM sync_outbox'));
    });

    test('purging old ops uses (ts)', () async {
      await seed();

      await db.purgeOutboxOlderThan(DateTime.utc(2026, 5, 1, 0, 0, 3));

      await expectIndexed((s) => s.startsWith('DELETE FROM sync_outbox'));
    });

    test('the queue drains completely and in order', () async {
      await seed();

      final stats = await engine.sync();

      expect(stats.pushed, 6);
      final left = await db.takeOutbox();
      expect(left.map((op) => op.kind), ['other_kind']);
    });
  });
}
