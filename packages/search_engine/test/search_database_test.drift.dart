// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:search_engine/src/tables/search_tables.drift.dart' as i1;
import 'package:search_engine/src/tables/search_index_cursors.drift.dart' as i2;
import 'package:search_engine/src/tables/search_lookup.drift.dart' as i3;
import 'package:search_engine/src/tables/pending_search_items.drift.dart' as i4;

abstract class $TestSearchDatabase extends i0.GeneratedDatabase {
  $TestSearchDatabase(i0.QueryExecutor e) : super(e);
  $TestSearchDatabaseManager get managers => $TestSearchDatabaseManager(this);
  late final i1.GlobalSearch globalSearch = i1.GlobalSearch(this);
  late final i2.$SearchIndexCursorsTable searchIndexCursors = i2
      .$SearchIndexCursorsTable(this);
  late final i3.$SearchLookupTable searchLookup = i3.$SearchLookupTable(this);
  late final i4.$PendingSearchItemsTable pendingSearchItems = i4
      .$PendingSearchItemsTable(this);
  @override
  Iterable<i0.TableInfo<i0.Table, Object?>> get allTables =>
      allSchemaEntities.whereType<i0.TableInfo<i0.Table, Object?>>();
  @override
  List<i0.DatabaseSchemaEntity> get allSchemaEntities => [
    globalSearch,
    searchIndexCursors,
    searchLookup,
    i3.idxSearchLookupUserKind,
    pendingSearchItems,
    i4.idxPendingSearchItemsUserId,
  ];
  @override
  i0.DriftDatabaseOptions get options =>
      const i0.DriftDatabaseOptions(storeDateTimeAsText: true);
}

class $TestSearchDatabaseManager {
  final $TestSearchDatabase _db;
  $TestSearchDatabaseManager(this._db);
  i1.$GlobalSearchTableManager get globalSearch =>
      i1.$GlobalSearchTableManager(_db, _db.globalSearch);
  i2.$$SearchIndexCursorsTableTableManager get searchIndexCursors =>
      i2.$$SearchIndexCursorsTableTableManager(_db, _db.searchIndexCursors);
  i3.$$SearchLookupTableTableManager get searchLookup =>
      i3.$$SearchLookupTableTableManager(_db, _db.searchLookup);
  i4.$$PendingSearchItemsTableTableManager get pendingSearchItems =>
      i4.$$PendingSearchItemsTableTableManager(_db, _db.pendingSearchItems);
}
