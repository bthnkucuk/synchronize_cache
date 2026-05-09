// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:search_engine/src/tables/search_tables.drift.dart' as i1;

typedef $GlobalSearchCreateCompanionBuilder =
    i1.GlobalSearchCompanion Function({
      required String originalId,
      required String kind,
      required String userId,
      required String title,
      required String description,
      required String content,
      required String titleNormalized,
      required String descriptionNormalized,
      required String contentNormalized,
      i0.Value<int> rowid,
    });
typedef $GlobalSearchUpdateCompanionBuilder =
    i1.GlobalSearchCompanion Function({
      i0.Value<String> originalId,
      i0.Value<String> kind,
      i0.Value<String> userId,
      i0.Value<String> title,
      i0.Value<String> description,
      i0.Value<String> content,
      i0.Value<String> titleNormalized,
      i0.Value<String> descriptionNormalized,
      i0.Value<String> contentNormalized,
      i0.Value<int> rowid,
    });

class $GlobalSearchFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.GlobalSearch> {
  $GlobalSearchFilterComposer({
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

  i0.ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get titleNormalized => $composableBuilder(
    column: $table.titleNormalized,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get descriptionNormalized => $composableBuilder(
    column: $table.descriptionNormalized,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get contentNormalized => $composableBuilder(
    column: $table.contentNormalized,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $GlobalSearchOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.GlobalSearch> {
  $GlobalSearchOrderingComposer({
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

  i0.ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get titleNormalized => $composableBuilder(
    column: $table.titleNormalized,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get descriptionNormalized => $composableBuilder(
    column: $table.descriptionNormalized,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get contentNormalized => $composableBuilder(
    column: $table.contentNormalized,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $GlobalSearchAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.GlobalSearch> {
  $GlobalSearchAnnotationComposer({
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

  i0.GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  i0.GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  i0.GeneratedColumn<String> get titleNormalized => $composableBuilder(
    column: $table.titleNormalized,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get descriptionNormalized => $composableBuilder(
    column: $table.descriptionNormalized,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get contentNormalized => $composableBuilder(
    column: $table.contentNormalized,
    builder: (column) => column,
  );
}

class $GlobalSearchTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.GlobalSearch,
          i1.GlobalSearchData,
          i1.$GlobalSearchFilterComposer,
          i1.$GlobalSearchOrderingComposer,
          i1.$GlobalSearchAnnotationComposer,
          $GlobalSearchCreateCompanionBuilder,
          $GlobalSearchUpdateCompanionBuilder,
          (
            i1.GlobalSearchData,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i1.GlobalSearch,
              i1.GlobalSearchData
            >,
          ),
          i1.GlobalSearchData,
          i0.PrefetchHooks Function()
        > {
  $GlobalSearchTableManager(i0.GeneratedDatabase db, i1.GlobalSearch table)
    : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => i1.$GlobalSearchFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => i1.$GlobalSearchOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => i1.$GlobalSearchAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> originalId = const i0.Value.absent(),
                i0.Value<String> kind = const i0.Value.absent(),
                i0.Value<String> userId = const i0.Value.absent(),
                i0.Value<String> title = const i0.Value.absent(),
                i0.Value<String> description = const i0.Value.absent(),
                i0.Value<String> content = const i0.Value.absent(),
                i0.Value<String> titleNormalized = const i0.Value.absent(),
                i0.Value<String> descriptionNormalized =
                    const i0.Value.absent(),
                i0.Value<String> contentNormalized = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.GlobalSearchCompanion(
                originalId: originalId,
                kind: kind,
                userId: userId,
                title: title,
                description: description,
                content: content,
                titleNormalized: titleNormalized,
                descriptionNormalized: descriptionNormalized,
                contentNormalized: contentNormalized,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String originalId,
                required String kind,
                required String userId,
                required String title,
                required String description,
                required String content,
                required String titleNormalized,
                required String descriptionNormalized,
                required String contentNormalized,
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.GlobalSearchCompanion.insert(
                originalId: originalId,
                kind: kind,
                userId: userId,
                title: title,
                description: description,
                content: content,
                titleNormalized: titleNormalized,
                descriptionNormalized: descriptionNormalized,
                contentNormalized: contentNormalized,
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

typedef $GlobalSearchProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.GlobalSearch,
      i1.GlobalSearchData,
      i1.$GlobalSearchFilterComposer,
      i1.$GlobalSearchOrderingComposer,
      i1.$GlobalSearchAnnotationComposer,
      $GlobalSearchCreateCompanionBuilder,
      $GlobalSearchUpdateCompanionBuilder,
      (
        i1.GlobalSearchData,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.GlobalSearch,
          i1.GlobalSearchData
        >,
      ),
      i1.GlobalSearchData,
      i0.PrefetchHooks Function()
    >;

class GlobalSearch extends i0.Table
    with
        i0.TableInfo<GlobalSearch, i1.GlobalSearchData>,
        i0.VirtualTableInfo<GlobalSearch, i1.GlobalSearchData> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  GlobalSearch(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _originalIdMeta = const i0.VerificationMeta(
    'originalId',
  );
  late final i0.GeneratedColumn<String> originalId = i0.GeneratedColumn<String>(
    'original_id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const i0.VerificationMeta _kindMeta = const i0.VerificationMeta(
    'kind',
  );
  late final i0.GeneratedColumn<String> kind = i0.GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const i0.VerificationMeta _userIdMeta = const i0.VerificationMeta(
    'userId',
  );
  late final i0.GeneratedColumn<String> userId = i0.GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const i0.VerificationMeta _titleMeta = const i0.VerificationMeta(
    'title',
  );
  late final i0.GeneratedColumn<String> title = i0.GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const i0.VerificationMeta _descriptionMeta = const i0.VerificationMeta(
    'description',
  );
  late final i0.GeneratedColumn<String> description =
      i0.GeneratedColumn<String>(
        'description',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: '',
      );
  static const i0.VerificationMeta _contentMeta = const i0.VerificationMeta(
    'content',
  );
  late final i0.GeneratedColumn<String> content = i0.GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const i0.VerificationMeta _titleNormalizedMeta =
      const i0.VerificationMeta('titleNormalized');
  late final i0.GeneratedColumn<String> titleNormalized =
      i0.GeneratedColumn<String>(
        'title_normalized',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: '',
      );
  static const i0.VerificationMeta _descriptionNormalizedMeta =
      const i0.VerificationMeta('descriptionNormalized');
  late final i0.GeneratedColumn<String> descriptionNormalized =
      i0.GeneratedColumn<String>(
        'description_normalized',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: '',
      );
  static const i0.VerificationMeta _contentNormalizedMeta =
      const i0.VerificationMeta('contentNormalized');
  late final i0.GeneratedColumn<String> contentNormalized =
      i0.GeneratedColumn<String>(
        'content_normalized',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: '',
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    originalId,
    kind,
    userId,
    title,
    description,
    content,
    titleNormalized,
    descriptionNormalized,
    contentNormalized,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'global_search';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.GlobalSearchData> instance, {
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
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('title_normalized')) {
      context.handle(
        _titleNormalizedMeta,
        titleNormalized.isAcceptableOrUnknown(
          data['title_normalized']!,
          _titleNormalizedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_titleNormalizedMeta);
    }
    if (data.containsKey('description_normalized')) {
      context.handle(
        _descriptionNormalizedMeta,
        descriptionNormalized.isAcceptableOrUnknown(
          data['description_normalized']!,
          _descriptionNormalizedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionNormalizedMeta);
    }
    if (data.containsKey('content_normalized')) {
      context.handle(
        _contentNormalizedMeta,
        contentNormalized.isAcceptableOrUnknown(
          data['content_normalized']!,
          _contentNormalizedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentNormalizedMeta);
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => const {};
  @override
  i1.GlobalSearchData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.GlobalSearchData(
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
      title:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      description:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}description'],
          )!,
      content:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}content'],
          )!,
      titleNormalized:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}title_normalized'],
          )!,
      descriptionNormalized:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}description_normalized'],
          )!,
      contentNormalized:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}content_normalized'],
          )!,
    );
  }

  @override
  GlobalSearch createAlias(String alias) {
    return GlobalSearch(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(original_id UNINDEXED, kind UNINDEXED, user_id UNINDEXED, title, description, content, title_normalized, description_normalized, content_normalized, tokenize = \'trigram\')';
}

class GlobalSearchData extends i0.DataClass
    implements i0.Insertable<i1.GlobalSearchData> {
  final String originalId;
  final String kind;
  final String userId;
  final String title;
  final String description;
  final String content;
  final String titleNormalized;
  final String descriptionNormalized;
  final String contentNormalized;
  const GlobalSearchData({
    required this.originalId,
    required this.kind,
    required this.userId,
    required this.title,
    required this.description,
    required this.content,
    required this.titleNormalized,
    required this.descriptionNormalized,
    required this.contentNormalized,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['original_id'] = i0.Variable<String>(originalId);
    map['kind'] = i0.Variable<String>(kind);
    map['user_id'] = i0.Variable<String>(userId);
    map['title'] = i0.Variable<String>(title);
    map['description'] = i0.Variable<String>(description);
    map['content'] = i0.Variable<String>(content);
    map['title_normalized'] = i0.Variable<String>(titleNormalized);
    map['description_normalized'] = i0.Variable<String>(descriptionNormalized);
    map['content_normalized'] = i0.Variable<String>(contentNormalized);
    return map;
  }

  i1.GlobalSearchCompanion toCompanion(bool nullToAbsent) {
    return i1.GlobalSearchCompanion(
      originalId: i0.Value(originalId),
      kind: i0.Value(kind),
      userId: i0.Value(userId),
      title: i0.Value(title),
      description: i0.Value(description),
      content: i0.Value(content),
      titleNormalized: i0.Value(titleNormalized),
      descriptionNormalized: i0.Value(descriptionNormalized),
      contentNormalized: i0.Value(contentNormalized),
    );
  }

  factory GlobalSearchData.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return GlobalSearchData(
      originalId: serializer.fromJson<String>(json['original_id']),
      kind: serializer.fromJson<String>(json['kind']),
      userId: serializer.fromJson<String>(json['user_id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      content: serializer.fromJson<String>(json['content']),
      titleNormalized: serializer.fromJson<String>(json['title_normalized']),
      descriptionNormalized: serializer.fromJson<String>(
        json['description_normalized'],
      ),
      contentNormalized: serializer.fromJson<String>(
        json['content_normalized'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'original_id': serializer.toJson<String>(originalId),
      'kind': serializer.toJson<String>(kind),
      'user_id': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'content': serializer.toJson<String>(content),
      'title_normalized': serializer.toJson<String>(titleNormalized),
      'description_normalized': serializer.toJson<String>(
        descriptionNormalized,
      ),
      'content_normalized': serializer.toJson<String>(contentNormalized),
    };
  }

  i1.GlobalSearchData copyWith({
    String? originalId,
    String? kind,
    String? userId,
    String? title,
    String? description,
    String? content,
    String? titleNormalized,
    String? descriptionNormalized,
    String? contentNormalized,
  }) => i1.GlobalSearchData(
    originalId: originalId ?? this.originalId,
    kind: kind ?? this.kind,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    description: description ?? this.description,
    content: content ?? this.content,
    titleNormalized: titleNormalized ?? this.titleNormalized,
    descriptionNormalized: descriptionNormalized ?? this.descriptionNormalized,
    contentNormalized: contentNormalized ?? this.contentNormalized,
  );
  GlobalSearchData copyWithCompanion(i1.GlobalSearchCompanion data) {
    return GlobalSearchData(
      originalId:
          data.originalId.present ? data.originalId.value : this.originalId,
      kind: data.kind.present ? data.kind.value : this.kind,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      content: data.content.present ? data.content.value : this.content,
      titleNormalized:
          data.titleNormalized.present
              ? data.titleNormalized.value
              : this.titleNormalized,
      descriptionNormalized:
          data.descriptionNormalized.present
              ? data.descriptionNormalized.value
              : this.descriptionNormalized,
      contentNormalized:
          data.contentNormalized.present
              ? data.contentNormalized.value
              : this.contentNormalized,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GlobalSearchData(')
          ..write('originalId: $originalId, ')
          ..write('kind: $kind, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('content: $content, ')
          ..write('titleNormalized: $titleNormalized, ')
          ..write('descriptionNormalized: $descriptionNormalized, ')
          ..write('contentNormalized: $contentNormalized')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    originalId,
    kind,
    userId,
    title,
    description,
    content,
    titleNormalized,
    descriptionNormalized,
    contentNormalized,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.GlobalSearchData &&
          other.originalId == this.originalId &&
          other.kind == this.kind &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.description == this.description &&
          other.content == this.content &&
          other.titleNormalized == this.titleNormalized &&
          other.descriptionNormalized == this.descriptionNormalized &&
          other.contentNormalized == this.contentNormalized);
}

class GlobalSearchCompanion extends i0.UpdateCompanion<i1.GlobalSearchData> {
  final i0.Value<String> originalId;
  final i0.Value<String> kind;
  final i0.Value<String> userId;
  final i0.Value<String> title;
  final i0.Value<String> description;
  final i0.Value<String> content;
  final i0.Value<String> titleNormalized;
  final i0.Value<String> descriptionNormalized;
  final i0.Value<String> contentNormalized;
  final i0.Value<int> rowid;
  const GlobalSearchCompanion({
    this.originalId = const i0.Value.absent(),
    this.kind = const i0.Value.absent(),
    this.userId = const i0.Value.absent(),
    this.title = const i0.Value.absent(),
    this.description = const i0.Value.absent(),
    this.content = const i0.Value.absent(),
    this.titleNormalized = const i0.Value.absent(),
    this.descriptionNormalized = const i0.Value.absent(),
    this.contentNormalized = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  GlobalSearchCompanion.insert({
    required String originalId,
    required String kind,
    required String userId,
    required String title,
    required String description,
    required String content,
    required String titleNormalized,
    required String descriptionNormalized,
    required String contentNormalized,
    this.rowid = const i0.Value.absent(),
  }) : originalId = i0.Value(originalId),
       kind = i0.Value(kind),
       userId = i0.Value(userId),
       title = i0.Value(title),
       description = i0.Value(description),
       content = i0.Value(content),
       titleNormalized = i0.Value(titleNormalized),
       descriptionNormalized = i0.Value(descriptionNormalized),
       contentNormalized = i0.Value(contentNormalized);
  static i0.Insertable<i1.GlobalSearchData> custom({
    i0.Expression<String>? originalId,
    i0.Expression<String>? kind,
    i0.Expression<String>? userId,
    i0.Expression<String>? title,
    i0.Expression<String>? description,
    i0.Expression<String>? content,
    i0.Expression<String>? titleNormalized,
    i0.Expression<String>? descriptionNormalized,
    i0.Expression<String>? contentNormalized,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (originalId != null) 'original_id': originalId,
      if (kind != null) 'kind': kind,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (content != null) 'content': content,
      if (titleNormalized != null) 'title_normalized': titleNormalized,
      if (descriptionNormalized != null)
        'description_normalized': descriptionNormalized,
      if (contentNormalized != null) 'content_normalized': contentNormalized,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.GlobalSearchCompanion copyWith({
    i0.Value<String>? originalId,
    i0.Value<String>? kind,
    i0.Value<String>? userId,
    i0.Value<String>? title,
    i0.Value<String>? description,
    i0.Value<String>? content,
    i0.Value<String>? titleNormalized,
    i0.Value<String>? descriptionNormalized,
    i0.Value<String>? contentNormalized,
    i0.Value<int>? rowid,
  }) {
    return i1.GlobalSearchCompanion(
      originalId: originalId ?? this.originalId,
      kind: kind ?? this.kind,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      content: content ?? this.content,
      titleNormalized: titleNormalized ?? this.titleNormalized,
      descriptionNormalized:
          descriptionNormalized ?? this.descriptionNormalized,
      contentNormalized: contentNormalized ?? this.contentNormalized,
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
    if (title.present) {
      map['title'] = i0.Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = i0.Variable<String>(description.value);
    }
    if (content.present) {
      map['content'] = i0.Variable<String>(content.value);
    }
    if (titleNormalized.present) {
      map['title_normalized'] = i0.Variable<String>(titleNormalized.value);
    }
    if (descriptionNormalized.present) {
      map['description_normalized'] = i0.Variable<String>(
        descriptionNormalized.value,
      );
    }
    if (contentNormalized.present) {
      map['content_normalized'] = i0.Variable<String>(contentNormalized.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GlobalSearchCompanion(')
          ..write('originalId: $originalId, ')
          ..write('kind: $kind, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('content: $content, ')
          ..write('titleNormalized: $titleNormalized, ')
          ..write('descriptionNormalized: $descriptionNormalized, ')
          ..write('contentNormalized: $contentNormalized, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
