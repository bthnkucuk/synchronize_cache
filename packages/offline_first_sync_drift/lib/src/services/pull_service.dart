import 'dart:async';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/constants.dart';
import 'package:offline_first_sync_drift/src/cursor.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/server_timestamp.dart';
import 'package:offline_first_sync_drift/src/services/cursor_service.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

/// Service for pulling changes from the server.
@immutable
final class PullService<DB extends GeneratedDatabase> {
  const PullService({
    required this._db,
    required this._transport,
    required this._tables,
    required this._cursorService,
    required this._config,
    required this._events,
  });

  final DB _db;
  final TransportAdapter _transport;
  final Map<String, SyncableTable<dynamic>> _tables;
  final CursorService _cursorService;
  final SyncConfig _config;
  final StreamController<SyncEvent> _events;

  /// Empty pages followed in a row before a pull gives up on a server that
  /// never returns rows.
  static const _maxConsecutiveEmptyPages = 32;

  /// Pull changes for specified kinds.
  Future<int> pullKinds(Set<String> kinds) async {
    var total = 0;
    for (final kind in kinds) {
      if (_tables.containsKey(kind)) {
        total += await pullKind(kind);
      }
    }
    return total;
  }

  /// Pull changes for a kind.
  Future<int> pullKind(String kind) async {
    final tableConfig = _tables[kind];
    if (tableConfig == null) return 0;

    int done = 0;
    String? token;
    var emptyPages = 0;

    try {
      final cursor = await _cursorService.get(kind);
      var since =
          cursor?.ts ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      var afterId = cursor?.lastId;

      while (true) {
        final page = await _transport.pull(
          kind: kind,
          updatedSince: since,
          pageSize: _config.pageSize,
          pageToken: token,
          afterId: afterId,
          includeDeleted: true,
        );

        if (page.items.isEmpty) {
          // No rows, but the server may still name a next page (a filter
          // hid every row of this one). Follow it — unless it repeats, or a
          // server keeps producing empty pages without end.
          final next = page.nextPageToken;
          emptyPages++;
          if (next == null ||
              next == token ||
              emptyPages > _maxConsecutiveEmptyPages) {
            break;
          }
          token = next;
          continue;
        }
        emptyPages = 0;

        int upserts = 0;
        int deletes = 0;

        await _db.batch((batch) {
          for (final json in page.items) {
            final entity = tableConfig.fromJson(json);
            final deletedAt =
                json[SyncFields.deletedAt] ?? json[SyncFields.deletedAtSnake];

            if (deletedAt != null) {
              deletes++;
            } else {
              upserts++;
            }

            batch.insert(
              tableConfig.table,
              tableConfig.getInsertable(entity),
              mode: InsertMode.insertOrReplace,
            );
          }
        });

        _events.add(CacheUpdateEvent(kind, upserts: upserts, deletes: deletes));

        final last = page.items.last;
        final ts =
            last[SyncFields.updatedAt] ?? last[SyncFields.updatedAtSnake];
        final id =
            last[SyncFields.id] ??
            last[SyncFields.idUpper] ??
            last[SyncFields.uuid];

        if (ts == null) {
          throw ParseException(
            'Transport returned item without updatedAt for kind=$kind',
          );
        }
        // `null.toString()` is the legal string "null"; persisting it would
        // silently poison keyset pagination for this kind.
        if (id == null) {
          throw ParseException(
            'Transport returned item without id for kind=$kind',
          );
        }

        since = parseServerTimestamp(ts);
        afterId = id.toString();
        await _cursorService.set(kind, Cursor(ts: since, lastId: afterId));

        done += page.items.length;
        _events
          ..add(
            PullPageProcessedEvent(
              kind: kind,
              pageSize: page.items.length,
              totalDone: done,
            ),
          )
          ..add(SyncProgress(SyncPhase.pull, done, done));

        token = page.nextPageToken;
        if (token == null && page.items.length < _config.pageSize) {
          break;
        }
      }
    } on SyncException {
      rethrow;
    } catch (e, st) {
      throw SyncOperationException(
        'Pull failed for kind=$kind',
        phase: 'pull',
        cause: e,
        stackTrace: st,
      );
    }

    return done;
  }
}
