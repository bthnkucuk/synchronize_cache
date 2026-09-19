import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:search_engine/search_engine.dart';
// The two indexes the search tables declare. Modular generation keeps them in
// the package's own generated files, which its barrel does not re-export, and
// `onUpgrade` has to create them by hand for databases that predate v3. The
// `include:` below already names the same `src/` path for the same reason.
// ignore: implementation_imports
import 'package:search_engine/src/tables/pending_search_items.drift.dart'
    show idxPendingSearchItemsUserId;
// ignore: implementation_imports
import 'package:search_engine/src/tables/search_lookup.drift.dart'
    show idxSearchLookupUserKind;

import 'database.drift.dart';
import 'tables/app_settings.dart';
import 'tables/notes.dart';
import 'tables/todos.dart';

export '../models/note.dart';
export '../models/todo.dart';
// Modular generation puts the companions and the `toInsertable()` extensions
// next to each table. Re-exporting them keeps `import 'database.dart'` the
// one import the rest of the app needs.
export 'tables/app_settings.drift.dart';
export 'tables/notes.drift.dart';
export 'tables/todos.drift.dart';

/// Application database with offline-first sync and full-text search.
///
/// Two mixins, two jobs:
/// - [SyncDatabaseMixin] brings the outbox and the pull cursors.
/// - [SearchDatabaseMixin] brings the FTS5 index, its lookup table and the
///   indexing cursors.
///
/// Everything else is the app's own: two synced kinds ([Todos], [Notes]) and
/// a key/value table for this device's sync preferences.
@DriftDatabase(
  include: {
    'package:offline_first_sync_drift/src/sync_tables.drift',
    'package:search_engine/src/tables/search_tables.drift',
  },
  tables: [
    Todos,
    Notes,
    AppSettings,
    PendingSearchItems,
    SearchLookup,
    SearchIndexCursors,
  ],
)
class AppDatabase extends $AppDatabase
    with SyncDatabaseMixin, SearchDatabaseMixin {
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
  ///
  /// The name is what makes two browser tabs two *devices*: `?device=B` opens
  /// `todo_advanced_b`, which shares nothing with device A except the server.
  ///
  /// [interceptor] sees every statement sent to it; the sync scenarios use
  /// one to count transactions and to read query plans.
  static AppDatabase open({
    String name = 'todo_advanced',
    QueryInterceptor? interceptor,
  }) {
    final connection = driftDatabase(name: name, web: _webOptions);
    return AppDatabase(
      interceptor == null ? connection : connection.interceptWith(interceptor),
    );
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2 stores DateTime as ISO-8601 text (see build.yaml). Convert the
        // unix-second integers written by v1; their sub-second part is
        // already lost, the next pull restores the exact server versions.
        for (final column in const [
          'updated_at',
          'deleted_at',
          'deleted_at_local',
          'due_date',
        ]) {
          await customStatement(
            "UPDATE todos SET $column = "
            "strftime('%Y-%m-%dT%H:%M:%fZ', $column, 'unixepoch') "
            "WHERE typeof($column) = 'integer'",
          );
        }
      }
      if (from < 3) {
        // Every browser that already ran this app holds a v2 database, so the
        // notes, the settings and the whole search index have to be created
        // in place. `createAll()` would be wrong here: it also tries to
        // recreate what is already there.
        await m.createTable(notes);
        await m.createTable(appSettings);
        await m.createTable(pendingSearchItems);
        await m.createTable(searchLookup);
        await m.createTable(searchIndexCursors);
        // The FTS5 virtual table, which `createTable` cannot make.
        await m.create(globalSearch);
        await m.createIndex(idxPendingSearchItemsUserId);
        await m.createIndex(idxSearchLookupUserKind);
      }
    },
  );
}
