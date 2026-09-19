import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/src/tables/sync_data_classes.dart';

/// Outbox table for synchronization operations.
/// Stores local changes until they are sent to the server.
///
/// The indexes back the queries the engine repeats for every batch or every
/// pushed op, which would otherwise scan the whole queue each time:
///  * `(kind, ts)` — `takeOutbox` for one kind reads the next batch in
///    dispatch order, without sorting the queue;
///  * `(ts)` — the same for `takeOutbox` without a kind filter (full resync)
///    and for `purgeOutboxOlderThan`;
///  * `(kind, entity_id)` — finding and re-basing the ops still queued for an
///    entity after one of its ops was pushed.
///
/// They are declared `IF NOT EXISTS` on purpose: databases created before
/// they existed get them from [SyncDatabaseMixin.ensureSyncIndexes], and a
/// migration that calls `Migrator.createIndex` for them stays harmless.
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_sync_outbox_kind_ts '
  'ON sync_outbox (kind, ts)',
)
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_sync_outbox_ts ON sync_outbox (ts)',
)
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_sync_outbox_kind_entity '
  'ON sync_outbox (kind, entity_id)',
)
@UseRowClass(SyncOutboxData)
class SyncOutbox extends Table {
  /// Unique operation identifier.
  TextColumn get opId => text()();

  /// Entity kind (for example, `daily_feeling`).
  TextColumn get kind => text()();

  /// Entity ID.
  TextColumn get entityId => text()();

  /// Operation type: `upsert` or `delete`.
  TextColumn get op => text()();

  /// JSON payload for upsert operations.
  TextColumn get payload => text().nullable()();

  /// Operation timestamp (UTC milliseconds).
  IntColumn get ts => integer()();

  /// Number of send attempts.
  IntColumn get tryCount => integer().withDefault(const Constant(0))();

  /// Timestamp when data was last fetched from server (UTC milliseconds).
  IntColumn get baseUpdatedAt => integer().nullable()();

  /// JSON array with changed field names.
  TextColumn get changedFields => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};

  @override
  String get tableName => 'sync_outbox';
}
