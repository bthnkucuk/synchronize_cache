import 'dart:async';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/constants.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/internal/event_emitter.dart';
import 'package:offline_first_sync_drift/src/op.dart';
import 'package:offline_first_sync_drift/src/services/outbox_service.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

/// What an app can do about operations that used up their retry budget
/// ([SyncConfig.maxOutboxTryCount]): look at them, give them a new budget, or
/// give up on them.
@immutable
final class StuckOperationsService<DB extends GeneratedDatabase> {
  const StuckOperationsService({
    required this._db,
    required this._outbox,
    required this._transport,
    required this._tables,
    required this._config,
    required this._events,
  });

  final DB _db;
  final OutboxService _outbox;
  final TransportAdapter _transport;
  final Map<String, SyncableTable<dynamic>> _tables;
  final SyncConfig _config;
  final StreamController<SyncEvent> _events;

  /// Operations that reached the stuck threshold.
  Future<List<Op>> getStuck({Set<String>? kinds}) =>
      _outbox.getStuck(minTryCount: _config.maxOutboxTryCount, kinds: kinds);

  /// Gives the stuck operations a new retry budget.
  Future<void> retry({Set<String>? kinds}) async {
    final stuck = await getStuck(kinds: kinds);
    await _outbox.resetTryCount(stuck.map((op) => op.opId));
  }

  /// Drops the stuck operations and restores their rows from the server; see
  /// `SyncEngine.dropStuckOperations`.
  Future<void> drop({Set<String>? kinds}) async {
    final stuck = await getStuck(kinds: kinds);

    final byEntity = <(String, String), List<String>>{};
    for (final op in stuck) {
      byEntity.putIfAbsent((op.kind, op.id), () => []).add(op.opId);
    }

    // Row by row, each one settled on its own: a row that cannot be restored
    // (or an error while trying) does not keep the others.
    for (final MapEntry(key: (kind, id), value: opIds) in byEntity.entries) {
      if (await _hasLiveOps(kind, id)) {
        // Newer edits of the same row that are still on their way keep their
        // say: the row is theirs until they are pushed.
        await _outbox.ack(opIds);
      } else {
        await _discard(kind, id, opIds);
      }
    }
  }

  /// Whether `(kind, id)` has operations queued that are not stuck.
  Future<bool> _hasLiveOps(String kind, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 FROM ${TableNames.syncOutbox} '
          'WHERE ${TableColumns.kind} = ? AND ${TableColumns.entityId} = ? '
          'AND ${TableColumns.tryCount} < ? LIMIT 1',
          variables: [
            Variable.withString(kind),
            Variable.withString(id),
            Variable.withInt(_config.maxOutboxTryCount),
          ],
        )
        .get();
    return rows.isNotEmpty;
  }

  /// Drops the stuck operations [opIds] of `(kind, id)` and makes the local
  /// row what the server has. Leaves both alone when the server could not be
  /// asked.
  Future<void> _discard(String kind, String id, List<String> opIds) async {
    final tableConfig = _tables[kind];
    if (tableConfig == null) {
      await _outbox.ack(opIds);
      return;
    }

    final FetchResult result;
    try {
      result = await _transport.fetch(kind: kind, id: id);
    } on Object catch (e, st) {
      _events.emit(SyncErrorEvent(SyncPhase.push, e, st));
      return;
    }

    Insertable<dynamic>? serverRow;
    switch (result) {
      case FetchError(:final error, :final stackTrace):
        _events.emit(SyncErrorEvent(SyncPhase.push, error, stackTrace));
        return;
      case FetchSuccess(:final data):
        try {
          serverRow = tableConfig.getInsertable(tableConfig.fromJson(data));
        } on Object catch (e, st) {
          // The server has the row, in a form this app cannot read — a pull
          // skips such a row too. The operations are dropped as asked; the
          // local row cannot be made the server's, and the app is told.
          _reportUnrestoredRow(kind, id, e, st);
        }
      case FetchNotFound():
        break;
    }

    await _db.transaction(() async {
      // An edit made while the server was being asked owns the row now.
      if (!await _hasLiveOps(kind, id)) {
        try {
          if (serverRow != null) {
            await _db.into(tableConfig.table).insertOnConflictUpdate(serverRow);
          } else if (result is FetchNotFound) {
            await _deleteLocalRow(tableConfig, id);
          }
        } on Object catch (e, st) {
          _reportUnrestoredRow(kind, id, e, st);
        }
      }
      await _outbox.ack(opIds);
    });
  }

  Future<void> _deleteLocalRow(
    SyncableTable<dynamic> tableConfig,
    String id,
  ) async {
    final pk = tableConfig.table.$primaryKey;
    if (pk.length != 1) return;
    await _db.customUpdate(
      'DELETE FROM "${tableConfig.table.actualTableName}" '
      'WHERE "${pk.first.name}" = ?',
      variables: [Variable.withString(id)],
      updates: {tableConfig.table},
      updateKind: UpdateKind.delete,
    );
  }

  void _reportUnrestoredRow(
    String kind,
    String id,
    Object error,
    StackTrace stackTrace,
  ) {
    _events.emit(
      SyncErrorEvent(
        SyncPhase.push,
        ParseException(
          'Dropped the stuck operations of "$kind" $id, but its row could '
          'not be restored from the server: $error',
          error,
          stackTrace,
        ),
        stackTrace,
      ),
    );
  }
}
