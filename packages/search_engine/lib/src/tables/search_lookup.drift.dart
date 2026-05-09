// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:search_engine/src/tables/search_lookup.drift.dart' as i1;
import 'package:search_engine/src/tables/search_lookup.dart' as i2;

typedef $$SearchLookupTableCreateCompanionBuilder =
    i1.SearchLookupCompanion Function({
      required String originalId,
      required String kind,
      required String userId,
      required int ftsRowid,
      i0.Value<int> rowid,
    });
typedef $$SearchLookupTableUpdateCompanionBuilder =
    i1.SearchLookupCompanion Function({
      i0.Value<String> originalId,
      i0.Value<String> kind,
      i0.Value<String> userId,
      i0.Value<int> ftsRowid,
      i0.Value<int> rowid,
    });

class $$SearchLookupTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$SearchLookupTable> {
  $$SearchLookupTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get originalId => $composableBuilder(
    column: $table.originalId,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get ftsRowid => $composableBuilder(
    column: $table.ftsRowid,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$SearchLookupTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$SearchLookupTable> {
  $$SearchLookupTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get originalId => $composableBuilder(
    column: $table.originalId,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get ftsRowid => $composableBuilder(
    column: $table.ftsRowid,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$SearchLookupTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$SearchLookupTable> {
  $$SearchLookupTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get originalId => $composableBuilder(
    column: $table.originalId,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  i0.GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  i0.GeneratedColumn<int> get ftsRowid =>
      $composableBuilder(column: $table.ftsRowid, builder: (column) => column);
}

class $$SearchLookupTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$SearchLookupTable,
          i1.SearchLookupData,
          i1.$$SearchLookupTableFilterComposer,
          i1.$$SearchLookupTableOrderingComposer,
          i1.$$SearchLookupTableAnnotationComposer,
          $$SearchLookupTableCreateCompanionBuilder,
          $$SearchLookupTableUpdateCompanionBuilder,
          (
            i1.SearchLookupData,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i1.$SearchLookupTable,
              i1.SearchLookupData
            >,
          ),
          i1.SearchLookupData,
          i0.PrefetchHooks Function()
        > {
  $$SearchLookupTableTableManager(
    i0.GeneratedDatabase db,
    i1.$SearchLookupTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  i1.$$SearchLookupTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => i1.$$SearchLookupTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => i1.$$SearchLookupTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<String> originalId = const i0.Value.absent(),
                i0.Value<String> kind = const i0.Value.absent(),
                i0.Value<String> userId = const i0.Value.absent(),
                i0.Value<int> ftsRowid = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.SearchLookupCompanion(
                originalId: originalId,
                kind: kind,
                userId: userId,
                ftsRowid: ftsRowid,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String originalId,
                required String kind,
                required String userId,
                required int ftsRowid,
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.SearchLookupCompanion.insert(
                originalId: originalId,
                kind: kind,
                userId: userId,
                ftsRowid: ftsRowid,
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

typedef $$SearchLookupTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$SearchLookupTable,
      i1.SearchLookupData,
      i1.$$SearchLookupTableFilterComposer,
      i1.$$SearchLookupTableOrderingComposer,
      i1.$$SearchLookupTableAnnotationComposer,
      $$SearchLookupTableCreateCompanionBuilder,
      $$SearchLookupTableUpdateCompanionBuilder,
      (
        i1.SearchLookupData,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$SearchLookupTable,
          i1.SearchLookupData
        >,
      ),
      i1.SearchLookupData,
      i0.PrefetchHooks Function()
    >;
i0.Index get idxSearchLookupUserKind => i0.Index(
  'idx_search_lookup_user_kind',
  'CREATE INDEX idx_search_lookup_user_kind ON search_lookup (user_id, kind)',
);

class $SearchLookupTable extends i2.SearchLookup
    with i0.TableInfo<$SearchLookupTable, i1.SearchLookupData> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchLookupTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _originalIdMeta = const i0.VerificationMeta(
    'originalId',
  );
  @override
  late final i0.GeneratedColumn<String> originalId = i0.GeneratedColumn<String>(
    'original_id',
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
  static const i0.VerificationMeta _ftsRowidMeta = const i0.VerificationMeta(
    'ftsRowid',
  );
  @override
  late final i0.GeneratedColumn<int> ftsRowid = i0.GeneratedColumn<int>(
    'fts_rowid',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<i0.GeneratedColumn> get $columns => [originalId, kind, userId, ftsRowid];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_lookup';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.SearchLookupData> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('original_id')) {
      context.handle(
        _originalIdMeta,
        originalId.isAcceptableOrUnknown(data['original_id']!, _originalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_originalIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('fts_rowid')) {
      context.handle(
        _ftsRowidMeta,
        ftsRowid.isAcceptableOrUnknown(data['fts_rowid']!, _ftsRowidMeta),
      );
    } else if (isInserting) {
      context.missing(_ftsRowidMeta);
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {originalId, kind, userId};
  @override
  i1.SearchLookupData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.SearchLookupData(
      originalId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}original_id'],
          )!,
      kind:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
      userId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}user_id'],
          )!,
      ftsRowid:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.int,
            data['${effectivePrefix}fts_rowid'],
          )!,
    );
  }

  @override
  $SearchLookupTable createAlias(String alias) {
    return $SearchLookupTable(attachedDatabase, alias);
  }
}

class SearchLookupData extends i0.DataClass
    implements i0.Insertable<i1.SearchLookupData> {
  final String originalId;
  final String kind;
  final String userId;
  final int ftsRowid;
  const SearchLookupData({
    required this.originalId,
    required this.kind,
    required this.userId,
    required this.ftsRowid,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['original_id'] = i0.Variable<String>(originalId);
    map['kind'] = i0.Variable<String>(kind);
    map['user_id'] = i0.Variable<String>(userId);
    map['fts_rowid'] = i0.Variable<int>(ftsRowid);
    return map;
  }

  i1.SearchLookupCompanion toCompanion(bool nullToAbsent) {
    return i1.SearchLookupCompanion(
      originalId: i0.Value(originalId),
      kind: i0.Value(kind),
      userId: i0.Value(userId),
      ftsRowid: i0.Value(ftsRowid),
    );
  }

  factory SearchLookupData.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return SearchLookupData(
      originalId: serializer.fromJson<String>(json['originalId']),
      kind: serializer.fromJson<String>(json['kind']),
      userId: serializer.fromJson<String>(json['userId']),
      ftsRowid: serializer.fromJson<int>(json['ftsRowid']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'originalId': serializer.toJson<String>(originalId),
      'kind': serializer.toJson<String>(kind),
      'userId': serializer.toJson<String>(userId),
      'ftsRowid': serializer.toJson<int>(ftsRowid),
    };
  }

  i1.SearchLookupData copyWith({
    String? originalId,
    String? kind,
    String? userId,
    int? ftsRowid,
  }) => i1.SearchLookupData(
    originalId: originalId ?? this.originalId,
    kind: kind ?? this.kind,
    userId: userId ?? this.userId,
    ftsRowid: ftsRowid ?? this.ftsRowid,
  );
  SearchLookupData copyWithCompanion(i1.SearchLookupCompanion data) {
    return SearchLookupData(
      originalId:
          data.originalId.present ? data.originalId.value : this.originalId,
      kind: data.kind.present ? data.kind.value : this.kind,
      userId: data.userId.present ? data.userId.value : this.userId,
      ftsRowid: data.ftsRowid.present ? data.ftsRowid.value : this.ftsRowid,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchLookupData(')
          ..write('originalId: $originalId, ')
          ..write('kind: $kind, ')
          ..write('userId: $userId, ')
          ..write('ftsRowid: $ftsRowid')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(originalId, kind, userId, ftsRowid);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.SearchLookupData &&
          other.originalId == this.originalId &&
          other.kind == this.kind &&
          other.userId == this.userId &&
          other.ftsRowid == this.ftsRowid);
}

class SearchLookupCompanion extends i0.UpdateCompanion<i1.SearchLookupData> {
  final i0.Value<String> originalId;
  final i0.Value<String> kind;
  final i0.Value<String> userId;
  final i0.Value<int> ftsRowid;
  final i0.Value<int> rowid;
  const SearchLookupCompanion({
    this.originalId = const i0.Value.absent(),
    this.kind = const i0.Value.absent(),
    this.userId = const i0.Value.absent(),
    this.ftsRowid = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  SearchLookupCompanion.insert({
    required String originalId,
    required String kind,
    required String userId,
    required int ftsRowid,
    this.rowid = const i0.Value.absent(),
  }) : originalId = i0.Value(originalId),
       kind = i0.Value(kind),
       userId = i0.Value(userId),
       ftsRowid = i0.Value(ftsRowid);
  static i0.Insertable<i1.SearchLookupData> custom({
    i0.Expression<String>? originalId,
    i0.Expression<String>? kind,
    i0.Expression<String>? userId,
    i0.Expression<int>? ftsRowid,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (originalId != null) 'original_id': originalId,
      if (kind != null) 'kind': kind,
      if (userId != null) 'user_id': userId,
      if (ftsRowid != null) 'fts_rowid': ftsRowid,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.SearchLookupCompanion copyWith({
    i0.Value<String>? originalId,
    i0.Value<String>? kind,
    i0.Value<String>? userId,
    i0.Value<int>? ftsRowid,
    i0.Value<int>? rowid,
  }) {
    return i1.SearchLookupCompanion(
      originalId: originalId ?? this.originalId,
      kind: kind ?? this.kind,
      userId: userId ?? this.userId,
      ftsRowid: ftsRowid ?? this.ftsRowid,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (originalId.present) {
      map['original_id'] = i0.Variable<String>(originalId.value);
    }
    if (kind.present) {
      map['kind'] = i0.Variable<String>(kind.value);
    }
    if (userId.present) {
      map['user_id'] = i0.Variable<String>(userId.value);
    }
    if (ftsRowid.present) {
      map['fts_rowid'] = i0.Variable<int>(ftsRowid.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchLookupCompanion(')
          ..write('originalId: $originalId, ')
          ..write('kind: $kind, ')
          ..write('userId: $userId, ')
          ..write('ftsRowid: $ftsRowid, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
