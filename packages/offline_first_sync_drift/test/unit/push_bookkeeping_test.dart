// What PushService does with the local database after the transport
// answered a batch: mirror the server rows, acknowledge, record failures,
// re-base what is still queued. It used to be one implicit transaction per
// statement and one UPDATE per pushed op; these tests pin down that it is
// one transaction per batch, that a batch is applied atomically, and that a
// transport which does not answer an op cannot keep the push loop spinning.
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

const _kind = 'test_item';
final _v0 = DateTime.utc(2026, 4, 30, 8);

/// Counts the statements and transactions that reach the database.
class _Counter extends QueryInterceptor {
  int transactions = 0;
  int batches = 0;
  final List<String> writes = [];

  void reset() {
    transactions = 0;
    batches = 0;
    writes.clear();
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    return super.beginTransaction(parent);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    batches++;
    return super.runBatched(executor, statements);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    writes.add(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    writes.add(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    writes.add(statement);
    return super.runCustom(executor, statement, args);
  }
}

/// A transport whose answer to `push` is scripted per test.
class _ScriptedTransport implements TransportAdapter {
  _ScriptedTransport(this.answer);

  BatchPushResult Function(List<Op> ops) answer;
  int pushCalls = 0;
  var _clock = DateTime.utc(2026, 5, 1, 12, 0, 0, 0, 111);

  Map<String, Object?> accepted(Op op) => {
    ...(op as UpsertOp).payloadJson,
    'updated_at': (_clock = _clock.add(
      const Duration(seconds: 1, microseconds: 7),
    )).toIso8601String(),
  };

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    pushCalls++;
    return answer(ops);
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
  Future<PushResult> forcePush(Op op) async => const PushSuccess();

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

UpsertOp _op(int n, {required String id, DateTime? base}) => UpsertOp(
  opId: 'op-$n',
  kind: _kind,
  id: id,
  localTimestamp: DateTime.utc(2026, 5, 1).add(Duration(seconds: n)),
  payloadJson: {
    'id': id,
    'name': 'edit $n',
    'updated_at': _v0.toIso8601String(),
  },
  baseUpdatedAt: base ?? _v0,
);

void main() {
  late _Counter counter;
  late TestDatabase db;
  late StreamController<SyncEvent> events;
  late _ScriptedTransport transport;

  setUp(() {
    counter = _Counter();
    db = TestDatabase(NativeDatabase.memory().interceptWith(counter));
    events = StreamController<SyncEvent>.broadcast();
    transport = _ScriptedTransport((ops) => const BatchPushResult(results: []));
  });

  tearDown(() async {
    await db.close();
    await events.close();
  });

  PushService service({SyncConfig config = const SyncConfig()}) {
    final tables = <String, SyncableTable<dynamic>>{
      _kind: SyncableTable<TestItem>(
        kind: _kind,
        table: db.testItems,
        fromJson: TestItem.fromJson,
        toJson: (e) => e.toJson(),
        toInsertable: (e) => e.toInsertable(),
        getId: (e) => e.id,
        getUpdatedAt: (e) => e.updatedAt,
      ),
    };
    return PushService(
      db: db,
      outbox: OutboxService(db),
      transport: transport,
      conflictService: ConflictService<TestDatabase>(
        db: db,
        transport: transport,
        tables: tables,
        config: config,
        tableConflictConfigs: const {},
        events: events,
      ),
      tables: tables,
      config: config,
      events: events,
    );
  }

  BatchPushResult acceptAll(List<Op> ops) => BatchPushResult(
    results: [
      for (final op in ops)
        OpPushResult(
          opId: op.opId,
          result: PushSuccess(serverData: transport.accepted(op)),
        ),
    ],
  );

  Future<int> tryCountOf(String opId) async {
    final row = await db
        .customSelect(
          'SELECT try_count FROM sync_outbox WHERE op_id = ?',
          variables: [Variable.withString(opId)],
        )
        .getSingle();
    return row.read<int>('try_count');
  }

  group('a transport that does not answer an op', () {
    test('ends the push instead of pushing the op again and again', () async {
      await db.enqueue(_op(1, id: 'a'));
      // Guard: the loop this test is about never ends on its own.
      transport.answer = (ops) {
        if (transport.pushCalls > 20) throw StateError('still pushing');
        return const BatchPushResult(results: []);
      };

      final stats = await service().pushAll();

      expect(transport.pushCalls, 1);
      expect(stats.pushed, 0);
      expect(stats.errors, 1);
    });

    test('counts as a failed attempt of that op only', () async {
      await db.enqueue(_op(1, id: 'a'));
      await db.enqueue(_op(2, id: 'b'));
      transport.answer = (ops) {
        if (transport.pushCalls > 20) throw StateError('still pushing');
        return BatchPushResult(
          results: [
            for (final op in ops)
              if (op.id != 'b')
                OpPushResult(
                  opId: op.opId,
                  result: PushSuccess(serverData: transport.accepted(op)),
                ),
          ],
        );
      };
      final failures = <OperationFailedEvent>[];
      final sub = events.stream
          .where((e) => e is OperationFailedEvent)
          .cast<OperationFailedEvent>()
          .listen(failures.add);
      addTearDown(sub.cancel);

      final stats = await service().pushAll();
      await pumpEventQueue();

      expect(stats.pushed, 1);
      expect(stats.errors, 1);
      expect((await db.takeOutbox()).map((op) => op.opId), ['op-2']);
      expect(await tryCountOf('op-2'), 1);
      expect(failures.single.opId, 'op-2');
      expect(failures.single.error, isA<TransportException>());
    });

    test('a result for an op that was not pushed still fails loudly', () async {
      await db.enqueue(_op(1, id: 'a'));
      transport.answer = (ops) => const BatchPushResult(
        results: [OpPushResult(opId: 'someone-else', result: PushSuccess())],
      );

      await expectLater(
        service().pushAll(),
        throwsA(
          isA<SyncOperationException>().having(
            (e) => '${e.cause}',
            'cause',
            contains('someone-else'),
          ),
        ),
      );
    });
  });

  group('after a batch was pushed', () {
    test('server rows, acknowledgement and re-base share one transaction, '
        'and only entities with queued ops are re-based', () async {
      // Five entities; only `a` has a second op waiting behind the first.
      var n = 0;
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        await db.enqueue(_op(++n, id: id));
      }
      await db.enqueue(_op(++n, id: 'a'));
      transport.answer = (ops) {
        // Look at the first batch only: the second one pushes what is left.
        if (transport.pushCalls == 2) counter.reset();
        return acceptAll(ops);
      };
      counter.reset();

      // A page of five: the first batch is a..e, the second is a's other op.
      final stats = await service(config: const SyncConfig(pageSize: 5))
          .pushAll();

      expect(stats.pushed, 6);
      expect(transport.pushCalls, 2);
      // Second batch: one row written back, one op acknowledged, nothing left
      // to re-base — in one transaction.
      expect(counter.transactions, 1);
      expect(
        counter.writes.where((w) => w.startsWith('UPDATE sync_outbox')),
        isEmpty,
      );
    });

    test(
      'the first batch re-bases exactly the entity that has more queued',
      () async {
        var n = 0;
        for (final id in ['a', 'b', 'c', 'd', 'e']) {
          await db.enqueue(_op(++n, id: id));
        }
        await db.enqueue(_op(++n, id: 'a'));
        var firstBatchWrites = <String>[];
        var firstBatchTransactions = 0;
        transport.answer = (ops) {
          if (transport.pushCalls == 2) {
            firstBatchWrites = [...counter.writes];
            firstBatchTransactions = counter.transactions;
          }
          return acceptAll(ops);
        };
        counter.reset();

        await service(config: const SyncConfig(pageSize: 5)).pushAll();

        expect(firstBatchTransactions, 1);
        expect(
          firstBatchWrites.where((w) => w.startsWith('UPDATE sync_outbox')),
          hasLength(1),
          reason: 'five ops were pushed, one entity has another op queued',
        );
      },
    );

    test(
      'an op enqueued while the batch was in flight is re-based too',
      () async {
        await db.enqueue(_op(1, id: 'a'));
        transport.answer = (ops) {
          if (transport.pushCalls == 1) {
            // The user edits `a` again while op-1 is on the wire: the edit is
            // based on the version the app still has, v0.
            unawaited(db.enqueue(_op(2, id: 'a')));
          }
          return acceptAll(ops);
        };
        final pushedBases = <DateTime?>[];
        final inner = transport.answer;
        transport.answer = (ops) {
          pushedBases.addAll(ops.map((op) => (op as UpsertOp).baseUpdatedAt));
          return inner(ops);
        };

        final stats = await service().pushAll();

        expect(stats.pushed, 2);
        expect(pushedBases.first, _v0);
        expect(
          pushedBases.last,
          isNot(_v0),
          reason: 'op-2 must carry the version op-1 produced',
        );
      },
    );

    test(
      'a server row that cannot be stored rolls the whole batch back',
      () async {
        await db.enqueue(_op(1, id: 'a'));
        await db.enqueue(_op(2, id: 'b'));
        transport.answer = (ops) => BatchPushResult(
          results: [
            for (final op in ops)
              OpPushResult(
                opId: op.opId,
                result: PushSuccess(
                  serverData: op.id == 'b'
                      // `name` is required: TestItem.fromJson throws.
                      ? {'id': 'b', 'updated_at': _v0.toIso8601String()}
                      : transport.accepted(op),
                ),
              ),
          ],
        );

        await expectLater(
          service().pushAll(),
          throwsA(isA<SyncOperationException>()),
        );

        // Neither half-applied: `a` was not mirrored while its op is still
        // queued with the old base.
        expect(await db.select(db.testItems).get(), isEmpty);
        expect((await db.takeOutbox()).map((op) => op.opId), ['op-1', 'op-2']);
      },
    );

    test('OperationPushedEvent arrives when the batch is gone from the outbox '
        'and the local rows carry the server versions', () async {
      await db.enqueue(_op(1, id: 'a'));
      await db.enqueue(_op(2, id: 'b'));
      transport.answer = acceptAll;
      final seen = <String>[];
      final sub = events.stream
          .where((e) => e is OperationPushedEvent)
          .cast<OperationPushedEvent>()
          .listen((event) async {
            final queued = await db.takeOutbox();
            final rows = await db.select(db.testItems).get();
            final mirrored = rows.where((r) => r.updatedAt.isAfter(_v0));
            seen.add(
              '${event.entityId}: queued=${queued.length} '
              'mirrored=${mirrored.length}',
            );
          });
      addTearDown(sub.cancel);

      await service().pushAll();
      await pumpEventQueue();

      expect(seen, ['a: queued=0 mirrored=2', 'b: queued=0 mirrored=2']);
    });
  });

  group('rebaseQueuedOutboxOps', () {
    final v1 = DateTime.utc(2026, 5, 2, 9, 0, 0, 0, 123);

    Future<Map<String, DateTime?>> bases() async => {
      for (final op in await db.takeOutbox(limit: 5000))
        op.opId: switch (op) {
          UpsertOp(:final baseUpdatedAt) => baseUpdatedAt,
          DeleteOp(:final baseUpdatedAt) => baseUpdatedAt,
        },
    };

    test(
      're-bases the queued ops of the given entities and nothing else',
      () async {
        await db.enqueue(_op(1, id: 'a'));
        await db.enqueue(_op(2, id: 'a'));
        await db.enqueue(_op(3, id: 'b'));
        await db.enqueue(
          UpsertOp(
            opId: 'op-4',
            kind: 'other_kind',
            id: 'a',
            localTimestamp: DateTime.utc(2026, 5, 1, 0, 0, 4),
            payloadJson: const {'id': 'a'},
            baseUpdatedAt: _v0,
          ),
        );

        final rebased = await db.rebaseQueuedOutboxOps({
          (_kind, 'a'): v1,
          (_kind, 'not-queued'): v1,
        });

        expect(rebased, 2);
        expect(await bases(), {
          'op-1': v1,
          'op-2': v1,
          'op-3': _v0,
          'op-4': _v0,
        });
      },
    );

    test(
      'leaves ops without a base alone (create, fail if it exists)',
      () async {
        await db.enqueue(
          UpsertOp(
            opId: 'op-1',
            kind: _kind,
            id: 'a',
            localTimestamp: DateTime.utc(2026, 5, 1),
            payloadJson: const {'id': 'a'},
          ),
        );

        final rebased = await db.rebaseQueuedOutboxOps({(_kind, 'a'): v1});

        expect(rebased, 0);
        expect(await bases(), {'op-1': null});
      },
    );

    test('handles more entities than SQLite takes variables', () async {
      const total = 1200;
      await db.batch((b) {
        b.insertAll(db.syncOutbox, [
          for (var i = 0; i < total; i++)
            SyncOutboxCompanion.insert(
              opId: 'op-$i',
              kind: _kind,
              entityId: 'e-$i',
              op: 'upsert',
              ts: 1000 + i,
              payload: const Value('{}'),
              baseUpdatedAt: Value(_v0.microsecondsSinceEpoch),
            ),
        ]);
      });

      final rebased = await db.rebaseQueuedOutboxOps({
        for (var i = 0; i < total; i++) (_kind, 'e-$i'): v1,
      });

      expect(rebased, total);
      expect((await bases()).values.toSet(), {v1});
    });

    test('an empty map is a no-op', () async {
      expect(await db.rebaseQueuedOutboxOps(const {}), 0);
    });
  });

  group('recordOutboxFailures', () {
    test('stores the metadata of all ops in one batched statement', () async {
      for (var n = 1; n <= 4; n++) {
        await db.enqueue(_op(n, id: 'e-$n'));
      }
      counter.reset();

      await db.recordOutboxFailures({
        for (var n = 1; n <= 4; n++) 'op-$n': 'boom $n',
      });

      expect(counter.batches, 1);
      expect(
        counter.writes.where((w) => w.contains('sync_outbox_meta')),
        isEmpty,
        reason: 'one round trip per failed op',
      );
      final meta = await db.select(db.syncOutboxMeta).get();
      expect(
        {for (final m in meta) m.opId: m.lastError},
        {for (var n = 1; n <= 4; n++) 'op-$n': 'boom $n'},
      );
      for (var n = 1; n <= 4; n++) {
        expect(await tryCountOf('op-$n'), 1);
      }
    });
  });
}
