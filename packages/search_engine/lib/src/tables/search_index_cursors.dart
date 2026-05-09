import 'package:drift/drift.dart';

/// Per-(user, kind) cursor pinning the last `(updatedAt, id)` pair indexed
/// into the search backend. The search-side mirror of `sync_cursors` from
/// `offline_first_sync_drift`.
///
/// `SearchIndexer` reads the cursor before each batch and advances it after
/// every successful row, so subsequent runs only fetch rows that have
/// changed since.
@DataClassName('SearchIndexCursorRow')
class SearchIndexCursors extends Table {
  TextColumn get userId => text()();
  TextColumn get kind => text()();

  /// `updatedAt` of the last indexed row, stored as ms-since-epoch UTC.
  IntColumn get lastIndexedAtMs => integer()();

  /// Stable id of the last indexed row — tie-breaker when several rows
  /// share the same `updatedAt`.
  TextColumn get lastIndexedId => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, kind};

  @override
  String get tableName => 'search_index_cursors';
}
