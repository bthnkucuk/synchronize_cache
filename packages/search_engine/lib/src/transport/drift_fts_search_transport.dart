import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/search_highlight_config.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/transport/search_transport.dart';

/// Default [SearchTransport] backed by SQLite FTS5 via drift. Wraps the
/// existing [SearchDatabaseMixin] CRUD methods so the engine never has to
/// know about FTS5 SQL directly.
class DriftFtsSearchTransport implements SearchTransport {
  DriftFtsSearchTransport(this._db);

  final SearchDatabaseMixin _db;

  @override
  Future<void> upsert(GlobalSearch item) => _db.upsertSearchItem(item);

  @override
  Future<void> delete({
    required String originalId,
    required String kind,
    required String userId,
  }) => _db.deleteSearchItem(originalId: originalId, kind: kind, userId: userId);

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
      );

  @override
  Stream<List<GlobalSearch>> watchSearch({
    required String userId,
    required String query,
    Set<String> kinds = const {},
    int offset = 0,
    int limit = 50,
    SearchHighlightConfig highlight = const SearchHighlightConfig(),
  }) =>
      _db.watchSearchGlobal(
        userId: userId,
        query: query,
        kinds: kinds,
        offset: offset,
        limit: limit,
        highlight: highlight,
      );
}
