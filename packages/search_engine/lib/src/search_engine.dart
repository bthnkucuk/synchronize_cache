import 'dart:async';
import 'dart:convert';

import 'package:synchronized/synchronized.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/pending_search_item.dart';
import 'package:search_engine/src/models/searchable_table.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/transport/search_transport.dart';

typedef SearchEngineErrorHandler =
    void Function(
      Object exception, [
      StackTrace? stackTrace,
      // ignore: avoid_annotating_with_dynamic
      dynamic msg,
    ]);

/// Coordinates the queue + index pipeline:
///
/// 1. Callers `addSearchItems(...)` to enqueue [PendingSearchItem]s.
/// 2. On completion of a sync (or on demand) `processPendingItems(...)`
///    drains the queue, parses each item via the registered
///    [SearchableTable] and writes the result through [SearchTransport]
///    into the actual search backend.
///
/// The engine is backend-agnostic: it talks to [SearchTransport] for
/// reads/writes and to [SearchDatabaseMixin] for the local pending queue.
/// The queue-store dependency disappears in Phase 2 (cursor-based
/// incremental indexing).
class SearchEngine {
  SearchEngine({
    required SearchTransport transport,
    required SearchDatabaseMixin database,
    required Iterable<SearchableTable<dynamic, dynamic>> tables,
    FutureOr<dynamic> Function(String)? jsonDecoder,
    String Function(String)? normalizer,
    SearchEngineErrorHandler? errorHandler,
    int maxPendingTries = 5,
  }) : _transport = transport,
       _database = database,
       _tables = {for (final t in tables) t.kind: t},
       _jsonDecoder = jsonDecoder ?? _defaultJsonDecoder,
       _normalizer = normalizer,
       _maxPendingTries = maxPendingTries,
       _errorHandler = errorHandler;

  final SearchTransport _transport;
  final SearchDatabaseMixin _database;
  final Map<String, SearchableTable<dynamic, dynamic>> _tables;
  final FutureOr<dynamic> Function(String) _jsonDecoder;
  final String Function(String)? _normalizer;
  final SearchEngineErrorHandler? _errorHandler;

  /// `tryCount` threshold above which a pending row is considered a
  /// dead-letter and skipped by [processPendingItems]. Bumping this value
  /// (or calling [SearchDatabaseMixin.resetPendingTryCount]) re-arms the
  /// row.
  final int _maxPendingTries;
  int get maxPendingTries => _maxPendingTries;
  final Lock _lock = Lock();

  /// Diacritic-stripping normalizer applied to outbound rows (so
  /// `*_normalized` columns are filled at insert time) and exposed to
  /// callers that build their own query against [SearchTransport.search].
  String Function(String)? get normalizer => _normalizer;

  /// Backend handle — exposed so callers (search UI, tests) can issue
  /// queries without going through the engine. Engine itself only writes.
  SearchTransport get transport => _transport;

  /// Local search-side database (pending queue + cursors). Exposed so
  /// `SearchIndexer` can read/write cursors through the same lock-able
  /// engine.
  SearchDatabaseMixin get database => _database;

  /// Resolve the registered binding for [kind], or `null` when unknown.
  /// Used by `SearchIndexer` cursor-mode to call `toGlobalSearch` directly
  /// without round-tripping through the queue.
  SearchableTable<dynamic, dynamic>? tableForKind(String kind) => _tables[kind];

  /// Index a row directly through [SearchTransport], bypassing the pending
  /// queue. Used by cursor-based indexing — every call is serialized through
  /// the engine's [Lock] so it cannot interleave with [processPendingItems].
  Future<void> indexNow(GlobalSearch item) async {
    await _lock.synchronized(() => _transport.upsert(item.normalize(_normalizer)));
  }

  /// Remove a row from the index directly, bypassing the pending queue.
  Future<void> removeNow({
    required String originalId,
    required String kind,
    required String userId,
  }) async {
    await _lock.synchronized(
      () => _transport.delete(originalId: originalId, kind: kind, userId: userId),
    );
  }

  static FutureOr<dynamic> _defaultJsonDecoder(String body) => jsonDecode(body);

  /// Enqueues [items]. When [processNow] is `true`, also drains them into
  /// the search index immediately (used in tests and one-shot indexing
  /// flows).
  Future<void> addSearchItems(List<PendingSearchItem> items, {bool processNow = false}) async {
    await _database.upsertPendingUserItems(items);
    if (!processNow) return;
    for (final item in items) {
      await _processSearchItem(item);
    }
  }

  /// Drains up to [batchSize] queued items for [userId] into the search
  /// index. Concurrent invocations are serialized through an internal
  /// [Lock] so the queue is not consumed twice in parallel.
  Future<void> processPendingItems({required String userId, int batchSize = 5000}) async {
    await _lock.synchronized(() async {
      try {
        final items = await _database.getPendingUserItems(
          userId: userId,
          jsonDecoder: _jsonDecoder,
          limit: batchSize,
          maxTryCount: _maxPendingTries,
        );
        for (final item in items) {
          await _processSearchItem(item);
        }
      } catch (e, st) {
        _errorHandler?.call(e, st, 'SearchEngine.processPendingItems failed: $e\n$st');
      }
    });
  }

  Future<void> _processSearchItem(PendingSearchItem item) async {
    try {
      final table = _tables[item.kind];
      if (table == null) {
        // Unknown kind — drop the queued row to break the retry loop.
        await _database.deletePendingUserItem(id: item.id, kind: item.kind);
        return;
      }
      if (item.deleted) {
        await _transport.delete(originalId: item.id, kind: item.kind, userId: item.userId);
      } else {
        final parsed = await table.toGlobalSearch(item);
        await _transport.upsert(parsed.normalize(_normalizer));
      }
      await _database.deletePendingUserItem(id: item.id, kind: item.kind);
    } catch (e, st) {
      // Bump tryCount so a poison row eventually drops out of the queue.
      // Best-effort — even if the increment itself fails (rare), the next
      // batch will pick the row up again.
      try {
        await _database.incrementPendingTryCount(id: item.id, kind: item.kind);
      } catch (_) {
        /* swallow — log below already records the cause */
      }
      _errorHandler?.call(e, st, 'SearchEngine._processSearchItem(${item.kind}/${item.id}) failed: $e\n$st');
    }
  }
}
