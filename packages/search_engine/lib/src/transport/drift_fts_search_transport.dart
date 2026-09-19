import 'package:meta/meta.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/search_highlight_config.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/transport/search_transport.dart';

/// Default [SearchTransport] backed by SQLite FTS5 via drift. Wraps the
/// existing [SearchDatabaseMixin] CRUD methods so the engine never has to
/// know about FTS5 SQL directly.
@immutable
final class const DriftFtsSearchTransport(
  final SearchDatabaseMixin _db, {

  /// Applied to every query before it reaches FTS5. Pass the same function
  /// you give to `SearchEngine(normalizer: …)`: the engine normalizes what it
  /// writes, and a query that is not normalized the same way cannot match it
  /// (the trigram tokenizer does not fold Turkish `ı`/`İ`, for instance).
  final String Function(String)? normalizer,
}) implements SearchTransport {
  @override
  Future<void> upsert(GlobalSearch item) => _db.upsertSearchItem(item);

  @override
  Future<void> delete({
    required String originalId,
    required String kind,
    required String userId,
  }) =>
      _db.deleteSearchItem(originalId: originalId, kind: kind, userId: userId);

  @override
  Future<List<GlobalSearch>> search({
    required String userId,
    required String query,
    Set<String> kinds = const {},
    int offset = 0,
    int limit = 50,
    SearchHighlightConfig highlight = const SearchHighlightConfig(),
  }) => _db.searchGlobal(
    userId: userId,
    query: query,
    kinds: kinds,
    offset: offset,
    limit: limit,
    highlight: highlight,
    normalizer: normalizer,
  );

  @override
  Stream<List<GlobalSearch>> watchSearch({
    required String userId,
    required String query,
    Set<String> kinds = const {},
    int offset = 0,
    int limit = 50,
    SearchHighlightConfig highlight = const SearchHighlightConfig(),
  }) => _db.watchSearchGlobal(
    userId: userId,
    query: query,
    kinds: kinds,
    offset: offset,
    limit: limit,
    highlight: highlight,
    normalizer: normalizer,
  );
}
