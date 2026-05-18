import 'dart:async';

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart' hide isNull, isNotNull;

import '../fixtures/test_database.dart';

// PushService is highly coupled to drift internals (customSelect for base
// re-stamping, insertOnConflictUpdate for server-row write-back). We use a
// real in-memory TestDatabase + mocktail TransportAdapter + a real
// OutboxService and a no-op ConflictService stub, focusing on:
//   - early exit for empty kinds filter
//   - successful push acks + counter accounting
//   - server-data write-back on success
//   - error path: increments tryCount via outbox, breaks loop, doesn't ack
//   - retry-with-backoff path triggered by retryTransportErrorsInEngine
//   - MaxRetriesExceededException when retries exhausted
//   - conflict resolution branch interaction (skipConflictingOps)

class _MockTransport extends Mock implements TransportAdapter {}

class _StubConflictService<DB extends GeneratedDatabase>
    implements ConflictService<DB> {
  _StubConflictService(this._result);

  final ConflictResolutionResult _result;
  int callCount = 0;

  @override
  Future<ConflictResolutionResult> resolve(Op op, PushConflict serverConflict) {
    callCount++;
    return Future.value(_result);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

UpsertOp _upsert({
  String id = 'item-1',
  DateTime? base,
}) =>
    UpsertOp(
      opId: 'op-$id',
      kind: 'test_item',
      id: id,
      localTimestamp: DateTime.utc(2024, 6, 1, 12),
      payloadJson: {
        'id': id,
        'updated_at': '2024-06-01T12:00:00.000Z',
        'name': 'Local-$id',
      },
      baseUpdatedAt: base,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_upsert());
    registerFallbackValue(<Op>[]);
  });

  late TestDatabase db;
  late _MockTransport transport;
  late StreamController<SyncEvent> events;
  late OutboxService outbox;
  late SyncableTable<TestItem> testItemTable;
  late Map<String, SyncableTable<dynamic>> tables;

  setUp(() {
    db = TestDatabase();
    transport = _MockTransport();
    events = StreamController<SyncEvent>.broadcast();
    outbox = OutboxService(db);
    testItemTable = SyncableTable<TestItem>(
      kind: 'test_item',
      table: db.testItems,
      fromJson: TestItem.fromJson,
      toJson: (e) => e.toJson(),
      toInsertable: (e) => e.toInsertable(),
      getId: (e) => e.id,
      getUpdatedAt: (e) => e.updatedAt,
    );
    tables = {'test_item': testItemTable};
  });

  tearDown(() async {
    await db.close();
    await events.close();
  });

  PushService buildService({
    SyncConfig? config,
    ConflictService<dynamic>? conflictService,
  }) =>
      PushService(
        db: db,
        outbox: outbox,
        transport: transport,
        conflictService: conflictService ??
            _StubConflictService(
              const ConflictResolutionResult(resolved: false),
            ),
        tables: tables,
        config: config ?? const SyncConfig(),
        events: events,
      );

  group('PushService.pushAll', () {
    test('returns empty stats and skips transport for empty kinds filter',
        () async {
      final service = buildService();

      final stats = await service.pushAll(kinds: <String>{});

      expect(stats.pushed, 0);
      expect(stats.conflicts, 0);
      expect(stats.errors, 0);
      verifyNever(() => transport.push(any()));
    });

    test('returns empty stats when outbox is empty', () async {
      when(() => transport.push(any()))
          .thenAnswer((_) async => const BatchPushResult(results: []));

      final service = buildService();
      final stats = await service.pushAll();

      expect(stats.pushed, 0);
      verifyNever(() => transport.push(any()));
    });

    test(
      'pushes ops, acks success, emits events, writes back server data',
      () async {
        final op = _upsert(id: 'a');
        await outbox.enqueue(op);

        when(() => transport.push(any())).thenAnswer(
          (invocation) async {
            final ops = invocation.positionalArguments[0] as List<Op>;
            return BatchPushResult(
              results: ops
                  .map(
                    (o) => OpPushResult(
                      opId: o.opId,
                      result: const PushSuccess(
                        serverData: {
                          'id': 'a',
                          'updated_at': '2024-06-01T13:00:00.000Z',
                          'name': 'Server-A',
                        },
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        );

        final captured = <SyncEvent>[];
        final sub = events.stream.listen(captured.add);

        final stats = await buildService().pushAll();

        expect(stats.pushed, 1);
        expect(stats.errors, 0);
        expect(stats.conflicts, 0);

        // Outbox emptied (acked).
        final pending =
            await outbox.take(limit: 100, maxTryCountExclusive: null);
        expect(pending, isEmpty);

        // Local row reflects server data (write-back).
        final rows = await db.select(db.testItems).get();
        expect(rows.first.name, 'Server-A');

        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(captured.whereType<OperationPushedEvent>(), hasLength(1));
        expect(captured.whereType<PushBatchProcessedEvent>(), hasLength(1));
      },
    );

    test(
      'treats PushNotFound as success (acks) and PushError as failure',
      () async {
        final ok = _upsert(id: 'ok');
        final nf = _upsert(id: 'nf');
        final er = _upsert(id: 'er');
        await outbox.enqueue(ok);
        await outbox.enqueue(nf);
        await outbox.enqueue(er);

        when(() => transport.push(any())).thenAnswer(
          (invocation) async {
            final ops = invocation.positionalArguments[0] as List<Op>;
            return BatchPushResult(
              results: ops.map((o) {
                if (o.id == 'ok') {
                  return OpPushResult(
                    opId: o.opId,
                    result: const PushSuccess(),
                  );
                }
                if (o.id == 'nf') {
                  return OpPushResult(
                    opId: o.opId,
                    result: const PushNotFound(),
                  );
                }
                return OpPushResult(
                  opId: o.opId,
                  result: const PushError('boom'),
                );
              }).toList(),
            );
          },
        );

        final captured = <SyncEvent>[];
        final sub = events.stream.listen(captured.add);

        final stats = await buildService().pushAll();

        expect(stats.pushed, 1);
        expect(stats.errors, 1);

        // After break-on-error, the failed op stays in outbox; ok+nf acked.
        final pending = await outbox.take(
          limit: 100,
          maxTryCountExclusive: null,
        );
        expect(pending.map((o) => o.id), ['er']);

        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(captured.whereType<OperationFailedEvent>(), hasLength(1));
      },
    );

    test('rethrows existing SyncException without wrapping', () async {
      await outbox.enqueue(_upsert());

      const original = NetworkException('boom');
      when(() => transport.push(any())).thenThrow(original);

      try {
        await buildService().pushAll();
        fail('expected SyncException');
      } catch (e) {
        expect(identical(e, original), isTrue);
      }
    });

    test('wraps unknown exceptions in SyncOperationException(phase: push)',
        () async {
      await outbox.enqueue(_upsert());
      when(() => transport.push(any())).thenThrow(StateError('weird'));

      try {
        await buildService().pushAll();
        fail('expected SyncOperationException');
      } on SyncOperationException catch (e) {
        expect(e.phase, 'push');
        expect(e.cause, isA<StateError>());
      }
    });
  });

  group('PushService transport retry (retryTransportErrorsInEngine=true)', () {
    test('retries with backoff until success', () async {
      await outbox.enqueue(_upsert(id: 'a'));

      var attempt = 0;
      when(() => transport.push(any())).thenAnswer((invocation) async {
        attempt++;
        if (attempt < 3) {
          throw Exception('transient');
        }
        final ops = invocation.positionalArguments[0] as List<Op>;
        return BatchPushResult(
          results: ops
              .map(
                (o) => OpPushResult(
                  opId: o.opId,
                  result: const PushSuccess(),
                ),
              )
              .toList(),
        );
      });

      final service = buildService(
        config: const SyncConfig(
          retryTransportErrorsInEngine: true,
          maxPushRetries: 5,
          backoffMin: Duration(milliseconds: 1),
          backoffMax: Duration(milliseconds: 2),
        ),
      );

      final stats = await service.pushAll();

      expect(attempt, 3);
      expect(stats.pushed, 1);
    });

    test('throws MaxRetriesExceededException when retries exhausted',
        () async {
      await outbox.enqueue(_upsert());

      when(() => transport.push(any())).thenThrow(Exception('always fails'));

      final service = buildService(
        config: const SyncConfig(
          retryTransportErrorsInEngine: true,
          maxPushRetries: 2,
          backoffMin: Duration(milliseconds: 1),
          backoffMax: Duration(milliseconds: 1),
        ),
      );

      try {
        await service.pushAll();
        fail('expected MaxRetriesExceededException (wrapped)');
      } on SyncOperationException catch (e) {
        // MaxRetriesExceededException is a SyncException → rethrown as-is.
        // Actually: SyncException is rethrown without wrapping, so we should
        // get MaxRetriesExceededException directly. Adjust if that path
        // changed.
        fail('unexpected SyncOperationException: $e');
      } on MaxRetriesExceededException catch (e) {
        expect(e.maxRetries, 2);
        expect(e.attempts, 2);
      }
    });
  });

  group('PushService conflict branch', () {
    test('records resolved conflict and acks op', () async {
      final op = _upsert(id: 'c1');
      await outbox.enqueue(op);

      when(() => transport.push(any())).thenAnswer(
        (invocation) async {
          final ops = invocation.positionalArguments[0] as List<Op>;
          return BatchPushResult(
            results: ops
                .map(
                  (o) => OpPushResult(
                    opId: o.opId,
                    result: PushConflict(
                      serverData: {'id': 'c1', 'name': 'Server'},
                      serverTimestamp: DateTime.utc(2024, 6, 5),
                    ),
                  ),
                )
                .toList(),
          );
        },
      );

      final conflictService = _StubConflictService<TestDatabase>(
        const ConflictResolutionResult(resolved: true),
      );

      final service = buildService(
        conflictService: conflictService as ConflictService<dynamic>,
      );

      final stats = await service.pushAll();

      expect(stats.conflicts, 1);
      expect(stats.conflictsResolved, 1);
      expect(conflictService.callCount, 1);

      final pending =
          await outbox.take(limit: 100, maxTryCountExclusive: null);
      expect(pending, isEmpty);
    });

    test(
      'unresolved conflict with skipConflictingOps=true acks the op',
      () async {
        final op = _upsert(id: 'c2');
        await outbox.enqueue(op);

        when(() => transport.push(any())).thenAnswer(
          (invocation) async {
            final ops = invocation.positionalArguments[0] as List<Op>;
            return BatchPushResult(
              results: ops
                  .map(
                    (o) => OpPushResult(
                      opId: o.opId,
                      result: PushConflict(
                        serverData: {'id': 'c2'},
                        serverTimestamp: DateTime.utc(2024, 6, 5),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        );

        final skipService = buildService(
          config: const SyncConfig(skipConflictingOps: true),
          conflictService: _StubConflictService<TestDatabase>(
            const ConflictResolutionResult(resolved: false),
          ) as ConflictService<dynamic>,
        );
        final stats = await skipService.pushAll();
        expect(stats.conflicts, 1);
        expect(stats.conflictsResolved, 0);
        final pending =
            await outbox.take(limit: 100, maxTryCountExclusive: null);
        expect(pending, isEmpty);
      },
    );

    test(
      'unresolved conflict without skipConflictingOps gets resolved on retry',
      () async {
        // Two-attempt scenario: first push returns conflict, second returns
        // success — proves the loop continues until either resolution or
        // ack. This is the safe variant of "stays in outbox" without risking
        // an infinite loop in the test.
        await outbox.enqueue(_upsert(id: 'c3'));

        var pushCall = 0;
        when(() => transport.push(any())).thenAnswer((invocation) async {
          pushCall++;
          final ops = invocation.positionalArguments[0] as List<Op>;
          if (pushCall == 1) {
            return BatchPushResult(
              results: ops
                  .map(
                    (o) => OpPushResult(
                      opId: o.opId,
                      result: PushConflict(
                        serverData: {'id': 'c3'},
                        serverTimestamp: DateTime.utc(2024, 6, 5),
                      ),
                    ),
                  )
                  .toList(),
            );
          }
          return BatchPushResult(
            results: ops
                .map(
                  (o) => OpPushResult(
                    opId: o.opId,
                    result: const PushSuccess(),
                  ),
                )
                .toList(),
          );
        });

        // Conflict service: any call returns unresolved (op stays in
        // outbox). Loop re-fetches outbox, push#2 returns success, op is
        // acked.
        final conflictStub = _StubConflictService<TestDatabase>(
          const ConflictResolutionResult(resolved: false),
        );

        final service = buildService(
          conflictService: conflictStub as ConflictService<dynamic>,
        );
        final stats = await service.pushAll();

        expect(conflictStub.callCount, 1);
        expect(pushCall, 2);
        expect(stats.conflicts, 1);
        expect(stats.pushed, 1);

        final pending =
            await outbox.take(limit: 100, maxTryCountExclusive: null);
        expect(pending, isEmpty);
      },
    );
  });
}
