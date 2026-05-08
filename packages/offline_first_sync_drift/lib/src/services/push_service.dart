import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/conflict_resolution.dart';
import 'package:offline_first_sync_drift/src/constants.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/op.dart';
import 'package:offline_first_sync_drift/src/services/conflict_service.dart';
import 'package:offline_first_sync_drift/src/services/outbox_service.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

/// Push operation statistics.
class PushStats {
  const PushStats({
    this.pushed = 0,
    this.conflicts = 0,
    this.conflictsResolved = 0,
    this.errors = 0,
  });

  final int pushed;
  final int conflicts;
  final int conflictsResolved;
  final int errors;

  PushStats copyWith({
    int? pushed,
    int? conflicts,
    int? conflictsResolved,
    int? errors,
  }) => PushStats(
    pushed: pushed ?? this.pushed,
    conflicts: conflicts ?? this.conflicts,
    conflictsResolved: conflictsResolved ?? this.conflictsResolved,
    errors: errors ?? this.errors,
  );
}

/// Service for pushing local changes to the server.
class PushService {
  PushService({
    required GeneratedDatabase db,
    required OutboxService outbox,
    required TransportAdapter transport,
    required ConflictService<dynamic> conflictService,
    required Map<String, SyncableTable<dynamic>> tables,
    required SyncConfig config,
    required StreamController<SyncEvent> events,
  }) : _db = db,
       _outbox = outbox,
       _transport = transport,
       _conflictService = conflictService,
       _tables = tables,
       _config = config,
       _events = events;

  final GeneratedDatabase _db;
  final OutboxService _outbox;
  final TransportAdapter _transport;
  final ConflictService<dynamic> _conflictService;
  final Map<String, SyncableTable<dynamic>> _tables;
  final SyncConfig _config;
  final StreamController<SyncEvent> _events;

  /// Push operations from outbox.
  ///
  /// If [kinds] is provided, only operations for those kinds are processed.
  Future<PushStats> pushAll({Set<String>? kinds}) async {
    final counters = _PushCounters();

    try {
      if (kinds != null && kinds.isEmpty) {
        return counters.toStats();
      }

      while (true) {
        final outboxOps = await _outbox.take(
          limit: _config.pageSize,
          kinds: kinds,
          maxTryCountExclusive: _config.maxOutboxTryCount,
        );
        if (outboxOps.isEmpty) break;

        // Re-stamp each op's `baseUpdatedAt` from the latest local row so the
        // wire-level `_baseUpdatedAt` reflects the server-known version Round 1
        // wrote back after the previous successful push. Frozen outbox values
        // would otherwise produce stale-base 409s on rapid back-to-back edits.
        final ops = await _reStampBaseUpdatedAt(outboxOps);

        final result = await _pushBatch(ops);

        final successOpIds = <String>[];
        final conflictOps = <Op, PushConflict>{};
        final failed = <String, String>{};
        var hadPushErrors = false;
        var batchSuccessCount = 0;
        var batchErrorCount = 0;
        var batchConflictCount = 0;

        for (final opResult in result.results) {
          final op = ops.firstWhere((o) => o.opId == opResult.opId);

          switch (opResult.result) {
            case PushSuccess(:final serverData):
              // Server may return the canonical row for upserts (with
              // trigger-bumped fields like updated_at). For delete success
              // the body is empty (HTTP 204), so serverData is null and
              // there is nothing to write back. We mirror
              // ConflictService._applyServerData here so the local row
              // reflects the server-authoritative state immediately.
              if (serverData != null) {
                await _applyServerRow(op.kind, serverData);
              }
              successOpIds.add(opResult.opId);
              counters.pushed++;
              batchSuccessCount++;
              _events.add(
                OperationPushedEvent(
                  opId: op.opId,
                  kind: op.kind,
                  entityId: op.id,
                  operationType: op is UpsertOp ? OpType.upsert : OpType.delete,
                ),
              );

            case final PushConflict conflict:
              counters.conflicts++;
              batchConflictCount++;
              conflictOps[op] = conflict;

            case PushNotFound():
              successOpIds.add(opResult.opId);
              batchSuccessCount++;

            case final PushError error:
              counters.errors++;
              batchErrorCount++;
              hadPushErrors = true;
              failed[op.opId] = error.error.toString();
              _events.add(
                OperationFailedEvent(
                  opId: op.opId,
                  kind: op.kind,
                  entityId: op.id,
                  error: error.error,
                  willRetry: !_config.skipConflictingOps,
                ),
              );
          }
        }

        _events.add(
          PushBatchProcessedEvent(
            batchSize: ops.length,
            successCount: batchSuccessCount,
            errorCount: batchErrorCount,
            conflictCount: batchConflictCount,
          ),
        );

        await _outbox.ack(successOpIds);
        if (failed.isNotEmpty) {
          await _outbox.recordFailures(failed);
        }

        for (final entry in conflictOps.entries) {
          final result = await _conflictService.resolve(entry.key, entry.value);
          if (result.resolved) {
            counters.conflictsResolved++;
            successOpIds.add(entry.key.opId);
          } else if (_config.skipConflictingOps) {
            successOpIds.add(entry.key.opId);
          }
        }

        if (conflictOps.isNotEmpty) {
          await _outbox.ack(
            conflictOps.keys
                .where(
                  (op) =>
                      successOpIds.contains(op.opId) ||
                      _config.skipConflictingOps,
                )
                .map((op) => op.opId),
          );
        }

        // Do not spin on the same failed operations in a single sync run.
        // Leave unresolved items in outbox for the next sync attempt.
        if (hadPushErrors) {
          break;
        }
      }
    } on SyncException {
      rethrow;
    } catch (e, st) {
      throw SyncOperationException(
        'Push failed',
        phase: 'push',
        cause: e,
        stackTrace: st,
      );
    }

    return counters.toStats();
  }

  /// Re-stamp each op's [Op.baseUpdatedAt] from the latest local row's
  /// `updated_at` so the wire-level optimistic-concurrency token reflects the
  /// version Round 1 wrote back to local on the previous successful push.
  ///
  /// Three-state rule (preserves original semantics; never fabricates a base):
  ///   1. `op.baseUpdatedAt` non-null + local row found → override with row's
  ///      `updated_at` (the new, fresh, server-known version).
  ///   2. `op.baseUpdatedAt` non-null + local row missing → keep
  ///      `op.baseUpdatedAt` as-is (defensive: should not happen in practice).
  ///   3. `op.baseUpdatedAt` null (regardless of local row) → keep null.
  ///      First-write semantics (`isNewRecord`) — the consumer asked the server
  ///      to reject if the row already exists. Don't lie by inventing a base.
  ///
  /// Force-update is **not** routed through this method: `forcePush()` is a
  /// separate transport entrypoint used only by `ConflictService` for the
  /// `clientWins` strategy and does not emit `_baseUpdatedAt` on the wire.
  ///
  /// If the kind is not registered, the op is left unchanged (mirrors the
  /// defensive no-op in `_applyServerRow`).
  Future<List<Op>> _reStampBaseUpdatedAt(List<Op> ops) async {
    if (ops.isEmpty) return ops;
    final result = <Op>[];
    for (final op in ops) {
      result.add(await _reStampOne(op));
    }
    return result;
  }

  Future<Op> _reStampOne(Op op) async {
    // Rule 3: never fabricate a base for first-write ops.
    if (op is UpsertOp && op.baseUpdatedAt == null) return op;
    if (op is DeleteOp && op.baseUpdatedAt == null) return op;

    final tableConfig = _tables[op.kind];
    if (tableConfig == null) return op;

    final freshUpdatedAt = await _readLocalUpdatedAt(tableConfig, op.id);
    // Rule 2: row missing → keep op.baseUpdatedAt as-is.
    if (freshUpdatedAt == null) return op;

    // Rule 1: override with fresh local value.
    if (op is UpsertOp) {
      return op.copyWith(baseUpdatedAt: freshUpdatedAt);
    }
    if (op is DeleteOp) {
      return DeleteOp(
        opId: op.opId,
        kind: op.kind,
        id: op.id,
        localTimestamp: op.localTimestamp,
        baseUpdatedAt: freshUpdatedAt,
      );
    }
    return op;
  }

  /// Read the local row's `updated_at` for `(kind, id)` via a generic SELECT
  /// keyed on the registered table's primary-key column. Returns `null` if the
  /// row is absent or the table has a composite primary key (defensive — keep
  /// the op's existing `baseUpdatedAt` rather than guess).
  Future<DateTime?> _readLocalUpdatedAt(
    SyncableTable<dynamic> tableConfig,
    String id,
  ) async {
    final pk = tableConfig.table.$primaryKey;
    if (pk.length != 1) return null;

    final pkColumn = pk.first.name;
    final tableName = tableConfig.table.actualTableName;

    final rows = await _db
        .customSelect(
          'SELECT * FROM $tableName WHERE $pkColumn = ? LIMIT 1',
          variables: [Variable.withString(id)],
          readsFrom: {tableConfig.table},
        )
        .get();
    if (rows.isEmpty) return null;

    final entity = tableConfig.table.map(rows.first.data);
    try {
      return tableConfig.updatedAtOf(entity).toUtc();
    } catch (_) {
      // SyncableTable.updatedAtOf throws StateError if it can't find a
      // timestamp; defensively fall back to leaving the op's base alone.
      return null;
    }
  }

  /// Write the server's canonical row back to the local entity table.
  ///
  /// Mirrors [ConflictService._applyServerData]: convert the server JSON to
  /// an entity via the registered [SyncableTable.fromJson], turn it into an
  /// `Insertable` and `insertOnConflictUpdate` it. Used after a successful
  /// push so the local row picks up server-bumped fields (`updated_at`,
  /// trigger-derived columns, etc.) that the server returned in its response.
  ///
  /// If the [kind] is not registered, this is a no-op — the same defensive
  /// stance taken by `_applyServerData`.
  Future<void> _applyServerRow(
    String kind,
    Map<String, Object?> serverData,
  ) async {
    final tableConfig = _tables[kind];
    if (tableConfig == null) return;

    final entity = tableConfig.fromJson(serverData);
    await _db
        .into(tableConfig.table)
        .insertOnConflictUpdate(tableConfig.getInsertable(entity));
  }

  Future<BatchPushResult> _pushBatch(List<Op> ops) async {
    if (!_config.retryTransportErrorsInEngine) {
      return _transport.push(ops);
    }

    int attempt = 0;
    while (true) {
      try {
        attempt++;
        return await _transport.push(ops);
      } catch (e, st) {
        if (attempt >= _config.maxPushRetries) {
          throw MaxRetriesExceededException(
            'Push failed after $attempt attempts',
            attempts: attempt,
            maxRetries: _config.maxPushRetries,
            cause: e,
            stackTrace: st,
          );
        }
        final backoff =
            _config.backoffMin *
            math.pow(_config.backoffMultiplier, attempt - 1);
        final delay =
            backoff > _config.backoffMax ? _config.backoffMax : backoff;

        await Future<void>.delayed(delay);
      }
    }
  }
}

class _PushCounters {
  int pushed = 0;
  int conflicts = 0;
  int conflictsResolved = 0;
  int errors = 0;

  PushStats toStats() => PushStats(
    pushed: pushed,
    conflicts: conflicts,
    conflictsResolved: conflictsResolved,
    errors: errors,
  );
}
