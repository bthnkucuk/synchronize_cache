import 'package:drift/drift.dart';
import 'package:search_engine/search_engine.dart';

import '../database/database.dart';

/// Everything indexed belongs to one "user" — this app has no accounts, and
/// each device already has its own database, so one constant is enough.
const _userId = 'local';

/// The shortest query FTS5's trigram tokenizer can match.
const minimumQueryLength = 3;

/// Folds the letters SQLite's trigram tokenizer cannot, then lowercases.
///
/// The tokenizer is byte-oriented: it does not know that `ı` and `I` are the
/// same letter in Turkish, so `isik` would never find `ışık`. The engine
/// stores a folded copy of every field next to the original and folds the
/// query the same way — which is why the identical function has to go to
/// both `SearchEngine` and `DriftFtsSearchTransport`.
String foldTurkish(String input) => input
    .replaceAll('İ', 'i')
    .replaceAll('I', 'i')
    .replaceAll('ı', 'i')
    .replaceAll(RegExp('[şŞ]'), 's')
    .replaceAll(RegExp('[ğĞ]'), 'g')
    .replaceAll(RegExp('[üÜ]'), 'u')
    .replaceAll(RegExp('[öÖ]'), 'o')
    .replaceAll(RegExp('[çÇ]'), 'c')
    .toLowerCase();

/// Markers FTS5 wraps around the matched text.
///
/// The library's defaults are HTML spans, which Flutter cannot render. These
/// two control characters cannot occur in user text, so [highlightSpans] can
/// split on them and produce real `TextSpan`s.
const highlightStart = '␟';
const highlightEnd = '␞';

const _highlight = SearchHighlightConfig(
  titleOpen: highlightStart,
  titleClose: highlightEnd,
  descOpen: highlightStart,
  descClose: highlightEnd,
  contentOpen: highlightStart,
  contentClose: highlightEnd,
);

/// Splits a highlighted field into plain runs and matched runs.
///
/// Returns `(text, isMatch)` pairs in order.
List<(String, bool)> highlightSpans(String value) {
  final spans = <(String, bool)>[];
  var rest = value;
  while (true) {
    final start = rest.indexOf(highlightStart);
    if (start == -1) break;
    final end = rest.indexOf(highlightEnd, start + 1);
    if (end == -1) break;
    if (start > 0) spans.add((rest.substring(0, start), false));
    spans.add((rest.substring(start + 1, end), true));
    rest = rest.substring(end + 1);
  }
  if (rest.isNotEmpty) spans.add((rest, false));
  return spans;
}

/// The global search index over every kind in this app.
///
/// Todos and notes end up in one FTS5 table, so one query answers "where did
/// I write this?" across the whole app. The index is *derived*: the indexer
/// watches the drift tables, so rows that arrive through a pull from another
/// device become searchable on their own, with no restart and nothing for
/// the repositories to remember.
class AppSearch {
  AppSearch(this._db)
    : _engine = SearchEngine(
        transport: DriftFtsSearchTransport(_db, normalizer: foldTurkish),
        database: _db,
        normalizer: foldTurkish,
        tables: _tables(_db),
      ) {
    _indexer = SearchIndexer<AppDatabase>(
      db: _db,
      searchEngine: _engine,
      tables: _tables(_db),
    );
  }

  final AppDatabase _db;
  final SearchEngine _engine;
  late final SearchIndexer<AppDatabase> _indexer;

  /// Starts watching the tables and indexes what is already there.
  Future<void> start() => _indexer.start(userId: _userId);

  /// Re-arms every indexing loop; called after a sync brought new rows in
  /// case a table-update notification was missed.
  Future<void> refresh() => _indexer.refreshAll();

  Future<void> stop() => _indexer.stop();

  /// Results for [query], updated while the user types.
  ///
  /// A query shorter than [minimumQueryLength] yields nothing: the trigram
  /// tokenizer has no 1- or 2-character tokens to match.
  Stream<List<GlobalSearch>> watch(
    String query, {
    Set<String> kinds = const {},
  }) {
    if (query.trim().length < minimumQueryLength) {
      return Stream.value(const []);
    }
    return _engine.transport.watchSearch(
      userId: _userId,
      query: query,
      kinds: kinds,
      highlight: _highlight,
    );
  }

  /// How many documents the index holds right now.
  Stream<int> watchIndexedCount() => _db
      .customSelect(
        'SELECT count(*) AS c FROM search_lookup WHERE user_id = ?',
        variables: const [Variable<String>(_userId)],
        readsFrom: {_db.searchLookup},
      )
      .watchSingle()
      .map((row) => row.read<int>('c'));

  /// How many documents are queued but not indexed yet.
  Stream<int> watchPendingCount() => _db
      .customSelect(
        'SELECT count(*) AS c FROM pending_search_items WHERE user_id = ?',
        variables: const [Variable<String>(_userId)],
        readsFrom: {_db.pendingSearchItems},
      )
      .watchSingle()
      .map((row) => row.read<int>('c'));

  /// One binding per kind.
  ///
  /// `kind` must be the real SQL table name: the indexer subscribes to drift
  /// table updates by that name, and it is also the sync kind, so a search
  /// hit maps straight back to a row.
  static List<SearchableTable<AppDatabase, dynamic>> _tables(AppDatabase db) =>
      [_todos(db), _notes(db)];

  static SearchableTable<AppDatabase, Todo> _todos(AppDatabase db) =>
      searchableTable<AppDatabase, Todo>(
        kind: 'todos',
        watch: (db, _) => db.select(db.todos).watch(),
        idOf: (todo) => todo.id,
        // Deleted rows must still be *seen* so their tombstone can remove
        // them from the index; that is why this is a flag, not a filter.
        isDeleted: (todo) =>
            todo.deletedAt != null || todo.deletedAtLocal != null,
        toJson: (todo) => todo.toJson(),
        updatedAtOf: (todo) => todo.updatedAt,
        readSince: (db, _, since, lastId, limit) => _pageSince(
          db.select(db.todos),
          updatedAt: db.todos.updatedAt,
          id: db.todos.id,
          since: since,
          lastId: lastId,
          limit: limit,
        ),
        toGlobalSearch: (item) async => GlobalSearch(
          originalId: item.id,
          userId: item.userId,
          kind: item.kind,
          title: (item.data['title'] as String?) ?? '',
          description: (item.data['description'] as String?) ?? '',
          content: '',
        ),
      );

  static SearchableTable<AppDatabase, Note> _notes(AppDatabase db) =>
      searchableTable<AppDatabase, Note>(
        kind: 'notes',
        watch: (db, _) => db.select(db.notes).watch(),
        idOf: (note) => note.id,
        isDeleted: (note) =>
            note.deletedAt != null || note.deletedAtLocal != null,
        toJson: (note) => note.toJson(),
        updatedAtOf: (note) => note.updatedAt,
        readSince: (db, _, since, lastId, limit) => _pageSince(
          db.select(db.notes),
          updatedAt: db.notes.updatedAt,
          id: db.notes.id,
          since: since,
          lastId: lastId,
          limit: limit,
        ),
        toGlobalSearch: (item) async => GlobalSearch(
          originalId: item.id,
          userId: item.userId,
          kind: item.kind,
          title: (item.data['title'] as String?) ?? '',
          description: (item.data['body'] as String?) ?? '',
          content: '',
        ),
      );

  /// One page of rows after `(since, lastId)`, in `(updated_at, id)` order.
  ///
  /// The same keyset paging the sync pull uses, for the same reason: rows
  /// that share a timestamp must not be skipped or indexed twice.
  static Future<List<T>> _pageSince<Tbl extends HasResultSet, T>(
    SimpleSelectStatement<Tbl, T> select, {
    required GeneratedColumn<DateTime> updatedAt,
    required GeneratedColumn<String> id,
    required DateTime since,
    required String? lastId,
    required int limit,
  }) {
    return (select
          ..where(
            (_) =>
                updatedAt.isBiggerThanValue(since) |
                (updatedAt.equals(since) &
                    (lastId == null
                        ? const Constant(true)
                        : id.isBiggerThanValue(lastId))),
          )
          ..orderBy([
            (_) => OrderingTerm(expression: updatedAt),
            (_) => OrderingTerm(expression: id),
          ])
          ..limit(limit))
        .get();
  }
}
