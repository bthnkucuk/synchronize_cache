import 'dart:async';

import 'package:drift/drift.dart' show GeneratedDatabase, TableUpdateQuery;
import 'package:rxdart/rxdart.dart';
import 'package:search_engine/search_engine.dart';
import 'package:synchronized/synchronized.dart';

/// Cursor-based incremental indexer.
///
/// For each registered [SearchableTable] it subscribes to drift's
/// `tableUpdates(...)` event stream — a lightweight "the table changed"
/// signal that does NOT replay every row — and runs a bounded batch loop
/// that pulls only rows newer than the per-(user, kind) cursor stored in
/// `search_index_cursors`. Each row's `toGlobalSearch` runs through
/// `SearchEngine.indexNow` (transport-direct, no pending queue).
///
/// Compared to the Phase 1 watch-based indexer, this scales to large tables
/// because:
/// - one mutation triggers one cursor advance, not a full-table re-emit;
/// - URL-fetching parsers (transcription, summarization) only run for
///   actually-changed rows.
class SearchIndexer<DB extends GeneratedDatabase> {
  SearchIndexer({
    required this.db,
    required this.searchEngine,
    required this.tables,
    this.debounce = const Duration(milliseconds: 500),
    this.batchSize = 100,
  });

  final DB db;
  final SearchEngine searchEngine;

  /// Registered bindings. One stream subscription per table is opened on
  /// [start] and torn down on [stop].
  final List<SearchableTable<DB, dynamic>> tables;

  /// Coalesces rapid bursts of writes so the batch loop runs once per quiet
  /// window instead of per row.
  final Duration debounce;

  /// How many rows to fetch per `readSince` call. The loop continues until
  /// a partial batch indicates "no more rows".
  final int batchSize;

  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<String, Lock> _locks = {};
  String? _userId;

  /// Currently subscribed user, or `null` when stopped.
  String? get currentUserId => _userId;

  /// Subscribe to all registered tables for [userId]. Calling [start] again
  /// replaces previous subscriptions atomically.
  Future<void> start({required String userId}) async {
    await stop();
    _userId = userId;

    for (final table in tables) {
      // Initial drain — catch up with anything that was missed while the
      // indexer was off (cold start, user just signed in, etc).
      unawaited(_runBatch(table, userId));

      // React to subsequent mutations. `tableUpdates(onTableName)` does NOT
      // re-emit row data — it just tells us the table changed.
      _subs.add(
        db
            .tableUpdates(TableUpdateQuery.onTableName(table.kind))
            .debounceTime(debounce)
            .listen((_) => unawaited(_runBatch(table, userId))),
      );
    }
  }

  Future<void> _runBatch(
    SearchableTable<DB, dynamic> table,
    String userId,
  ) async {
    // Bail if the user changed since this batch was scheduled.
    if (_userId != userId) return;

    final lock = _locks.putIfAbsent(table.kind, Lock.new);
    await lock.synchronized(() async {
      try {
        final cursor = await searchEngine.database.readSearchIndexCursor(
          userId: userId,
          kind: table.kind,
        );
        var since =
            cursor?.since ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        var lastId = cursor?.lastId;

        while (true) {
          // Bail if the user changed mid-loop.
          if (_userId != userId) return;

          final rows = await table.readSince(
            db,
            userId,
            since,
            lastId,
            batchSize,
          );
          if (rows.isEmpty) return;

          for (final row in rows) {
            final id = table.idOf(row);
            if (table.isDeleted(row)) {
              await searchEngine.removeNow(
                originalId: id,
                kind: table.kind,
                userId: userId,
              );
            } else {
              final pendingItem = PendingSearchItem(
                userId: userId,
                kind: table.kind,
                id: id,
                data: table.toJson(row),
                deleted: false,
              );
              final globalSearch = await table.toGlobalSearch(pendingItem);
              await searchEngine.indexNow(globalSearch);
            }
          }

          final last = rows.last;
          since = table.updatedAtOf(last);
          lastId = table.idOf(last);

          await searchEngine.database.writeSearchIndexCursor(
            userId: userId,
            kind: table.kind,
            updatedAt: since,
            lastId: lastId,
          );

          // Partial batch ⇒ no more rows for now. Stay parked until the next
          // tableUpdates emit re-arms the loop.
          if (rows.length < batchSize) return;
        }
      } catch (e, _) {
        // Indexer is best-effort; the cursor wasn't advanced past the failed
        // row so it'll be retried on the next mutation.
        // ignore: avoid_print
        // print('SearchIndexer(${table.kind}) error: $e\n$st');
      }
    });
  }

  /// Re-arm every registered table's batch loop without re-subscribing —
  /// safety net for cases where `tableUpdates` emissions are lost or
  /// debounced out around lifecycle boundaries (e.g. anonymous→real
  /// sign-in handoff, where the first pull batch can land in the gap
  /// between [stop] and [start]). Cheap when there is nothing new: the
  /// cursor immediately reports an empty `readSince`.
  Future<void> refreshAll() async {
    final userId = _userId;
    if (userId == null) return;
    for (final table in tables) {
      unawaited(_runBatch(table, userId));
    }
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _userId = null;
  }
}
