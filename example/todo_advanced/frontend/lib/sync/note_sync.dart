import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

import '../database/database.dart';

/// Single source of truth for Note sync wiring.
///
/// Identical in shape to `todoSyncTable` — registering a second kind with
/// the engine is exactly this much work.
SyncableTable<Note> noteSyncTable(AppDatabase db) => SyncableTable<Note>(
  kind: 'notes',
  table: db.notes,
  fromJson: Note.fromJson,
  toJson: (n) => n.toJson(),
  toInsertable: (n) => n.toInsertable(),
  getId: (n) => n.id,
  getUpdatedAt: (n) => n.updatedAt,
);
