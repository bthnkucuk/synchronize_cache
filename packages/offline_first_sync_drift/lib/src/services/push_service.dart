import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/conflict_resolution.dart';
import 'package:offline_first_sync_drift/src/constants.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/op.dart';
import 'package:offline_first_sync_drift/src/server_timestamp.dart';
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
@immutable
final class PushService {
  const PushService({
    required this._db,
    required this._outbox,
    required this._transport,
    required this._conflictService,
    required this._tables,
    required this._config,
    required this._events,
  });

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

        // One op per entity per batch: later ops of the same entity wait for
        // the next pass, after the server version the earlier one produced
        // has been written into their base (see the re-base below). Sent in
        // the same batch they would all carry the same, by then stale, base.
        final ops = await _withPreciseBases(_firstOpPerEntity(outboxOps));

        final result = await _pushBatch(ops);

        final successOpIds = <String>[];
        final conflictOps = <Op, PushConflict>{};
        // Versions the server reported in this pass, per (kind, entity id).
        final serverVersions = <(String, String), DateTime>{};
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
                _noteServerVersion(serverVersions, op, serverData);
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

        var hadUnresolvedConflicts = false;
        for (final entry in conflictOps.entries) {
          final result = await _conflictService.resolve(entry.key, entry.value);
          if (result.resolved) {
            counters.conflictsResolved++;
            successOpIds.add(entry.key.opId);
            final serverData = result.serverData;
            if (serverData != null) {
              _noteServerVersion(serverVersions, entry.key, serverData);
            }
          } else if (_config.skipConflictingOps) {
            successOpIds.add(entry.key.opId);
          } else {
            hadUnresolvedConflicts = true;
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

        // Ops still queued for these entities were enqueued against the
        // version we just replaced; without this they would be rejected as
        // conflicts with our own write.
        for (final MapEntry(key: (kind, id), value: version)
            in serverVersions.entries) {
          await _outbox.rebase(
            kind: kind,
            entityId: id,
            serverVersion: version,
          );
        }

        // Do not spin on the same operations in a single sync run. Failed
        // pushes and unresolved conflicts both stay in the outbox, so the
        // next `take` would return them again and produce the same result.
        // Leave them for the next sync attempt.
        if (hadPushErrors || hadUnresolvedConflicts) {
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

  /// Keeps the first queued op of every `(kind, id)` and drops the rest for
  /// this pass; [ops] is ordered oldest first, so per-entity order is kept.
  ///
  /// Ops of one entity must reach the server one at a time and in order:
  /// each successful write moves the server version the next one has to be
  /// based on, and an op must not be applied when an earlier one failed.
  List<Op> _firstOpPerEntity(List<Op> ops) {
    final seen = <(String, String)>{};
    return [
      for (final op in ops)
        if (seen.add((op.kind, op.id))) op,
    ];
  }

  Future<List<Op>> _withPreciseBases(List<Op> ops) async => [
    for (final op in ops) await _recoverBasePrecision(op),
  ];

  /// Restores sub-millisecond digits of a base that lost them.
  ///
  /// An op's base is the version the app edited, exactly as the app passed
  /// it. It is NOT replaced by the local row's `updated_at`: that column
  /// belongs to the app (many bump it on every edit, which used to turn each
  /// edit into a conflict), and a pull may have stored another client's
  /// write there — using it would push over that write without the conflict
  /// the server must report.
  ///
  /// The one thing the local row is good for: ops enqueued before the outbox
  /// stored microseconds carry a millisecond base. When the row still holds
  /// that same version, its full-precision value is what the server has.
  Future<Op> _recoverBasePrecision(Op op) async {
    final base = _baseOf(op);
    if (base == null || base.microsecond != 0) return op;

    final tableConfig = _tables[op.kind];
    if (tableConfig == null) return op;

    final local = await _readLocalUpdatedAt(tableConfig, op.id);
    if (local == null || local.microsecond == 0) return op;
    if (local.millisecondsSinceEpoch != base.millisecondsSinceEpoch) return op;

    return switch (op) {
      UpsertOp() => op.copyWith(baseUpdatedAt: local),
      DeleteOp() => DeleteOp(
        opId: op.opId,
        kind: op.kind,
        id: op.id,
        localTimestamp: op.localTimestamp,
        baseUpdatedAt: local,
      ),
    };
  }

  DateTime? _baseOf(Op op) => switch (op) {
    UpsertOp(:final baseUpdatedAt) => baseUpdatedAt,
    DeleteOp(:final baseUpdatedAt) => baseUpdatedAt,
  };

  /// Records the version carried by a canonical row the server returned.
  void _noteServerVersion(
    Map<(String, String), DateTime> versions,
    Op op,
    Map<String, Object?> serverData,
  ) {
    final raw =
        serverData[SyncFields.updatedAt] ??
        serverData[SyncFields.updatedAtSnake];
    if (raw == null) return;
    try {
      versions[(op.kind, op.id)] = parseServerTimestamp(raw);
    } on FormatException {
      // No usable version: queued ops keep their own base.
    }
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
        final delay = backoff > _config.backoffMax
            ? _config.backoffMax
            : backoff;

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
