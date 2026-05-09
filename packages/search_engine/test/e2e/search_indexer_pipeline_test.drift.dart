// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:search_engine/src/tables/search_tables.drift.dart' as i1;
import 'package:search_engine/src/tables/search_index_cursors.drift.dart' as i2;
import 'package:search_engine/src/tables/search_lookup.drift.dart' as i3;
import 'package:search_engine/src/tables/pending_search_items.drift.dart' as i4;
import 'search_indexer_pipeline_test.drift.dart' as i5;
import 'search_indexer_pipeline_test.dart' as i6;
import 'package:drift/src/runtime/query_builder/query_builder.dart' as i7;

typedef $$NotesTableCreateCompanionBuilder =
    i5.NotesCompanion Function({
      required String id,
      required String userId,
      required String title,
      required int updatedAtMs,
      i0.Value<bool> deleted,
      i0.Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    i5.NotesCompanion Function({
      i0.Value<String> id,
      i0.Value<String> userId,
      i0.Value<String> title,
      i0.Value<int> updatedAtMs,
      i0.Value<bool> deleted,
      i0.Value<int> rowid,
    });

class $$NotesTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i5.$NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i5.$NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i5.$NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  i0.GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  i0.GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  i0.GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);
}

class $$NotesTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i5.$NotesTable,
          i5.Note,
          i5.$$NotesTableFilterComposer,
          i5.$$NotesTableOrderingComposer,
          i5.$$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (
            i5.Note,
            i0.BaseReferences<i0.GeneratedDatabase, i5.$NotesTable, i5.Note>,
          ),
          i5.Note,
          i0.PrefetchHooks Function()
        > {
  $$NotesTableTableManager(i0.GeneratedDatabase db, i5.$NotesTable table)
    : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => i5.$$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => i5.$$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => i5.$$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> id = const i0.Value.absent(),
                i0.Value<String> userId = const i0.Value.absent(),
                i0.Value<String> title = const i0.Value.absent(),
                i0.Value<int> updatedAtMs = const i0.Value.absent(),
                i0.Value<bool> deleted = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i5.NotesCompanion(
                id: id,
                userId: userId,
                title: title,
                updatedAtMs: updatedAtMs,
                deleted: deleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String title,
                required int updatedAtMs,
                i0.Value<bool> deleted = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i5.NotesCompanion.insert(
                id: id,
                userId: userId,
                title: title,
                updatedAtMs: updatedAtMs,
                deleted: deleted,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          i0.BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i5.$NotesTable,
      i5.Note,
      i5.$$NotesTableFilterComposer,
      i5.$$NotesTableOrderingComposer,
      i5.$$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (
        i5.Note,
        i0.BaseReferences<i0.GeneratedDatabase, i5.$NotesTable, i5.Note>,
      ),
      i5.Note,
      i0.PrefetchHooks Function()
    >;

abstract class $TestIndexerDatabase extends i0.GeneratedDatabase {
  $TestIndexerDatabase(i0.QueryExecutor e) : super(e);
  $TestIndexerDatabaseManager get managers => $TestIndexerDatabaseManager(this);
  late final i1.GlobalSearch globalSearch = i1.GlobalSearch(this);
  late final i2.$SearchIndexCursorsTable searchIndexCursors = i2
      .$SearchIndexCursorsTable(this);
  late final i3.$SearchLookupTable searchLookup = i3.$SearchLookupTable(this);
  late final i4.$PendingSearchItemsTable pendingSearchItems = i4
      .$PendingSearchItemsTable(this);
  late final i5.$NotesTable notes = i5.$NotesTable(this);
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
    notes,
  ];
  @override
  i0.DriftDatabaseOptions get options =>
      const i0.DriftDatabaseOptions(storeDateTimeAsText: true);
}

class $TestIndexerDatabaseManager {
  final $TestIndexerDatabase _db;
  $TestIndexerDatabaseManager(this._db);
  i1.$GlobalSearchTableManager get globalSearch =>
      i1.$GlobalSearchTableManager(_db, _db.globalSearch);
  i2.$$SearchIndexCursorsTableTableManager get searchIndexCursors =>
      i2.$$SearchIndexCursorsTableTableManager(_db, _db.searchIndexCursors);
  i3.$$SearchLookupTableTableManager get searchLookup =>
      i3.$$SearchLookupTableTableManager(_db, _db.searchLookup);
  i4.$$PendingSearchItemsTableTableManager get pendingSearchItems =>
      i4.$$PendingSearchItemsTableTableManager(_db, _db.pendingSearchItems);
  i5.$$NotesTableTableManager get notes =>
      i5.$$NotesTableTableManager(_db, _db.notes);
}

class $NotesTable extends i6.Notes with i0.TableInfo<$NotesTable, i5.Note> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<String> id = i0.GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _userIdMeta = const i0.VerificationMeta(
    'userId',
  );
  @override
  late final i0.GeneratedColumn<String> userId = i0.GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _titleMeta = const i0.VerificationMeta(
    'title',
  );
  @override
  late final i0.GeneratedColumn<String> title = i0.GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _updatedAtMsMeta = const i0.VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final i0.GeneratedColumn<int> updatedAtMs = i0.GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _deletedMeta = const i0.VerificationMeta(
    'deleted',
  );
  @override
  late final i0.GeneratedColumn<bool> deleted = i0.GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: i0.DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const i7.Constant(false),
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    id,
    userId,
    title,
    updatedAtMs,
    deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rows';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i5.Note> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {id};
  @override
  i5.Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i5.Note(
      id:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      userId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}user_id'],
          )!,
      title:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      updatedAtMs:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.int,
            data['${effectivePrefix}updated_at_ms'],
          )!,
      deleted:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.bool,
            data['${effectivePrefix}deleted'],
          )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends i0.DataClass implements i0.Insertable<i5.Note> {
  final String id;
  final String userId;
  final String title;
  final int updatedAtMs;
  final bool deleted;
  const Note({
    required this.id,
    required this.userId,
    required this.title,
    required this.updatedAtMs,
    required this.deleted,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['id'] = i0.Variable<String>(id);
    map['user_id'] = i0.Variable<String>(userId);
    map['title'] = i0.Variable<String>(title);
    map['updated_at_ms'] = i0.Variable<int>(updatedAtMs);
    map['deleted'] = i0.Variable<bool>(deleted);
    return map;
  }

  i5.NotesCompanion toCompanion(bool nullToAbsent) {
    return i5.NotesCompanion(
      id: i0.Value(id),
      userId: i0.Value(userId),
      title: i0.Value(title),
      updatedAtMs: i0.Value(updatedAtMs),
      deleted: i0.Value(deleted),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      title: serializer.fromJson<String>(json['title']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      deleted: serializer.fromJson<bool>(json['deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'deleted': serializer.toJson<bool>(deleted),
    };
  }

  i5.Note copyWith({
    String? id,
    String? userId,
    String? title,
    int? updatedAtMs,
    bool? deleted,
  }) => i5.Note(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    deleted: deleted ?? this.deleted,
  );
  Note copyWithCompanion(i5.NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      updatedAtMs:
          data.updatedAtMs.present ? data.updatedAtMs.value : this.updatedAtMs,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, title, updatedAtMs, deleted);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i5.Note &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.updatedAtMs == this.updatedAtMs &&
          other.deleted == this.deleted);
}

class NotesCompanion extends i0.UpdateCompanion<i5.Note> {
  final i0.Value<String> id;
  final i0.Value<String> userId;
  final i0.Value<String> title;
  final i0.Value<int> updatedAtMs;
  final i0.Value<bool> deleted;
  final i0.Value<int> rowid;
  const NotesCompanion({
    this.id = const i0.Value.absent(),
    this.userId = const i0.Value.absent(),
    this.title = const i0.Value.absent(),
    this.updatedAtMs = const i0.Value.absent(),
    this.deleted = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    required String userId,
    required String title,
    required int updatedAtMs,
    this.deleted = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : id = i0.Value(id),
       userId = i0.Value(userId),
       title = i0.Value(title),
       updatedAtMs = i0.Value(updatedAtMs);
  static i0.Insertable<i5.Note> custom({
    i0.Expression<String>? id,
    i0.Expression<String>? userId,
    i0.Expression<String>? title,
    i0.Expression<int>? updatedAtMs,
    i0.Expression<bool>? deleted,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (deleted != null) 'deleted': deleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i5.NotesCompanion copyWith({
    i0.Value<String>? id,
    i0.Value<String>? userId,
    i0.Value<String>? title,
    i0.Value<int>? updatedAtMs,
    i0.Value<bool>? deleted,
    i0.Value<int>? rowid,
  }) {
    return i5.NotesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      deleted: deleted ?? this.deleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (id.present) {
      map['id'] = i0.Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = i0.Variable<String>(userId.value);
    }
    if (title.present) {
      map['title'] = i0.Variable<String>(title.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = i0.Variable<int>(updatedAtMs.value);
    }
    if (deleted.present) {
      map['deleted'] = i0.Variable<bool>(deleted.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('deleted: $deleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
