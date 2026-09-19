import 'dart:async';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/conflict_resolution.dart';
import 'package:offline_first_sync_drift/src/op.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

/// Result of conflict resolution.
final class ConflictResolutionResult {
  const ConflictResolutionResult({
    required this.resolved,
    this.resultData,
    this.serverData,
  });

  /// Whether the conflict was resolved.
  final bool resolved;

  /// Data after resolution.
  final Map<String, Object?>? resultData;

  /// The entity as the server holds it after the resolution, when known: the
  /// server's row for `AcceptServer`, the row returned by the force push
  /// otherwise. Its `updated_at` is the version later ops must be based on.
  final Map<String, Object?>? serverData;
}

/// Service for sync conflict resolution.
@immutable
class ConflictService<DB extends GeneratedDatabase> {
  const ConflictService({
    required this._db,
    required this._transport,
    required this._tables,
    required this._config,
    required this._tableConflictConfigs,
    required this._events,
  });

  final DB _db;
  final TransportAdapter _transport;
  final Map<String, SyncableTable<dynamic>> _tables;
  final SyncConfig _config;
  final Map<String, TableConflictConfig> _tableConflictConfigs;
  final StreamController<SyncEvent> _events;

  /// Resolve conflict for an operation.
  Future<ConflictResolutionResult> resolve(
    Op op,
    PushConflict serverConflict,
  ) async {
    final tableConfig = _tableConflictConfigs[op.kind];
    final strategy = tableConfig?.strategy ?? _config.conflictStrategy;

    final localData = op is UpsertOp ? op.payloadJson : <String, Object?>{};
    final changedFields = op is UpsertOp ? op.changedFields : null;

    final conflict = Conflict(
      kind: op.kind,
      entityId: op.id,
      opId: op.opId,
      localData: localData,
      serverData: serverConflict.serverData,
      localTimestamp: op.localTimestamp,
      serverTimestamp: serverConflict.serverTimestamp,
      serverVersion: serverConflict.serverVersion,
      changedFields: changedFields,
    );

    _events.add(ConflictDetectedEvent(conflict: conflict, strategy: strategy));

    final resolution = await _determineResolution(
      conflict,
      strategy,
      tableConfig,
    );

    return _applyResolution(op, conflict, resolution);
  }

  Future<ConflictResolution> _determineResolution(
    Conflict conflict,
    ConflictStrategy strategy,
    TableConflictConfig? tableConfig,
  ) async {
    switch (strategy) {
      case ConflictStrategy.serverWins:
        return const AcceptServer();

      case ConflictStrategy.clientWins:
        return const AcceptClient();

      case ConflictStrategy.lastWriteWins:
        if (conflict.localTimestamp.isAfter(conflict.serverTimestamp)) {
          return const AcceptClient();
        }
        return const AcceptServer();

      case ConflictStrategy.merge:
        final mergeFunc =
            tableConfig?.mergeFunction ??
            _config.mergeFunction ??
            ConflictUtils.defaultMerge;
        final merged = mergeFunc(conflict.localData, conflict.serverData);
        return AcceptMerged(merged);

      case ConflictStrategy.manual:
        final resolver = tableConfig?.resolver ?? _config.conflictResolver;
        if (resolver == null) {
          _events.add(
            ConflictUnresolvedEvent(
              conflict: conflict,
              reason: 'No conflict resolver provided for manual strategy',
            ),
          );
          return const DeferResolution();
        }
        return resolver(conflict);

      case ConflictStrategy.autoPreserve:
        final mergeResult = ConflictUtils.preservingMerge(
          conflict.localData,
          conflict.serverData,
          changedFields: conflict.changedFields,
        );

        _events.add(
          DataMergedEvent(
            kind: conflict.kind,
            entityId: conflict.entityId,
            localFields: mergeResult.localFields,
            serverFields: mergeResult.serverFields,
            mergedData: mergeResult.data,
          ),
        );

        return AcceptMerged(
          mergeResult.data,
          mergeInfo: MergeInfo(
            localFields: mergeResult.localFields,
            serverFields: mergeResult.serverFields,
          ),
        );
    }
  }

  Future<ConflictResolutionResult> _applyResolution(
    Op op,
    Conflict conflict,
    ConflictResolution resolution,
  ) async {
    switch (resolution) {
      case AcceptServer():
        await _applyServerData(conflict);
        _events.add(
          ConflictResolvedEvent(
            conflict: conflict,
            resolution: resolution,
            resultData: conflict.serverData,
          ),
        );
        return ConflictResolutionResult(
          resolved: true,
          resultData: conflict.serverData,
          serverData: conflict.serverData,
        );

      case AcceptClient():
        final pushed = await _forcePushOp(op);
        final success = pushed != null;
        if (success) {
          _events.add(
            ConflictResolvedEvent(
              conflict: conflict,
              resolution: resolution,
              resultData: conflict.localData,
            ),
          );
        }
        return ConflictResolutionResult(
          resolved: success,
          resultData: success ? conflict.localData : null,
          serverData: pushed?.serverData,
        );

      case AcceptMerged(:final mergedData):
        final pushed = await _pushMergedData(op, mergedData);
        final success = pushed != null;
        if (success) {
          _events.add(
            ConflictResolvedEvent(
              conflict: conflict,
              resolution: resolution,
              resultData: mergedData,
            ),
          );
        }
        return ConflictResolutionResult(
          resolved: success,
          resultData: success ? mergedData : null,
          serverData: pushed?.serverData,
        );

      case DeferResolution():
        _events.add(
          ConflictUnresolvedEvent(
            conflict: conflict,
            reason: 'Resolution deferred',
          ),
        );
        return const ConflictResolutionResult(resolved: false);

      case DiscardOperation():
        _events.add(
          ConflictResolvedEvent(conflict: conflict, resolution: resolution),
        );
        return const ConflictResolutionResult(resolved: true);
    }
  }

  /// Writes a row the server returned into the local table, so the local
  /// entity carries the server's version of it. No-op without data or for an
  /// unregistered kind.
  Future<void> _applyServerRow(String kind, Map<String, Object?>? row) async {
    final tableConfig = _tables[kind];
    if (row == null || tableConfig == null) return;

    final entity = tableConfig.fromJson(row);
    await _db
        .into(tableConfig.table)
        .insertOnConflictUpdate(tableConfig.getInsertable(entity));
  }

  Future<void> _applyServerData(Conflict conflict) async {
    final tableConfig = _tables[conflict.kind];
    if (tableConfig == null) return;

    final entity = tableConfig.fromJson(conflict.serverData);
    await _db
        .into(tableConfig.table)
        .insertOnConflictUpdate(tableConfig.getInsertable(entity));
  }

  /// Force-pushes [op]; returns the server's success, or `null` on failure.
  Future<PushSuccess?> _forcePushOp(Op op) async {
    var retries = 0;
    while (retries < _config.maxConflictRetries) {
      final result = await _transport.forcePush(op);

      if (result is PushSuccess) {
        await _applyServerRow(op.kind, result.serverData);
        return result;
      }

      if (result is PushConflict) {
        retries++;
        if (retries < _config.maxConflictRetries) {
          await Future<void>.delayed(_config.conflictRetryDelay);
        }
        continue;
      }

      return null;
    }
    return null;
  }

  /// Force-pushes [mergedData]; returns the server's success, or `null`.
  Future<PushSuccess?> _pushMergedData(
    Op op,
    Map<String, Object?> mergedData,
  ) async {
    if (op is! UpsertOp) return null;

    final mergedOp = UpsertOp(
      opId: op.opId,
      kind: op.kind,
      id: op.id,
      localTimestamp: DateTime.now().toUtc(),
      payloadJson: mergedData,
    );

    var retries = 0;
    while (retries < _config.maxConflictRetries) {
      final result = await _transport.forcePush(mergedOp);

      if (result is PushSuccess) {
        // Prefer the row the server returned: it carries the version the
        // write produced. The merged data still has the version it replaced.
        await _applyServerRow(op.kind, result.serverData ?? mergedData);
        return result;
      }

      if (result is PushConflict) {
        retries++;
        if (retries < _config.maxConflictRetries) {
          await Future<void>.delayed(_config.conflictRetryDelay);
        }
        continue;
      }

      return null;
    }
    return null;
  }
}
