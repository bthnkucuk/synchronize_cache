import 'package:drift/drift.dart';

/// Queue of search-index updates waiting to be parsed into the FTS5
/// `global_search` virtual table.
@DataClassName('PendingSearchItemRow')
@TableIndex.sql('CREATE INDEX idx_pending_search_items_user_id ON pending_search_items(user_id)')
class PendingSearchItems extends Table {
  TextColumn get userId => text()();
  TextColumn get kind => text()();
  TextColumn get id => text()();
  TextColumn get stringData => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// How many times the engine has tried to parse this item without success.
  /// Reaches `SearchEngine.maxPendingTries` ⇒ row becomes a dead-letter and
  /// is skipped by `getPendingUserItems` until either the threshold is
  /// raised or the cursor is reset manually.
  IntColumn get tryCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id, kind};

  @override
  String get tableName => 'pending_search_items';
}
