import 'dart:async';

import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/search_highlight_config.dart';

/// Backend-agnostic contract for the search index. The mirror of
/// `TransportAdapter` in `offline_first_sync_drift`: lets the engine talk
/// to a swappable backend (FTS5 today, Algolia/Meilisearch/server-side
/// tomorrow) without leaking implementation details.
///
/// Concrete implementations live in `transport/`:
/// - [DriftFtsSearchTransport] — SQLite FTS5 + drift (default)
abstract class SearchTransport {
  /// Insert (or replace) [item] in the index.
  Future<void> upsert(GlobalSearch item);

  /// Remove the index row identified by `(originalId, kind, userId)`.
  Future<void> delete({
    required String originalId,
    required String kind,
    required String userId,
  });

  /// One-shot keyword search. Returns up to [limit] items ordered by the
  /// backend's relevance signal (BM25 for FTS5).
  Future<List<GlobalSearch>> search({
    required String userId,
    required String query,
    Set<String> kinds = const {},
    int offset = 0,
    int limit = 50,
    SearchHighlightConfig highlight = const SearchHighlightConfig(),
  });

  /// Reactive variant of [search] — emits a new list whenever the
  /// underlying index changes. Backends that cannot stream natively may
  /// fall back to polling or `Stream.value(...)` for one-shot semantics.
  Stream<List<GlobalSearch>> watchSearch({
    required String userId,
    required String query,
    Set<String> kinds = const {},
    int offset = 0,
    int limit = 50,
    SearchHighlightConfig highlight = const SearchHighlightConfig(),
  });
}
