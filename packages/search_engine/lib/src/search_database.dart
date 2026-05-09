import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/pending_search_item.dart';
import 'package:search_engine/src/models/search_highlight_config.dart';
import 'package:search_engine/src/tables/pending_search_items.dart';
import 'package:search_engine/src/tables/pending_search_items.drift.dart';
import 'package:search_engine/src/tables/search_index_cursors.dart';
import 'package:search_engine/src/tables/search_index_cursors.drift.dart';
import 'package:search_engine/src/tables/search_lookup.dart';
import 'package:search_engine/src/tables/search_lookup.drift.dart';

/// Mixin that adds the search-engine schema (`pending_search_items`,
/// `search_lookup`, FTS5 `global_search`) to a host drift database and
/// exposes a type-safe CRUD + query API on top of it.
///
/// Usage:
/// ```dart
/// @DriftDatabase(
///   include: {'package:search_engine/src/tables/search_tables.drift'},
///   tables: [PendingSearchItems, SearchLookup, /* ... */],
/// )
/// class MyDatabase extends $MyDatabase with SearchDatabaseMixin { ... }
/// ```
/// Cursor pinning the last `(updatedAt, id)` pair indexed for a given
/// (user, kind). Used by Phase 2 cursor-based incremental indexing.
class SearchIndexCursor {
  const SearchIndexCursor({required this.since, required this.lastId});
  final DateTime since;
  final String lastId;
}

mixin SearchDatabaseMixin on GeneratedDatabase {
  TableInfo<PendingSearchItems, PendingSearchItemRow>? _pendingTable;
  TableInfo<SearchLookup, SearchLookupData>? _lookupTable;
  TableInfo<SearchIndexCursors, SearchIndexCursorRow>? _cursorTable;

  TableInfo<PendingSearchItems, PendingSearchItemRow> get _pendingSearchItems =>
      _pendingTable ??= allTables.whereType<TableInfo<PendingSearchItems, PendingSearchItemRow>>().firstWhere(
        (t) => t.actualTableName == 'pending_search_items',
        orElse: () => throw StateError(
          'PendingSearchItems table not found. Add:\n'
          "include: {'package:search_engine/src/tables/search_tables.drift'}\n"
          'tables: [PendingSearchItems, SearchLookup, /* ... */]\n'
          'to your @DriftDatabase annotation.',
        ),
      );

  TableInfo<SearchLookup, SearchLookupData> get _searchLookup =>
      _lookupTable ??= allTables.whereType<TableInfo<SearchLookup, SearchLookupData>>().firstWhere(
        (t) => t.actualTableName == 'search_lookup',
        orElse: () => throw StateError(
          'SearchLookup table not found. Add:\n'
          "include: {'package:search_engine/src/tables/search_tables.drift'}\n"
          'tables: [PendingSearchItems, SearchLookup, /* ... */]\n'
          'to your @DriftDatabase annotation.',
        ),
      );

  TableInfo<SearchIndexCursors, SearchIndexCursorRow> get _searchIndexCursors =>
      _cursorTable ??= allTables.whereType<TableInfo<SearchIndexCursors, SearchIndexCursorRow>>().firstWhere(
        (t) => t.actualTableName == 'search_index_cursors',
        orElse: () => throw StateError(
          'SearchIndexCursors table not found. Add:\n'
          "include: {'package:search_engine/src/tables/search_tables.drift'}\n"
          'tables: [..., SearchIndexCursors]\n'
          'to your @DriftDatabase annotation.',
        ),
      );

  /// Read the cursor pinning the last `(updatedAt, id)` indexed for
  /// `(userId, kind)`. Returns `null` when no batch has run yet — caller
  /// should treat this as "start from epoch 0".
  Future<SearchIndexCursor?> readSearchIndexCursor({
    required String userId,
    required String kind,
  }) async {
    final table = _searchIndexCursors;
    final row = await (select(table)..where((c) => c.userId.equals(userId) & c.kind.equals(kind)))
        .getSingleOrNull();
    if (row == null) return null;
    return SearchIndexCursor(
      since: DateTime.fromMillisecondsSinceEpoch(row.lastIndexedAtMs, isUtc: true),
      lastId: row.lastIndexedId,
    );
  }

  /// Pin the cursor at `(updatedAt, lastId)` for `(userId, kind)`. Idempotent.
  Future<void> writeSearchIndexCursor({
    required String userId,
    required String kind,
    required DateTime updatedAt,
    required String lastId,
  }) async {
    await into(_searchIndexCursors).insertOnConflictUpdate(
      SearchIndexCursorsCompanion.insert(
        userId: userId,
        kind: kind,
        lastIndexedAtMs: updatedAt.toUtc().millisecondsSinceEpoch,
        lastIndexedId: lastId,
      ),
    );
  }

  /// Drop one or more cursors. When [kind] is omitted, every cursor for
  /// [userId] is removed. Use to force a full re-index of a kind.
  Future<void> clearSearchIndexCursors({
    required String userId,
    String? kind,
  }) async {
    final del = delete(_searchIndexCursors)..where((c) => c.userId.equals(userId));
    if (kind != null) {
      del.where((c) => c.kind.equals(kind));
    }
    await del.go();
  }

  /// Insert/update a batch of [PendingSearchItem]s into the queue. Conflicts
  /// on (id, kind) are resolved by overwriting the existing row.
  Future<void> upsertPendingUserItems(List<PendingSearchItem> items) async {
    if (items.isEmpty) return;
    await batch((b) {
      for (final item in items) {
        b.insert(
          _pendingSearchItems,
          PendingSearchItemsCompanion.insert(
            userId: item.userId,
            kind: item.kind,
            id: item.id,
            stringData: jsonEncode(item.data),
            deleted: Value(item.deleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Returns up to [limit] queued items for [userId], ordered by their
  /// physical insertion order (`rowid`). Items whose `tryCount` reached
  /// [maxTryCount] are skipped — they are dead-letters until either the
  /// threshold is raised or [resetPendingTryCount] is called.
  ///
  /// Decoding of `string_data` is delegated to [jsonDecoder] so callers can
  /// run the work on a worker pool when needed.
  Future<List<PendingSearchItem>> getPendingUserItems({
    required String userId,
    required FutureOr<dynamic> Function(String) jsonDecoder,
    int limit = 50,
    int? maxTryCount,
  }) async {
    final table = _pendingSearchItems;
    final query = select(table)..where((t) => t.userId.equals(userId));
    if (maxTryCount != null) {
      query.where((t) => t.tryCount.isSmallerThanValue(maxTryCount));
    }
    query.limit(limit);
    final rows = await query.get();
    final results = <PendingSearchItem>[];
    for (final row in rows) {
      final decoded = await jsonDecoder(row.stringData);
      results.add(
        PendingSearchItem(
          userId: row.userId,
          kind: row.kind,
          id: row.id,
          data: decoded as Map<String, dynamic>,
          deleted: row.deleted,
        ),
      );
    }
    return results;
  }

  /// Returns queued items that hit the dead-letter threshold (their
  /// `tryCount` is `>= minTryCount`). Useful for admin UIs that surface
  /// poison rows for manual inspection.
  Future<List<PendingSearchItem>> getDeadLetterPendingItems({
    required String userId,
    required int minTryCount,
    required FutureOr<dynamic> Function(String) jsonDecoder,
    int limit = 100,
  }) async {
    final table = _pendingSearchItems;
    final query = select(table)
      ..where((t) => t.userId.equals(userId))
      ..where((t) => t.tryCount.isBiggerOrEqualValue(minTryCount))
      ..limit(limit);
    final rows = await query.get();
    final results = <PendingSearchItem>[];
    for (final row in rows) {
      final decoded = await jsonDecoder(row.stringData);
      results.add(
        PendingSearchItem(
          userId: row.userId,
          kind: row.kind,
          id: row.id,
          data: decoded as Map<String, dynamic>,
          deleted: row.deleted,
        ),
      );
    }
    return results;
  }

  /// Deletes a single queued entry by its (id, kind) primary key.
  Future<void> deletePendingUserItem({required String id, required String kind}) async {
    final table = _pendingSearchItems;
    await (delete(table)..where((t) => t.id.equals(id) & t.kind.equals(kind))).go();
  }

  /// Increments the failure counter for `(id, kind)`. Once the counter
  /// reaches the engine's `maxPendingTries` the row is shadow-banned by
  /// [getPendingUserItems] until [resetPendingTryCount] is called.
  Future<void> incrementPendingTryCount({required String id, required String kind}) async {
    await customStatement(
      'UPDATE pending_search_items SET try_count = try_count + 1 WHERE id = ? AND kind = ?',
      [id, kind],
    );
  }

  /// Resets the failure counter for one (when [id]/[kind] is given) or all
  /// of [userId]'s dead-lettered rows. After this returns, the items are
  /// eligible for indexing again.
  Future<void> resetPendingTryCount({
    required String userId,
    String? id,
    String? kind,
  }) async {
    final table = _pendingSearchItems;
    final stmt = update(table)..where((t) => t.userId.equals(userId));
    if (id != null) stmt.where((t) => t.id.equals(id));
    if (kind != null) stmt.where((t) => t.kind.equals(kind));
    await stmt.write(const PendingSearchItemsCompanion(tryCount: Value(0)));
  }

  /// Removes any existing FTS5 row + lookup entry for (originalId, kind, userId).
  /// Must be called from inside a transaction.
  Future<void> _deleteNoTxn({required String originalId, required String kind, required String userId}) async {
    final lookup = _searchLookup;
    final query = select(lookup)
      ..where((t) => t.originalId.equals(originalId) & t.kind.equals(kind) & t.userId.equals(userId));
    final row = await query.getSingleOrNull();
    if (row == null) return;
    await customStatement('DELETE FROM global_search WHERE rowid = ?', [row.ftsRowid]);
    await (delete(lookup)
          ..where((t) => t.originalId.equals(originalId) & t.kind.equals(kind) & t.userId.equals(userId)))
        .go();
  }

  /// Removes a previously indexed row from the FTS5 + lookup tables.
  Future<void> deleteSearchItem({
    required String originalId,
    required String kind,
    required String userId,
  }) async {
    await transaction(() async {
      await _deleteNoTxn(originalId: originalId, kind: kind, userId: userId);
    });
  }

  /// Inserts (or replaces) a row in the FTS5 `global_search` virtual table
  /// and records the resulting rowid in `search_lookup` so it can be
  /// updated/deleted later without re-querying the index.
  Future<void> upsertSearchItem(GlobalSearch item) async {
    await transaction(() async {
      await _deleteNoTxn(originalId: item.originalId, kind: item.kind, userId: item.userId);
      final ftsRowId = await customInsert(
        'INSERT INTO global_search ('
        'original_id, user_id, kind, '
        'title, description, content, '
        'title_normalized, description_normalized, content_normalized'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(item.originalId),
          Variable.withString(item.userId),
          Variable.withString(item.kind),
          Variable.withString(item.title),
          Variable.withString(item.description),
          Variable.withString(item.content),
          Variable.withString(item.titleNormalized),
          Variable.withString(item.descriptionNormalized),
          Variable.withString(item.contentNormalized),
        ],
      );
      await into(_searchLookup).insert(
        SearchLookupCompanion.insert(
          originalId: item.originalId,
          kind: item.kind,
          userId: item.userId,
          ftsRowid: ftsRowId,
        ),
      );
    });
  }

  /// Runs an FTS5 `MATCH` query against `global_search`, scoped to [userId]
  /// and optionally to a subset of [kinds]. Results are ordered by `bm25()`
  /// relevance and decorated with `highlight()` / `snippet()` markup
  /// configured by [highlight].
  ///
  /// When [normalizer] is supplied, the user query is diacritic-stripped +
  /// lowercased and matched against the `*_normalized` columns; highlight
  /// fragments still come from the raw columns so the original glyphs are
  /// preserved in the UI.
  Future<List<GlobalSearch>> searchGlobal({
    required String userId,
    required String query,
    Set<String> kinds = const {},
    int offset = 0,
    int limit = 50,
    SearchHighlightConfig highlight = const SearchHighlightConfig(),
    String Function(String)? normalizer,
  }) async {
    final spec = _buildSearchQuery(
      userId: userId,
      query: query,
      kinds: kinds,
      offset: offset,
      limit: limit,
      highlight: highlight,
      normalizer: normalizer,
    );
    if (spec == null) return const [];
    final rows = await customSelect(spec.sql, variables: spec.variables).get();
    return rows.map(GlobalSearch.fromSql).toList();
  }

  /// Reactive variant of [searchGlobal] — emits a fresh result list whenever
  /// the search index changes. Subscribed by `StreamBuilder` UIs that want
  /// live results while sync arrives in the background.
  ///
  /// Drift's `readsFrom` cannot reference the FTS5 virtual table directly,
  /// but every `upsertSearchItem` / `deleteSearchItem` writes through the
  /// `search_lookup` table — so subscribing to its updates gives us full
  /// FTS reactivity without polling.
  Stream<List<GlobalSearch>> watchSearchGlobal({
    required String userId,
    required String query,
    Set<String> kinds = const {},
    int offset = 0,
    int limit = 50,
    SearchHighlightConfig highlight = const SearchHighlightConfig(),
    String Function(String)? normalizer,
  }) {
    final spec = _buildSearchQuery(
      userId: userId,
      query: query,
      kinds: kinds,
      offset: offset,
      limit: limit,
      highlight: highlight,
      normalizer: normalizer,
    );
    if (spec == null) return Stream<List<GlobalSearch>>.value(const []);
    return customSelect(
      spec.sql,
      variables: spec.variables,
      readsFrom: {_searchLookup},
    ).watch().map((rows) => rows.map(GlobalSearch.fromSql).toList());
  }

  ({String sql, List<Variable<Object>> variables})? _buildSearchQuery({
    required String userId,
    required String query,
    required Set<String> kinds,
    required int offset,
    required int limit,
    required SearchHighlightConfig highlight,
    required String Function(String)? normalizer,
  }) {
    // A trailing whitespace lets power users opt out of prefix matching
    // (`"foo "` → exact phrase). Anything else gets a `*` suffix so typing
    // mid-word still surfaces hits — `öner` finds `öneri` / `önerilen`.
    final explicitWord = query.endsWith(' ');
    final q = query.trim();
    if (q.isEmpty) return null;

    String quote(String s) {
      final base = '"${s.replaceAll('"', '""')}"';
      return explicitWord ? base : '$base*';
    }

    final cleanRaw = quote(q);
    String? cleanNormalized;
    if (normalizer != null) {
      final n = normalizer(q).trim();
      if (n.isNotEmpty && n != q) cleanNormalized = quote(n);
    }

    // FTS5 column-filter syntax `{c1 c2 c3}: term` scopes a sub-query to
    // those columns. We OR a raw match (to keep prefix / acronym hits on the
    // user-typed glyphs) with a normalized match (to absorb diacritic
    // mismatches). When no normalizer is in play the clause collapses to a
    // plain phrase match.
    final matchExpr = cleanNormalized == null
        ? cleanRaw
        : '({title description content}: $cleanRaw) '
            'OR ({title_normalized description_normalized content_normalized}: $cleanNormalized)';

    final kindClause = kinds.isEmpty ? '' : 'AND kind IN (${List.filled(kinds.length, '?').join(',')})';

    final variables = <Variable<Object>>[
      Variable.withString(highlight.titleOpen),
      Variable.withString(highlight.titleClose),
      Variable.withString(highlight.descOpen),
      Variable.withString(highlight.descClose),
      Variable.withString(highlight.snippetEllipsis),
      Variable.withInt(highlight.snippetTokenCount),
      Variable.withString(highlight.contentOpen),
      Variable.withString(highlight.contentClose),
      Variable.withString(highlight.snippetEllipsis),
      Variable.withInt(highlight.snippetTokenCount),
      Variable.withString(matchExpr),
      Variable.withString(userId),
      ...kinds.map(Variable.withString),
      Variable.withInt(limit),
      Variable.withInt(offset),
    ];

    final sql = 'SELECT *, '
        'highlight(global_search, 3, ?, ?) as hl_title, '
        'snippet(global_search, 4, ?, ?, ?, ?) as hl_desc, '
        'snippet(global_search, 5, ?, ?, ?, ?) as hl_content '
        'FROM global_search '
        'WHERE global_search MATCH ? '
        'AND user_id = ? '
        '$kindClause '
        'ORDER BY bm25(global_search) '
        'LIMIT ? OFFSET ?';

    return (sql: sql, variables: variables);
  }
}
