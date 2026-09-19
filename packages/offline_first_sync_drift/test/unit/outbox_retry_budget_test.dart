// `SyncConfig.maxOutboxTryCount` parks an operation the server will never
// accept, so that it cannot hold up the queue forever. It used to count EVERY
// failed push — including "no network". A device that stayed offline (or had
// an expired token, or talked to a server that was down) for five sync
// attempts ended up with all of its queued writes parked as "stuck"; they were
// never sent again, not even once everything worked.
import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

const _kind = 'test_item';

/// Answers every op with whatever [answer] says, like a transport that
/// reports per-op results (RestTransport without the batch API).
class _Server implements TransportAdapter {
  PushResult Function(Op op) answer = (_) => const PushSuccess();
  final List<String> pushedOpIds = [];

  @override
  Future<BatchPushResult> push(List<Op> ops) async => BatchPushResult(
    results: [
      for (final op in ops)
        OpPushResult(opId: op.opId, result: _record(op, answer(op))),
    ],
  );

  PushResult _record(Op op, PushResult result) {
    if (result is PushSuccess) pushedOpIds.add(op.opId);
    return result;
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

UpsertOp _op(String opId, {String? id}) => UpsertOp(
  opId: opId,
  kind: _kind,
  id: id ?? 'entity-$opId',
  localTimestamp: DateTime.utc(2026, 5, 1),
  payloadJson: {'id': id ?? 'entity-$opId', 'name': 'written offline'},
);

void main() {
  late TestDatabase db;
  late _Server server;
  late SyncEngine<TestDatabase> engine;
  const config = SyncConfig();

  setUp(() {
    db = TestDatabase();
    server = _Server();
    engine = SyncEngine<TestDatabase>(
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
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  Future<int> tryCountOf(String opId) async {
    final row = await db
        .customSelect(
          'SELECT try_count FROM sync_outbox WHERE op_id = ?',
          variables: [Variable.withString(opId)],
        )
        .getSingle();
    return row.read<int>('try_count');
  }

  /// More failed syncs than the budget allows.
  Future<void> failingSyncs() async {
    for (var i = 0; i < config.maxOutboxTryCount + 2; i++) {
      await engine.sync();
    }
  }

  group('a failure the operation is not to blame for', () {
    final failures = <String, Object>{
      'no network': const NetworkException('Network request failed'),
      'a timeout': TimeoutException('no answer'),
      'retries exhausted': const MaxRetriesExceededException(
        'Push failed after 5 attempts',
        attempts: 5,
        maxRetries: 5,
      ),
      '401 (expired token)': TransportException.httpError(401),
      '403': TransportException.httpError(403),
      '408': TransportException.httpError(408),
      '429 (rate limited)': TransportException.httpError(429),
      '500': TransportException.httpError(500),
      '503 (server down)': TransportException.httpError(503),
    };

    for (final MapEntry(key: name, value: error) in failures.entries) {
      test(
        '$name — never parks the op, which is sent once things work again',
        () async {
          await db.enqueue(_op('op-1'));
          server.answer = (_) => PushError(error);

          await failingSyncs();

          expect(await tryCountOf('op-1'), 0);
          expect(await engine.getStuckOperations(), isEmpty);

          server.answer = (_) => const PushSuccess();
          final stats = await engine.sync();

          expect(stats.pushed, 1);
          expect(await db.takeOutbox(), isEmpty);
        },
      );
    }

    test('is still reported: counted in the stats, announced as an event '
        'that will be retried, and remembered as the last error', () async {
      await db.enqueue(_op('op-1'));
      server.answer = (_) => PushError(TransportException.httpError(401));
      final events = <OperationFailedEvent>[];
      final sub = engine.events
          .where((e) => e is OperationFailedEvent)
          .cast<OperationFailedEvent>()
          .listen(events.add);
      addTearDown(sub.cancel);

      final stats = await engine.sync();
      await pumpEventQueue();

      expect(stats.errors, 1);
      expect(events.single.willRetry, isTrue);
      expect(events.single.errorInfo.category, SyncErrorCategory.auth);
      final meta = await db.select(db.syncOutboxMeta).getSingle();
      expect(meta.opId, 'op-1');
      expect(meta.lastError, contains('401'));
      expect(meta.lastTriedAt, isNotNull);
    });

    test('ends the push: the rest of the queue is not thrown at it', () async {
      // Three pages of one op each; the first push already says "offline".
      for (final opId in ['op-1', 'op-2', 'op-3']) {
        await db.enqueue(_op(opId));
      }
      var pushCalls = 0;
      server.answer = (_) {
        pushCalls++;
        return const PushError(NetworkException('down'));
      };
      final paged = SyncEngine<TestDatabase>(
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
        config: const SyncConfig(pageSize: 1),
      );
      addTearDown(paged.dispose);

      await paged.sync();

      expect(pushCalls, 1);
    });
  });

  group('a failure that is about the operation', () {
    final failures = <String, Object>{
      '400': TransportException.httpError(400),
      '413': TransportException.httpError(413),
      '422': TransportException.httpError(422),
      'a transport error without a status': const TransportException(
        'Entity id ".." cannot be addressed',
      ),
      'an unexpected error': StateError('cannot serialize'),
    };

    for (final MapEntry(key: name, value: error) in failures.entries) {
      test('$name — uses up the budget and parks the op', () async {
        await db.enqueue(_op('poison'));
        server.answer = (_) => PushError(error);

        await failingSyncs();

        expect(await tryCountOf('poison'), config.maxOutboxTryCount);
        expect((await engine.getStuckOperations()).map((op) => op.opId), [
          'poison',
        ]);

        // Parked means: not sent any more, even when the server would take it.
        server.answer = (_) => const PushSuccess();
        final stats = await engine.sync();
        expect(stats.pushed, 0);
      });
    }

    test('does not hold up the ops queued behind it', () async {
      await db.enqueue(_op('poison'));
      await db.enqueue(_op('healthy'));
      server.answer = (op) => op.opId == 'poison'
          ? PushError(TransportException.httpError(422))
          : const PushSuccess();

      await engine.sync();

      expect(server.pushedOpIds, ['healthy']);
      expect(await tryCountOf('poison'), 1);
    });
  });

  test('in one batch only the op that is to blame is counted', () async {
    await db.enqueue(_op('rejected'));
    await db.enqueue(_op('unlucky'));
    server.answer = (op) => PushError(
      op.opId == 'rejected'
          ? TransportException.httpError(422)
          : const NetworkException('connection reset'),
    );

    await engine.sync();

    expect(await tryCountOf('rejected'), 1);
    expect(await tryCountOf('unlucky'), 0);
    final meta = await db.select(db.syncOutboxMeta).get();
    expect(meta.map((m) => m.opId).toSet(), {'rejected', 'unlucky'});
  });

  group('SyncErrorInfo.isEnvironmental', () {
    final cases = <(Object, bool)>[
      (const NetworkException('x'), true),
      (TimeoutException('x'), true),
      (TransportException.httpError(401), true),
      (TransportException.httpError(403), true),
      (TransportException.httpError(408), true),
      (TransportException.httpError(425), true),
      (TransportException.httpError(429), true),
      (TransportException.httpError(500), true),
      (TransportException.httpError(502), true),
      (TransportException.httpError(400), false),
      (TransportException.httpError(404), false),
      (TransportException.httpError(409), false),
      (TransportException.httpError(422), false),
      (const TransportException('no status'), false),
      (TransportException.parseError('<html>', const FormatException()), false),
      (const ParseException('bad row'), false),
      (StateError('x'), false),
    ];

    for (final (error, expected) in cases) {
      test('$error -> $expected', () {
        expect(SyncErrorInfo.fromError(error).isEnvironmental, expected);
      });
    }

    test('"not now" statuses are retryable', () {
      for (final status in [408, 425, 429]) {
        final info = SyncErrorInfo.fromError(
          TransportException.httpError(status),
        );
        expect(info.retryable, isTrue, reason: '$status');
      }
    });
  });

  group('recordOutboxFailures(countAttempts: false)', () {
    test('stores the error without counting an attempt', () async {
      await db.enqueue(_op('op-1'));

      await db.recordOutboxFailures({'op-1': 'offline'}, countAttempts: false);

      expect(await tryCountOf('op-1'), 0);
      final meta = await db.select(db.syncOutboxMeta).getSingle();
      expect(meta.lastError, 'offline');
    });

    test('counts by default', () async {
      await db.enqueue(_op('op-1'));

      await db.recordOutboxFailures({'op-1': 'HTTP error 422'});

      expect(await tryCountOf('op-1'), 1);
    });
  });
}
