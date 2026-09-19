import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:todo_advanced_frontend/services/item_sync_state.dart';
import 'package:todo_advanced_frontend/services/sync_failure.dart';

/// The state machine behind every chip, checked without a widget in sight.
void main() {
  final queuedAt = DateTime.utc(2026, 9, 20, 10);
  const key = ('todos', 'todo-1');

  QueuedOperation op({
    String opId = 'op-1',
    bool isDelete = false,
    int tryCount = 0,
    DateTime? baseUpdatedAt,
    String? lastError,
    Set<String>? changedFields,
    DateTime? at,
  }) => QueuedOperation(
    opId: opId,
    kind: 'todos',
    entityId: 'todo-1',
    isDelete: isDelete,
    queuedAt: at ?? queuedAt,
    tryCount: tryCount,
    baseUpdatedAt: baseUpdatedAt,
    changedFields: changedFields,
    lastError: lastError,
  );

  ItemSyncState derive(
    List<QueuedOperation> ops, {
    Set<ItemKey> conflicted = const {},
    Map<String, FailureReason> live = const {},
  }) => deriveItemSyncStates(
    operations: ops,
    conflicted: conflicted,
    liveFailures: live,
  )[key]!;

  group('deriveItemSyncStates', () {
    test('an item with nothing queued does not appear at all', () {
      final states = deriveItemSyncStates(
        operations: const [],
        conflicted: const {},
        liveFailures: const {},
      );

      expect(states, isEmpty);
    });

    test('a create that has never been sent is "Only on this device"', () {
      final state = derive([op()]);

      expect(state.status, ItemSyncStatus.onlyOnThisDevice);
      expect(state.status.label, 'Only on this device');
      expect(state.operations.single.isCreate, isTrue);
      expect(state.operations.single.typeLabel, 'Create');
    });

    test('an edit of a row the server knows is "Changes not sent yet"', () {
      final state = derive([
        op(baseUpdatedAt: DateTime.utc(2026), changedFields: {'title'}),
      ]);

      expect(state.status, ItemSyncStatus.changesNotSent);
      expect(state.operations.single.typeLabel, 'Edit');
    });

    test('a queued delete wins over an earlier edit', () {
      final state = derive([
        op(opId: 'op-edit', baseUpdatedAt: DateTime.utc(2026)),
        op(
          opId: 'op-delete',
          isDelete: true,
          at: queuedAt.add(const Duration(seconds: 1)),
        ),
      ]);

      expect(state.status, ItemSyncStatus.deleteNotSent);
      expect(state.operations.map((o) => o.opId), ['op-edit', 'op-delete']);
    });

    test('an environmental failure means "Waiting to retry", with the '
        'reason in words', () {
      final state = derive([op(lastError: 'NetworkException: no route')]);

      expect(state.status, ItemSyncStatus.waitingToRetry);
      expect(state.reason!.words, 'No connection to the server');
      expect(state.reason!.environmental, isTrue);
    });

    test('an expired sign-in is environmental too', () {
      final state = derive([
        op(
          lastError: 'TransportException: HTTP error 401 (status: 401)',
          baseUpdatedAt: DateTime.utc(2026),
        ),
      ]);

      expect(state.status, ItemSyncStatus.waitingToRetry);
      expect(state.reason!.words, 'Your sign-in has expired');
    });

    test('the retry budget being spent means "Stuck"', () {
      final state = derive([
        op(
          tryCount: 5,
          lastError: 'TransportException: HTTP error 422 (status: 422)',
          baseUpdatedAt: DateTime.utc(2026),
        ),
      ]);

      expect(state.status, ItemSyncStatus.stuck);
      expect(state.reason!.words, 'The server refused this item (HTTP 422)');
      expect(state.reason!.environmental, isFalse);
      expect(state.needsAttention, isTrue);
    });

    test('stuck beats waiting: a spent budget is not hidden by a later '
        'network blip', () {
      final state = derive([
        op(tryCount: 5, lastError: 'NetworkException: no route'),
      ]);

      expect(state.status, ItemSyncStatus.stuck);
    });

    test('a conflict outranks everything else', () {
      final state = derive(
        [op(tryCount: 5, lastError: 'NetworkException: no route')],
        conflicted: {key},
      );

      expect(state.status, ItemSyncStatus.conflict);
      expect(state.status.label, 'Conflict — needs your decision');
    });

    test('an item can be in conflict with nothing queued for it', () {
      final states = deriveItemSyncStates(
        operations: const [],
        conflicted: {key},
        liveFailures: const {},
      );

      expect(states[key]!.status, ItemSyncStatus.conflict);
    });

    test('the live reason from the engine beats the stored string', () {
      final state = derive(
        [op(lastError: 'NetworkException: stale')],
        live: {
          'op-1': const FailureReason(
            'The server is having trouble (HTTP 503)',
            environmental: true,
          ),
        },
      );

      expect(state.reason!.words, 'The server is having trouble (HTTP 503)');
    });

    test('items of different kinds are kept apart', () {
      final states = deriveItemSyncStates(
        operations: [
          op(),
          QueuedOperation(
            opId: 'op-note',
            kind: 'notes',
            entityId: 'todo-1',
            isDelete: true,
            queuedAt: queuedAt,
            tryCount: 0,
          ),
        ],
        conflicted: const {},
        liveFailures: const {},
      );

      expect(
        states[('todos', 'todo-1')]!.status,
        ItemSyncStatus.onlyOnThisDevice,
      );
      expect(states[('notes', 'todo-1')]!.status, ItemSyncStatus.deleteNotSent);
    });
  });

  group('queuedOperationFrom', () {
    test('decodes the outbox row, including microsecond base versions', () {
      final base = DateTime.utc(2026, 9, 20, 10, 0, 0, 123, 456);
      final row = SyncOutboxData(
        opId: 'op-1',
        kind: 'todos',
        entityId: 'todo-1',
        op: OpType.upsert,
        payload: '{}',
        ts: queuedAt.millisecondsSinceEpoch,
        tryCount: 2,
        baseUpdatedAt: base.microsecondsSinceEpoch,
        changedFields: '["title","description"]',
      );

      final parsed = queuedOperationFrom(
        row,
        SyncOutboxMetaData(
          opId: 'op-1',
          lastTriedAt: queuedAt.millisecondsSinceEpoch,
          lastError: 'boom',
        ),
      );

      expect(parsed.isDelete, isFalse);
      expect(parsed.tryCount, 2);
      expect(parsed.baseUpdatedAt, base);
      expect(parsed.changedFields, {'title', 'description'});
      expect(parsed.lastError, 'boom');
      expect(parsed.queuedAt, queuedAt);
    });

    test('a millisecond base version from an older row still decodes', () {
      final base = DateTime.utc(2026, 9, 20, 10, 0, 0, 123);
      expect(decodeOutboxTimestamp(base.microsecondsSinceEpoch), base);
      // 1970: small enough that it was stored as milliseconds.
      final old = DateTime.utc(1970, 1, 2);
      expect(decodeOutboxTimestamp(old.millisecondsSinceEpoch), old);
    });
  });
}
