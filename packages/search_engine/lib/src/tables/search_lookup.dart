import 'package:drift/drift.dart';

/// Maps a (user_id, kind, original_id) triple to the FTS5 rowid stored in
/// `global_search`, allowing us to delete/replace entries in the virtual
/// table without re-querying the FTS index.
@TableIndex.sql('CREATE INDEX idx_search_lookup_user_kind ON search_lookup(user_id, kind)')
class SearchLookup extends Table {
  TextColumn get originalId => text()();
  TextColumn get kind => text()();
  TextColumn get userId => text()();
  IntColumn get ftsRowid => integer()();

  @override
  Set<Column<Object>> get primaryKey => {originalId, kind, userId};

  @override
  String get tableName => 'search_lookup';
}
