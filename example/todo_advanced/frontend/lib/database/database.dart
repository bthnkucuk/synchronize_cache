import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

import '../models/todo.dart';
import 'tables/todos.dart';

export '../models/todo.dart';

part 'database.g.dart';

/// Application database with offline-first sync support.
///
/// Uses [SyncDatabaseMixin] to provide synchronization capabilities:
/// - Outbox for pending operations
/// - Cursors for tracking sync progress
@DriftDatabase(
  include: {'package:offline_first_sync_drift/src/sync_tables.drift'},
  tables: [Todos],
)
class AppDatabase extends _$AppDatabase with SyncDatabaseMixin {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// Locations of the SQLite WebAssembly module and the drift worker, both
  /// served from `web/`. Only used when running in a browser.
  static final _webOptions = DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  );

  /// Opens a persistent database for Flutter.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'todo_advanced', web: _webOptions);
  }

  /// Opens a persistent database with custom name.
  static AppDatabase open({String name = 'todo_advanced'}) {
    return AppDatabase(driftDatabase(name: name, web: _webOptions));
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
  );
}
