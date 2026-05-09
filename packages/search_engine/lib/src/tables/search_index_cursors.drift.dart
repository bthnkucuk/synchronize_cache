// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:search_engine/src/tables/search_index_cursors.drift.dart' as i1;
import 'package:search_engine/src/tables/search_index_cursors.dart' as i2;

typedef $$SearchIndexCursorsTableCreateCompanionBuilder =
    i1.SearchIndexCursorsCompanion Function({
      required String userId,
      required String kind,
      required int lastIndexedAtMs,
      required String lastIndexedId,
      i0.Value<int> rowid,
    });
typedef $$SearchIndexCursorsTableUpdateCompanionBuilder =
    i1.SearchIndexCursorsCompanion Function({
      i0.Value<String> userId,
      i0.Value<String> kind,
      i0.Value<int> lastIndexedAtMs,
      i0.Value<String> lastIndexedId,
      i0.Value<int> rowid,
    });

class $$SearchIndexCursorsTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$SearchIndexCursorsTable> {
  $$SearchIndexCursorsTableFilterComposer({
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

  i0.ColumnFilters<int> get lastIndexedAtMs => $composableBuilder(
    column: $table.lastIndexedAtMs,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get lastIndexedId => $composableBuilder(
    column: $table.lastIndexedId,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$SearchIndexCursorsTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$SearchIndexCursorsTable> {
  $$SearchIndexCursorsTableOrderingComposer({
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

  i0.ColumnOrderings<int> get lastIndexedAtMs => $composableBuilder(
    column: $table.lastIndexedAtMs,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get lastIndexedId => $composableBuilder(
    column: $table.lastIndexedId,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$SearchIndexCursorsTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$SearchIndexCursorsTable> {
  $$SearchIndexCursorsTableAnnotationComposer({
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

  i0.GeneratedColumn<int> get lastIndexedAtMs => $composableBuilder(
    column: $table.lastIndexedAtMs,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get lastIndexedId => $composableBuilder(
    column: $table.lastIndexedId,
    builder: (column) => column,
  );
}

class $$SearchIndexCursorsTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$SearchIndexCursorsTable,
          i1.SearchIndexCursorRow,
          i1.$$SearchIndexCursorsTableFilterComposer,
          i1.$$SearchIndexCursorsTableOrderingComposer,
          i1.$$SearchIndexCursorsTableAnnotationComposer,
          $$SearchIndexCursorsTableCreateCompanionBuilder,
          $$SearchIndexCursorsTableUpdateCompanionBuilder,
          (
            i1.SearchIndexCursorRow,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i1.$SearchIndexCursorsTable,
              i1.SearchIndexCursorRow
            >,
          ),
          i1.SearchIndexCursorRow,
          i0.PrefetchHooks Function()
        > {
  $$SearchIndexCursorsTableTableManager(
    i0.GeneratedDatabase db,
    i1.$SearchIndexCursorsTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => i1.$$SearchIndexCursorsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => i1.$$SearchIndexCursorsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => i1.$$SearchIndexCursorsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<String> userId = const i0.Value.absent(),
                i0.Value<String> kind = const i0.Value.absent(),
                i0.Value<int> lastIndexedAtMs = const i0.Value.absent(),
                i0.Value<String> lastIndexedId = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.SearchIndexCursorsCompanion(
                userId: userId,
                kind: kind,
                lastIndexedAtMs: lastIndexedAtMs,
                lastIndexedId: lastIndexedId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String kind,
                required int lastIndexedAtMs,
                required String lastIndexedId,
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.SearchIndexCursorsCompanion.insert(
                userId: userId,
                kind: kind,
                lastIndexedAtMs: lastIndexedAtMs,
                lastIndexedId: lastIndexedId,
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

typedef $$SearchIndexCursorsTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$SearchIndexCursorsTable,
      i1.SearchIndexCursorRow,
      i1.$$SearchIndexCursorsTableFilterComposer,
      i1.$$SearchIndexCursorsTableOrderingComposer,
      i1.$$SearchIndexCursorsTableAnnotationComposer,
      $$SearchIndexCursorsTableCreateCompanionBuilder,
      $$SearchIndexCursorsTableUpdateCompanionBuilder,
      (
        i1.SearchIndexCursorRow,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$SearchIndexCursorsTable,
          i1.SearchIndexCursorRow
        >,
      ),
      i1.SearchIndexCursorRow,
      i0.PrefetchHooks Function()
    >;

class $SearchIndexCursorsTable extends i2.SearchIndexCursors
    with i0.TableInfo<$SearchIndexCursorsTable, i1.SearchIndexCursorRow> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchIndexCursorsTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _lastIndexedAtMsMeta =
      const i0.VerificationMeta('lastIndexedAtMs');
  @override
  late final i0.GeneratedColumn<int> lastIndexedAtMs = i0.GeneratedColumn<int>(
    'last_indexed_at_ms',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _lastIndexedIdMeta =
      const i0.VerificationMeta('lastIndexedId');
  @override
  late final i0.GeneratedColumn<String> lastIndexedId =
      i0.GeneratedColumn<String>(
        'last_indexed_id',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    userId,
    kind,
    lastIndexedAtMs,
    lastIndexedId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_index_cursors';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.SearchIndexCursorRow> instance, {
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
    if (data.containsKey('last_indexed_at_ms')) {
      context.handle(
        _lastIndexedAtMsMeta,
        lastIndexedAtMs.isAcceptableOrUnknown(
          data['last_indexed_at_ms']!,
          _lastIndexedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastIndexedAtMsMeta);
    }
    if (data.containsKey('last_indexed_id')) {
      context.handle(
        _lastIndexedIdMeta,
        lastIndexedId.isAcceptableOrUnknown(
          data['last_indexed_id']!,
          _lastIndexedIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastIndexedIdMeta);
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {userId, kind};
  @override
  i1.SearchIndexCursorRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.SearchIndexCursorRow(
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
      lastIndexedAtMs:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.int,
            data['${effectivePrefix}last_indexed_at_ms'],
          )!,
      lastIndexedId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}last_indexed_id'],
          )!,
    );
  }

  @override
  $SearchIndexCursorsTable createAlias(String alias) {
    return $SearchIndexCursorsTable(attachedDatabase, alias);
  }
}

class SearchIndexCursorRow extends i0.DataClass
    implements i0.Insertable<i1.SearchIndexCursorRow> {
  final String userId;
  final String kind;

  /// `updatedAt` of the last indexed row, stored as ms-since-epoch UTC.
  final int lastIndexedAtMs;

  /// Stable id of the last indexed row — tie-breaker when several rows
  /// share the same `updatedAt`.
  final String lastIndexedId;
  const SearchIndexCursorRow({
    required this.userId,
    required this.kind,
    required this.lastIndexedAtMs,
    required this.lastIndexedId,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['user_id'] = i0.Variable<String>(userId);
    map['kind'] = i0.Variable<String>(kind);
    map['last_indexed_at_ms'] = i0.Variable<int>(lastIndexedAtMs);
    map['last_indexed_id'] = i0.Variable<String>(lastIndexedId);
    return map;
  }

  i1.SearchIndexCursorsCompanion toCompanion(bool nullToAbsent) {
    return i1.SearchIndexCursorsCompanion(
      userId: i0.Value(userId),
      kind: i0.Value(kind),
      lastIndexedAtMs: i0.Value(lastIndexedAtMs),
      lastIndexedId: i0.Value(lastIndexedId),
    );
  }

  factory SearchIndexCursorRow.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return SearchIndexCursorRow(
      userId: serializer.fromJson<String>(json['userId']),
      kind: serializer.fromJson<String>(json['kind']),
      lastIndexedAtMs: serializer.fromJson<int>(json['lastIndexedAtMs']),
      lastIndexedId: serializer.fromJson<String>(json['lastIndexedId']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'kind': serializer.toJson<String>(kind),
      'lastIndexedAtMs': serializer.toJson<int>(lastIndexedAtMs),
      'lastIndexedId': serializer.toJson<String>(lastIndexedId),
    };
  }

  i1.SearchIndexCursorRow copyWith({
    String? userId,
    String? kind,
    int? lastIndexedAtMs,
    String? lastIndexedId,
  }) => i1.SearchIndexCursorRow(
    userId: userId ?? this.userId,
    kind: kind ?? this.kind,
    lastIndexedAtMs: lastIndexedAtMs ?? this.lastIndexedAtMs,
    lastIndexedId: lastIndexedId ?? this.lastIndexedId,
  );
  SearchIndexCursorRow copyWithCompanion(i1.SearchIndexCursorsCompanion data) {
    return SearchIndexCursorRow(
      userId: data.userId.present ? data.userId.value : this.userId,
      kind: data.kind.present ? data.kind.value : this.kind,
      lastIndexedAtMs:
          data.lastIndexedAtMs.present
              ? data.lastIndexedAtMs.value
              : this.lastIndexedAtMs,
      lastIndexedId:
          data.lastIndexedId.present
              ? data.lastIndexedId.value
              : this.lastIndexedId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchIndexCursorRow(')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('lastIndexedAtMs: $lastIndexedAtMs, ')
          ..write('lastIndexedId: $lastIndexedId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, kind, lastIndexedAtMs, lastIndexedId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.SearchIndexCursorRow &&
          other.userId == this.userId &&
          other.kind == this.kind &&
          other.lastIndexedAtMs == this.lastIndexedAtMs &&
          other.lastIndexedId == this.lastIndexedId);
}

class SearchIndexCursorsCompanion
    extends i0.UpdateCompanion<i1.SearchIndexCursorRow> {
  final i0.Value<String> userId;
  final i0.Value<String> kind;
  final i0.Value<int> lastIndexedAtMs;
  final i0.Value<String> lastIndexedId;
  final i0.Value<int> rowid;
  const SearchIndexCursorsCompanion({
    this.userId = const i0.Value.absent(),
    this.kind = const i0.Value.absent(),
    this.lastIndexedAtMs = const i0.Value.absent(),
    this.lastIndexedId = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  SearchIndexCursorsCompanion.insert({
    required String userId,
    required String kind,
    required int lastIndexedAtMs,
    required String lastIndexedId,
    this.rowid = const i0.Value.absent(),
  }) : userId = i0.Value(userId),
       kind = i0.Value(kind),
       lastIndexedAtMs = i0.Value(lastIndexedAtMs),
       lastIndexedId = i0.Value(lastIndexedId);
  static i0.Insertable<i1.SearchIndexCursorRow> custom({
    i0.Expression<String>? userId,
    i0.Expression<String>? kind,
    i0.Expression<int>? lastIndexedAtMs,
    i0.Expression<String>? lastIndexedId,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (kind != null) 'kind': kind,
      if (lastIndexedAtMs != null) 'last_indexed_at_ms': lastIndexedAtMs,
      if (lastIndexedId != null) 'last_indexed_id': lastIndexedId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.SearchIndexCursorsCompanion copyWith({
    i0.Value<String>? userId,
    i0.Value<String>? kind,
    i0.Value<int>? lastIndexedAtMs,
    i0.Value<String>? lastIndexedId,
    i0.Value<int>? rowid,
  }) {
    return i1.SearchIndexCursorsCompanion(
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      lastIndexedAtMs: lastIndexedAtMs ?? this.lastIndexedAtMs,
      lastIndexedId: lastIndexedId ?? this.lastIndexedId,
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
    if (lastIndexedAtMs.present) {
      map['last_indexed_at_ms'] = i0.Variable<int>(lastIndexedAtMs.value);
    }
    if (lastIndexedId.present) {
      map['last_indexed_id'] = i0.Variable<String>(lastIndexedId.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchIndexCursorsCompanion(')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('lastIndexedAtMs: $lastIndexedAtMs, ')
          ..write('lastIndexedId: $lastIndexedId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
