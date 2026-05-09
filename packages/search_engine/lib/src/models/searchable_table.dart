import 'dart:async';

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/pending_search_item.dart';

/// Declarative description of a single Drift table that participates in the
/// global search index — the search-side mirror of `SyncableTable` from
/// `offline_first_sync_drift`.
///
/// One concrete [SearchableTable] (or [searchableTable] factory call) lives
/// per indexable kind. It bundles three concerns that previously sat in
/// separate places:
///
/// 1. **Where the data lives** — [watch] returns the live Drift stream.
/// 2. **How to project a row to JSON** — [toJson] (cheap, sync; persisted
///    verbatim into `pending_search_items.string_data`).
/// 3. **How to enrich a queued item into a [GlobalSearch] row** —
///    [toGlobalSearch] (heavy, async; URL fetch / decode).
///
/// Both `SearchEngine` (read side: enrichment) and `SearchIndexer` (write
/// side: stream + projection) consume the same instance.
abstract class SearchableTable<DB extends GeneratedDatabase, T> {
  const SearchableTable();

  /// Stable identifier used for the FTS5 `kind` column and the registry
  /// key. Should match the backend entity name (e.g. `'project_notes'`).
  String get kind;

  /// Live Drift stream of all rows belonging to [userId]. Subscribed by
  /// `SearchIndexer` and republished on every mutation.
  ///
  /// Implementations should include soft-deleted rows so the indexer can
  /// mirror tombstones into the index.
  Stream<List<T>> watch(DB db, String userId);

  /// Stable id of [row] (the same value used as the FTS `original_id`).
  String idOf(T row);

  /// Whether [row] should be removed from the search index. Typically
  /// driven by `deletedAt` / `deletedAtLocal` on `SyncColumns`.
  bool isDeleted(T row);

  /// Cheap, synchronous JSON projection — persisted into
  /// `pending_search_items.string_data` so [toGlobalSearch] can run later,
  /// off the write path.
  Map<String, dynamic> toJson(T row);

  /// Heavy enrichment + final projection. Runs inside
  /// `SearchEngine.processPendingItems` behind a Lock. URL fetch, file
  /// decode, JSON parse — anything that should not block writes — belongs
  /// here.
  ///
  /// Default: pulls `title` / `description` / `content` straight from the
  /// JSON map produced by [toJson]. Override for kinds that need to fetch
  /// remote text (e.g. transcription output URL).
  FutureOr<GlobalSearch> toGlobalSearch(PendingSearchItem item) {
    return GlobalSearch(
      originalId: item.id,
      userId: item.userId,
      kind: item.kind,
      title: (item.data['title'] as String?) ?? '',
      description: (item.data['description'] as String?) ?? '',
      content: (item.data['content'] as String?) ?? '',
    );
  }

  /// `updatedAt` of [row] — used by cursor-based incremental indexing.
  /// Default throws so misconfigured bindings fail fast at the indexer.
  DateTime updatedAtOf(T row) => throw UnsupportedError(
        'updatedAtOf not implemented for kind=$kind. Override it before '
        'enabling cursor-based incremental indexing.',
      );

  /// Fetch the next batch of rows after the cursor `(since, lastId)`,
  /// ordered by `(updatedAt asc, id asc)` and capped at [limit].
  ///
  /// Pass `lastId == null` for "start from epoch" semantics. Implementations
  /// should use the half-open condition
  /// `updatedAt > since OR (updatedAt == since AND id > lastId)` so a single
  /// cursor uniquely identifies progress even when many rows share the same
  /// `updatedAt`.
  ///
  /// Default throws — required for cursor-based indexing.
  Future<List<T>> readSince(
    DB db,
    String userId,
    DateTime since,
    String? lastId,
    int limit,
  ) =>
      throw UnsupportedError(
        'readSince not implemented for kind=$kind. Override it before '
        'enabling cursor-based incremental indexing.',
      );
}

/// Lambda-based [SearchableTable] — no subclass required for the common
/// case. Reach for a custom subclass only when the binding needs internal
/// state, helper methods, or its own dependency injection seams.
class _CallbackSearchableTable<DB extends GeneratedDatabase, T> extends SearchableTable<DB, T> {
  const _CallbackSearchableTable({
    required String kind,
    required Stream<List<T>> Function(DB, String) watch,
    required String Function(T) idOf,
    required Map<String, dynamic> Function(T) toJson,
    bool Function(T)? isDeleted,
    FutureOr<GlobalSearch> Function(PendingSearchItem)? toGlobalSearch,
    DateTime Function(T)? updatedAtOf,
    Future<List<T>> Function(DB, String userId, DateTime since, String? lastId, int limit)? readSince,
  }) : _kind = kind,
       _watch = watch,
       _idOf = idOf,
       _toJson = toJson,
       _isDeleted = isDeleted,
       _toGlobalSearch = toGlobalSearch,
       _updatedAtOf = updatedAtOf,
       _readSince = readSince;

  final String _kind;
  final Stream<List<T>> Function(DB, String) _watch;
  final String Function(T) _idOf;
  final Map<String, dynamic> Function(T) _toJson;
  final bool Function(T)? _isDeleted;
  final FutureOr<GlobalSearch> Function(PendingSearchItem)? _toGlobalSearch;
  final DateTime Function(T)? _updatedAtOf;
  final Future<List<T>> Function(DB, String, DateTime, String?, int)? _readSince;

  @override
  String get kind => _kind;

  @override
  Stream<List<T>> watch(DB db, String userId) => _watch(db, userId);

  @override
  String idOf(T row) => _idOf(row);

  @override
  bool isDeleted(T row) => _isDeleted?.call(row) ?? false;

  @override
  Map<String, dynamic> toJson(T row) => _toJson(row);

  @override
  FutureOr<GlobalSearch> toGlobalSearch(PendingSearchItem item) =>
      _toGlobalSearch?.call(item) ?? super.toGlobalSearch(item);

  @override
  DateTime updatedAtOf(T row) =>
      _updatedAtOf?.call(row) ?? super.updatedAtOf(row);

  @override
  Future<List<T>> readSince(DB db, String userId, DateTime since, String? lastId, int limit) =>
      _readSince?.call(db, userId, since, lastId, limit) ?? super.readSince(db, userId, since, lastId, limit);
}

/// Build a [SearchableTable] from inline callbacks — avoids one boilerplate
/// subclass per kind.
///
/// [isDeleted] defaults to `(_) => false` — pass an explicit callback for
/// tables with `deletedAt` / `deletedAtLocal` columns.
///
/// [toGlobalSearch] is optional; when omitted the default JSON projection
/// from [SearchableTable] is used.
///
/// [updatedAtOf] is optional in Phase 1 (queue-based indexing); becomes
/// required for Phase 2 cursor-based incremental indexing.
SearchableTable<DB, T> searchableTable<DB extends GeneratedDatabase, T>({
  required String kind,
  required Stream<List<T>> Function(DB db, String userId) watch,
  required String Function(T row) idOf,
  required Map<String, dynamic> Function(T row) toJson,
  bool Function(T row)? isDeleted,
  FutureOr<GlobalSearch> Function(PendingSearchItem item)? toGlobalSearch,
  DateTime Function(T row)? updatedAtOf,
  Future<List<T>> Function(DB db, String userId, DateTime since, String? lastId, int limit)? readSince,
}) {
  return _CallbackSearchableTable<DB, T>(
    kind: kind,
    watch: watch,
    idOf: idOf,
    toJson: toJson,
    isDeleted: isDeleted,
    toGlobalSearch: toGlobalSearch,
    updatedAtOf: updatedAtOf,
    readSince: readSince,
  );
}
