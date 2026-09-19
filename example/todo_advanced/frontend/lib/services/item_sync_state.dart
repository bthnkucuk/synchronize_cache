import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

import '../database/database.dart';
import 'sync_failure.dart';

/// Identifies one row of one kind, e.g. `('todos', 'a1b2…')`.
///
/// A record, so it works as a map key without writing an equality by hand.
typedef ItemKey = (String kind, String id);

/// Where one item stands between this device and the server.
enum ItemSyncStatus {
  /// Same here and on the server.
  synced,

  /// Created here and never sent (an upsert queued without a base version).
  onlyOnThisDevice,

  /// Edited here; the server still has the older version.
  changesNotSent,

  /// Deleted here; the server still has it.
  deleteNotSent,

  /// The last attempt failed for a reason that is not this item's fault.
  waitingToRetry,

  /// The server rejected it until the retry budget ran out.
  stuck,

  /// The manual conflict flow is waiting for the user.
  conflict,
}

extension ItemSyncStatusLabel on ItemSyncStatus {
  /// What the chip on the card says.
  String get label => switch (this) {
    ItemSyncStatus.synced => 'Synced',
    ItemSyncStatus.onlyOnThisDevice => 'Only on this device',
    ItemSyncStatus.changesNotSent => 'Changes not sent yet',
    ItemSyncStatus.deleteNotSent => 'Delete not sent yet',
    ItemSyncStatus.waitingToRetry => 'Waiting to retry',
    ItemSyncStatus.stuck => 'Stuck',
    ItemSyncStatus.conflict => 'Conflict — needs your decision',
  };

  /// One sentence explaining what the state means.
  String get explanation => switch (this) {
    ItemSyncStatus.synced =>
      'This device and the server hold the same version.',
    ItemSyncStatus.onlyOnThisDevice =>
      'You created this here and it has never reached the server. No other '
          'device can see it yet.',
    ItemSyncStatus.changesNotSent =>
      'Your edit is saved here. The server still has the version everyone '
          'else sees.',
    ItemSyncStatus.deleteNotSent =>
      'You deleted this here. It is still on the server until the delete is '
          'sent.',
    ItemSyncStatus.waitingToRetry =>
      'The last attempt failed for a reason that is not this item\'s fault, '
          'so it was not counted. It will go out as soon as that clears up.',
    ItemSyncStatus.stuck =>
      'The server rejected this change until the retry budget ran out. It '
          'will not be sent again until you retry it.',
    ItemSyncStatus.conflict =>
      'This item changed here and on another device. Nothing is lost while '
          'you decide.',
  };
}

/// One operation waiting in the outbox for a given item.
@immutable
class QueuedOperation {
  const QueuedOperation({
    required this.opId,
    required this.kind,
    required this.entityId,
    required this.isDelete,
    required this.queuedAt,
    required this.tryCount,
    this.baseUpdatedAt,
    this.changedFields,
    this.lastError,
    this.lastTriedAt,
  });

  final String opId;
  final String kind;
  final String entityId;
  final bool isDelete;
  final DateTime queuedAt;
  final int tryCount;

  /// The server version this change was made against. `null` on an upsert
  /// means "this row has never existed on the server".
  final DateTime? baseUpdatedAt;

  /// The JSON keys the user actually changed, when the app tracked them.
  final Set<String>? changedFields;

  final String? lastError;
  final DateTime? lastTriedAt;

  ItemKey get key => (kind, entityId);

  /// An upsert with no base version: a create the server has never seen.
  bool get isCreate => !isDelete && baseUpdatedAt == null;

  /// What the sheet calls this operation.
  String get typeLabel => isDelete
      ? 'Delete'
      : isCreate
      ? 'Create'
      : 'Edit';
}

/// The state of one item plus the evidence behind it.
@immutable
class ItemSyncState {
  const ItemSyncState({
    required this.status,
    this.operations = const [],
    this.reason,
    this.maxTryCount = 5,
  });

  static const synced = ItemSyncState(status: ItemSyncStatus.synced);

  final ItemSyncStatus status;

  /// Queued operations for this item, oldest first.
  final List<QueuedOperation> operations;

  /// Why it is waiting or stuck, in words. `null` when there is nothing to
  /// explain.
  final FailureReason? reason;

  /// The retry budget, so the sheet can say "attempts 2 of 5".
  final int maxTryCount;

  bool get isSynced => status == ItemSyncStatus.synced;

  /// Whether the user can do something about this one.
  bool get needsAttention =>
      status == ItemSyncStatus.stuck || status == ItemSyncStatus.conflict;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemSyncState &&
          other.status == status &&
          other.reason == reason &&
          other.maxTryCount == maxTryCount &&
          listEquals(other.operations, operations);

  @override
  int get hashCode =>
      Object.hash(status, reason, maxTryCount, Object.hashAll(operations));

  @override
  String toString() => 'ItemSyncState(${status.name})';
}

/// Turns the outbox into one state per item.
///
/// Pure on purpose: no drift, no widgets, no clock. Everything the UI shows
/// about an item comes from here, and it can be checked state by state in a
/// plain unit test.
///
/// Precedence, most urgent first: a conflict the user must decide, then an
/// item that ran out of retries, then one that is waiting on the
/// environment, and only then the plain "what is queued" states.
Map<ItemKey, ItemSyncState> deriveItemSyncStates({
  required List<QueuedOperation> operations,
  required Set<ItemKey> conflicted,
  required Map<String, FailureReason> liveFailures,
  int maxTryCount = 5,
}) {
  final byItem = <ItemKey, List<QueuedOperation>>{};
  for (final op in operations) {
    byItem.putIfAbsent(op.key, () => []).add(op);
  }
  for (final key in conflicted) {
    byItem.putIfAbsent(key, () => []);
  }

  final states = <ItemKey, ItemSyncState>{};
  for (final entry in byItem.entries) {
    final ops = entry.value.toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));

    // The freshest thing we know about why it is not through yet: the live
    // event if there is one, otherwise what the outbox stored.
    FailureReason? reason;
    for (final op in ops) {
      final live = liveFailures[op.opId];
      final stored = op.lastError;
      reason =
          live ?? (stored == null ? reason : describeStoredFailure(stored));
      if (live != null) break;
    }

    final status = _statusFor(
      ops: ops,
      isConflicted: conflicted.contains(entry.key),
      reason: reason,
      maxTryCount: maxTryCount,
    );

    states[entry.key] = ItemSyncState(
      status: status,
      operations: ops,
      reason:
          status == ItemSyncStatus.waitingToRetry ||
              status == ItemSyncStatus.stuck
          ? reason
          : null,
      maxTryCount: maxTryCount,
    );
  }
  return states;
}

ItemSyncStatus _statusFor({
  required List<QueuedOperation> ops,
  required bool isConflicted,
  required FailureReason? reason,
  required int maxTryCount,
}) {
  if (isConflicted) return ItemSyncStatus.conflict;
  if (ops.isEmpty) return ItemSyncStatus.synced;

  if (ops.any((op) => op.tryCount >= maxTryCount)) return ItemSyncStatus.stuck;
  if (reason != null && reason.environmental) {
    return ItemSyncStatus.waitingToRetry;
  }

  // Otherwise describe what is actually queued. A delete is the most
  // consequential thing pending, so it wins over an earlier edit.
  if (ops.any((op) => op.isDelete)) return ItemSyncStatus.deleteNotSent;
  if (ops.every((op) => op.isCreate)) return ItemSyncStatus.onlyOnThisDevice;
  return ItemSyncStatus.changesNotSent;
}

/// Reads [QueuedOperation]s out of a joined outbox row.
QueuedOperation queuedOperationFrom(
  SyncOutboxData row,
  SyncOutboxMetaData? meta,
) {
  return QueuedOperation(
    opId: row.opId,
    kind: row.kind,
    entityId: row.entityId,
    isDelete: row.op == OpType.delete,
    queuedAt: DateTime.fromMillisecondsSinceEpoch(row.ts, isUtc: true),
    tryCount: row.tryCount,
    baseUpdatedAt: row.baseUpdatedAt == null
        ? null
        : decodeOutboxTimestamp(row.baseUpdatedAt!),
    changedFields: _decodeChangedFields(row.changedFields),
    lastError: meta?.lastError,
    lastTriedAt: meta?.lastTriedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(meta!.lastTriedAt!, isUtc: true),
  );
}

/// `sync_outbox.base_updated_at` holds microseconds for anything after 1973
/// and milliseconds for older rows, so that the column could gain precision
/// without a schema change. The library keeps the codec internal; reading the
/// column for display means applying the same rule here.
DateTime decodeOutboxTimestamp(int stored) => stored.abs() >= 100000000000000
    ? DateTime.fromMicrosecondsSinceEpoch(stored, isUtc: true)
    : DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);

Set<String>? _decodeChangedFields(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return (jsonDecode(raw) as List).cast<String>().toSet();
  } on Object {
    return null;
  }
}

/// The live, watchable version of [deriveItemSyncStates].
///
/// Subscribes to the outbox tables once and hands every card its state, so a
/// list of a hundred todos does not run a hundred queries.
class ItemSyncStateStore extends ChangeNotifier {
  ItemSyncStateStore({
    required this.db,
    required this.maxTryCount,
    Set<ItemKey> Function()? conflictedItems,
  }) : _conflictedItems = conflictedItems ?? (() => const {});

  final AppDatabase db;
  final int maxTryCount;
  final Set<ItemKey> Function() _conflictedItems;

  StreamSubscription<List<QueuedOperation>>? _subscription;
  List<QueuedOperation> _operations = const [];
  final Map<String, FailureReason> _liveFailures = {};

  Map<ItemKey, ItemSyncState> _states = const {};

  /// Every item that is not plainly synced, keyed by `(kind, id)`.
  Map<ItemKey, ItemSyncState> get states => _states;

  /// Begins watching the outbox.
  ///
  /// Deliberately not done in the constructor: a live drift subscription is
  /// real asynchronous work, and a widget test that builds this service would
  /// then deadlock inside `pumpAndSettle`, which runs in a fake-async zone
  /// that never completes real I/O. Starting explicitly also makes the app's
  /// startup order visible in `main`.
  void start() {
    _subscription ??= _watchOperations().listen((ops) {
      _operations = ops;
      _recompute();
    });
  }

  /// The state of one item; [ItemSyncState.synced] when nothing is queued.
  ItemSyncState stateFor(String kind, String id) =>
      _states[(kind, id)] ?? ItemSyncState.synced;

  /// Records the precise reason the engine reported for a failed operation.
  void recordFailure(String opId, SyncErrorInfo info) {
    _liveFailures[opId] = describeFailure(info);
    _recompute();
  }

  /// Forgets a reason once its operation left the outbox.
  void forgetFailure(String opId) {
    if (_liveFailures.remove(opId) != null) _recompute();
  }

  /// Re-reads the conflict set, which lives in `ConflictHandler`.
  void conflictsChanged() => _recompute();

  Stream<List<QueuedOperation>> _watchOperations() {
    final query = db.select(db.syncOutbox).join([
      leftOuterJoin(
        db.syncOutboxMeta,
        db.syncOutboxMeta.opId.equalsExp(db.syncOutbox.opId),
      ),
    ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          queuedOperationFrom(
            row.readTable(db.syncOutbox),
            row.readTableOrNull(db.syncOutboxMeta),
          ),
      ],
    );
  }

  void _recompute() {
    final queuedOpIds = {for (final op in _operations) op.opId};
    _liveFailures.removeWhere((opId, _) => !queuedOpIds.contains(opId));

    _states = deriveItemSyncStates(
      operations: _operations,
      conflicted: _conflictedItems(),
      liveFailures: _liveFailures,
      maxTryCount: maxTryCount,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
