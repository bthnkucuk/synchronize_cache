// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:search_engine/src/tables/pending_search_items.drift.dart' as i1;
import 'package:search_engine/src/tables/pending_search_items.dart' as i2;
import 'package:drift/src/runtime/query_builder/query_builder.dart' as i3;

typedef $$PendingSearchItemsTableCreateCompanionBuilder =
    i1.PendingSearchItemsCompanion Function({
      required String userId,
      required String kind,
      required String id,
      required String stringData,
      i0.Value<bool> deleted,
      i0.Value<int> tryCount,
      i0.Value<int> rowid,
    });
typedef $$PendingSearchItemsTableUpdateCompanionBuilder =
    i1.PendingSearchItemsCompanion Function({
      i0.Value<String> userId,
      i0.Value<String> kind,
      i0.Value<String> id,
      i0.Value<String> stringData,
      i0.Value<bool> deleted,
      i0.Value<int> tryCount,
      i0.Value<int> rowid,
    });

class $$PendingSearchItemsTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PendingSearchItemsTable> {
  $$PendingSearchItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get stringData => $composableBuilder(
    column: $table.stringData,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get tryCount => $composableBuilder(
    column: $table.tryCount,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$PendingSearchItemsTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PendingSearchItemsTable> {
  $$PendingSearchItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get stringData => $composableBuilder(
    column: $table.stringData,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get tryCount => $composableBuilder(
    column: $table.tryCount,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$PendingSearchItemsTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PendingSearchItemsTable> {
  $$PendingSearchItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  i0.GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  i0.GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<String> get stringData => $composableBuilder(
    column: $table.stringData,
    builder: (column) => column,
  );

  i0.GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  i0.GeneratedColumn<int> get tryCount =>
      $composableBuilder(column: $table.tryCount, builder: (column) => column);
}

class $$PendingSearchItemsTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$PendingSearchItemsTable,
          i1.PendingSearchItemRow,
          i1.$$PendingSearchItemsTableFilterComposer,
          i1.$$PendingSearchItemsTableOrderingComposer,
          i1.$$PendingSearchItemsTableAnnotationComposer,
          $$PendingSearchItemsTableCreateCompanionBuilder,
          $$PendingSearchItemsTableUpdateCompanionBuilder,
          (
            i1.PendingSearchItemRow,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i1.$PendingSearchItemsTable,
              i1.PendingSearchItemRow
            >,
          ),
          i1.PendingSearchItemRow,
          i0.PrefetchHooks Function()
        > {
  $$PendingSearchItemsTableTableManager(
    i0.GeneratedDatabase db,
    i1.$PendingSearchItemsTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => i1.$$PendingSearchItemsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => i1.$$PendingSearchItemsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => i1.$$PendingSearchItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<String> userId = const i0.Value.absent(),
                i0.Value<String> kind = const i0.Value.absent(),
                i0.Value<String> id = const i0.Value.absent(),
                i0.Value<String> stringData = const i0.Value.absent(),
                i0.Value<bool> deleted = const i0.Value.absent(),
                i0.Value<int> tryCount = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.PendingSearchItemsCompanion(
                userId: userId,
                kind: kind,
                id: id,
                stringData: stringData,
                deleted: deleted,
                tryCount: tryCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String kind,
                required String id,
                required String stringData,
                i0.Value<bool> deleted = const i0.Value.absent(),
                i0.Value<int> tryCount = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.PendingSearchItemsCompanion.insert(
                userId: userId,
                kind: kind,
                id: id,
                stringData: stringData,
                deleted: deleted,
                tryCount: tryCount,
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

typedef $$PendingSearchItemsTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$PendingSearchItemsTable,
      i1.PendingSearchItemRow,
      i1.$$PendingSearchItemsTableFilterComposer,
      i1.$$PendingSearchItemsTableOrderingComposer,
      i1.$$PendingSearchItemsTableAnnotationComposer,
      $$PendingSearchItemsTableCreateCompanionBuilder,
      $$PendingSearchItemsTableUpdateCompanionBuilder,
      (
        i1.PendingSearchItemRow,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$PendingSearchItemsTable,
          i1.PendingSearchItemRow
        >,
      ),
      i1.PendingSearchItemRow,
      i0.PrefetchHooks Function()
    >;
i0.Index get idxPendingSearchItemsUserId => i0.Index(
  'idx_pending_search_items_user_id',
  'CREATE INDEX idx_pending_search_items_user_id ON pending_search_items (user_id)',
);

class $PendingSearchItemsTable extends i2.PendingSearchItems
    with i0.TableInfo<$PendingSearchItemsTable, i1.PendingSearchItemRow> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSearchItemsTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _kindMeta = const i0.VerificationMeta(
    'kind',
  );
  @override
  late final i0.GeneratedColumn<String> kind = i0.GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<String> id = i0.GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _stringDataMeta = const i0.VerificationMeta(
    'stringData',
  );
  @override
  late final i0.GeneratedColumn<String> stringData = i0.GeneratedColumn<String>(
    'string_data',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
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
    defaultValue: const i3.Constant(false),
  );
  static const i0.VerificationMeta _tryCountMeta = const i0.VerificationMeta(
    'tryCount',
  );
  @override
  late final i0.GeneratedColumn<int> tryCount = i0.GeneratedColumn<int>(
    'try_count',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    userId,
    kind,
    id,
    stringData,
    deleted,
    tryCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_search_items';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.PendingSearchItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('string_data')) {
      context.handle(
        _stringDataMeta,
        stringData.isAcceptableOrUnknown(data['string_data']!, _stringDataMeta),
      );
    } else if (isInserting) {
      context.missing(_stringDataMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('try_count')) {
      context.handle(
        _tryCountMeta,
        tryCount.isAcceptableOrUnknown(data['try_count']!, _tryCountMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {id, kind};
  @override
  i1.PendingSearchItemRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.PendingSearchItemRow(
      userId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}user_id'],
          )!,
      kind:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
      id:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      stringData:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}string_data'],
          )!,
      deleted:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.bool,
            data['${effectivePrefix}deleted'],
          )!,
      tryCount:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.int,
            data['${effectivePrefix}try_count'],
          )!,
    );
  }

  @override
  $PendingSearchItemsTable createAlias(String alias) {
    return $PendingSearchItemsTable(attachedDatabase, alias);
  }
}

class PendingSearchItemRow extends i0.DataClass
    implements i0.Insertable<i1.PendingSearchItemRow> {
  final String userId;
  final String kind;
  final String id;
  final String stringData;
  final bool deleted;

  /// How many times the engine has tried to parse this item without success.
  /// Reaches `SearchEngine.maxPendingTries` ⇒ row becomes a dead-letter and
  /// is skipped by `getPendingUserItems` until either the threshold is
  /// raised or the cursor is reset manually.
  final int tryCount;
  const PendingSearchItemRow({
    required this.userId,
    required this.kind,
    required this.id,
    required this.stringData,
    required this.deleted,
    required this.tryCount,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['user_id'] = i0.Variable<String>(userId);
    map['kind'] = i0.Variable<String>(kind);
    map['id'] = i0.Variable<String>(id);
    map['string_data'] = i0.Variable<String>(stringData);
    map['deleted'] = i0.Variable<bool>(deleted);
    map['try_count'] = i0.Variable<int>(tryCount);
    return map;
  }

  i1.PendingSearchItemsCompanion toCompanion(bool nullToAbsent) {
    return i1.PendingSearchItemsCompanion(
      userId: i0.Value(userId),
      kind: i0.Value(kind),
      id: i0.Value(id),
      stringData: i0.Value(stringData),
      deleted: i0.Value(deleted),
      tryCount: i0.Value(tryCount),
    );
  }

  factory PendingSearchItemRow.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return PendingSearchItemRow(
      userId: serializer.fromJson<String>(json['userId']),
      kind: serializer.fromJson<String>(json['kind']),
      id: serializer.fromJson<String>(json['id']),
      stringData: serializer.fromJson<String>(json['stringData']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      tryCount: serializer.fromJson<int>(json['tryCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'kind': serializer.toJson<String>(kind),
      'id': serializer.toJson<String>(id),
      'stringData': serializer.toJson<String>(stringData),
      'deleted': serializer.toJson<bool>(deleted),
      'tryCount': serializer.toJson<int>(tryCount),
    };
  }

  i1.PendingSearchItemRow copyWith({
    String? userId,
    String? kind,
    String? id,
    String? stringData,
    bool? deleted,
    int? tryCount,
  }) => i1.PendingSearchItemRow(
    userId: userId ?? this.userId,
    kind: kind ?? this.kind,
    id: id ?? this.id,
    stringData: stringData ?? this.stringData,
    deleted: deleted ?? this.deleted,
    tryCount: tryCount ?? this.tryCount,
  );
  PendingSearchItemRow copyWithCompanion(i1.PendingSearchItemsCompanion data) {
    return PendingSearchItemRow(
      userId: data.userId.present ? data.userId.value : this.userId,
      kind: data.kind.present ? data.kind.value : this.kind,
      id: data.id.present ? data.id.value : this.id,
      stringData:
          data.stringData.present ? data.stringData.value : this.stringData,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      tryCount: data.tryCount.present ? data.tryCount.value : this.tryCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSearchItemRow(')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('stringData: $stringData, ')
          ..write('deleted: $deleted, ')
          ..write('tryCount: $tryCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, kind, id, stringData, deleted, tryCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.PendingSearchItemRow &&
          other.userId == this.userId &&
          other.kind == this.kind &&
          other.id == this.id &&
          other.stringData == this.stringData &&
          other.deleted == this.deleted &&
          other.tryCount == this.tryCount);
}

class PendingSearchItemsCompanion
    extends i0.UpdateCompanion<i1.PendingSearchItemRow> {
  final i0.Value<String> userId;
  final i0.Value<String> kind;
  final i0.Value<String> id;
  final i0.Value<String> stringData;
  final i0.Value<bool> deleted;
  final i0.Value<int> tryCount;
  final i0.Value<int> rowid;
  const PendingSearchItemsCompanion({
    this.userId = const i0.Value.absent(),
    this.kind = const i0.Value.absent(),
    this.id = const i0.Value.absent(),
    this.stringData = const i0.Value.absent(),
    this.deleted = const i0.Value.absent(),
    this.tryCount = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  PendingSearchItemsCompanion.insert({
    required String userId,
    required String kind,
    required String id,
    required String stringData,
    this.deleted = const i0.Value.absent(),
    this.tryCount = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : userId = i0.Value(userId),
       kind = i0.Value(kind),
       id = i0.Value(id),
       stringData = i0.Value(stringData);
  static i0.Insertable<i1.PendingSearchItemRow> custom({
    i0.Expression<String>? userId,
    i0.Expression<String>? kind,
    i0.Expression<String>? id,
    i0.Expression<String>? stringData,
    i0.Expression<bool>? deleted,
    i0.Expression<int>? tryCount,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (kind != null) 'kind': kind,
      if (id != null) 'id': id,
      if (stringData != null) 'string_data': stringData,
      if (deleted != null) 'deleted': deleted,
      if (tryCount != null) 'try_count': tryCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.PendingSearchItemsCompanion copyWith({
    i0.Value<String>? userId,
    i0.Value<String>? kind,
    i0.Value<String>? id,
    i0.Value<String>? stringData,
    i0.Value<bool>? deleted,
    i0.Value<int>? tryCount,
    i0.Value<int>? rowid,
  }) {
    return i1.PendingSearchItemsCompanion(
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      id: id ?? this.id,
      stringData: stringData ?? this.stringData,
      deleted: deleted ?? this.deleted,
      tryCount: tryCount ?? this.tryCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (userId.present) {
      map['user_id'] = i0.Variable<String>(userId.value);
    }
    if (kind.present) {
      map['kind'] = i0.Variable<String>(kind.value);
    }
    if (id.present) {
      map['id'] = i0.Variable<String>(id.value);
    }
    if (stringData.present) {
      map['string_data'] = i0.Variable<String>(stringData.value);
    }
    if (deleted.present) {
      map['deleted'] = i0.Variable<bool>(deleted.value);
    }
    if (tryCount.present) {
      map['try_count'] = i0.Variable<int>(tryCount.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSearchItemsCompanion(')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('stringData: $stringData, ')
          ..write('deleted: $deleted, ')
          ..write('tryCount: $tryCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
