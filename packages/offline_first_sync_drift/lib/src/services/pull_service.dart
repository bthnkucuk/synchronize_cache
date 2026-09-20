import 'dart:async';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/constants.dart';
import 'package:offline_first_sync_drift/src/cursor.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/internal/event_emitter.dart';
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

  void _reportSkippedRow(
    String kind,
    Map<String, Object?>? json,
    Object error,
    StackTrace stackTrace,
  ) {
    final id = json == null
        ? null
        : json[SyncFields.id] ??
              json[SyncFields.idUpper] ??
              json[SyncFields.uuid];
    _events.emit(
      SyncErrorEvent(
        SyncPhase.pull,
        ParseException(
          'Skipped a pulled "$kind" row${id == null ? '' : ' (id $id)'} that '
          'could not be stored: $error',
          error,
          stackTrace,
        ),
        stackTrace,
      ),
    );
  }

  /// Where a pulled row is in `(updated_at, id)` order, or `null` when it
  /// does not say: either is missing, or the version is not a timestamp.
  (DateTime, String)? _positionOf(Map<String, Object?> json) {
    final ts = json[SyncFields.updatedAt] ?? json[SyncFields.updatedAtSnake];
    final id =
        json[SyncFields.id] ??
        json[SyncFields.idUpper] ??
        json[SyncFields.uuid];
    if (ts == null || id == null) return null;
    try {
      return (parseServerTimestamp(ts), id.toString());
    } on Object {
      return null;
    }
  }

  (DateTime, String) _strictPositionOf(String kind, Map<String, Object?> last) {
    final ts = last[SyncFields.updatedAt] ?? last[SyncFields.updatedAtSnake];
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
      throw ParseException('Transport returned item without id for kind=$kind');
    }
    return (parseServerTimestamp(ts), id.toString());
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

        // A row this app cannot read (a field the model does not expect, a
        // null where it needs a value, …) must not take the page down with
        // it: the cursor only moves when a page was stored, so one such row
        // stopped this kind at the same place in every later sync, forever.
        // It is skipped and reported; everything around it arrives.
        final rows = <Insertable<dynamic>>[];
        final tombstones = <bool>[];
        // Where the cursor goes after this page: the last row that names a
        // version and an id — readable by the app or not.
        (DateTime, String)? position;
        for (var i = 0; i < page.items.length; i++) {
          Map<String, Object?>? json;
          final Insertable<dynamic> row;
          try {
            // By index, inside the `try`: a transport may hand over a lazily
            // cast list (`RestTransport` does), which throws right here for
            // an element that is not a JSON object.
            json = page.items[i];
            position = _positionOf(json) ?? position;
            row = tableConfig.getInsertable(tableConfig.fromJson(json));
          } on Object catch (e, st) {
            if (!_config.skipInvalidPulledRows) rethrow;
            _reportSkippedRow(kind, json, e, st);
            continue;
          }
          final deletedAt =
              json[SyncFields.deletedAt] ?? json[SyncFields.deletedAtSnake];
          deletedAt != null ? deletes++ : upserts++;
          rows.add(row);
          tombstones.add(deletedAt != null);
        }

        try {
          await _db.batch((batch) {
            for (final row in rows) {
              batch.insert(
                tableConfig.table,
                row,
                mode: InsertMode.insertOrReplace,
              );
            }
          });
        } on Object {
          if (!_config.skipInvalidPulledRows) rethrow;
          // The database refused one of them (a constraint, most likely) and
          // rolled the whole batch back. Store them one by one to find out
          // which, and keep the rest.
          for (var i = 0; i < rows.length; i++) {
            try {
              await _db
                  .into(tableConfig.table)
                  .insert(rows[i], mode: InsertMode.insertOrReplace);
            } on Object catch (e, st) {
              tombstones[i] ? deletes-- : upserts--;
              _reportSkippedRow(kind, null, e, st);
            }
          }
        }

        _events.emit(
          CacheUpdateEvent(kind, upserts: upserts, deletes: deletes),
        );

        // With `skipInvalidPulledRows` a last row that does not say where it
        // is (no version, no id) is one more row to skip: the cursor goes to
        // the last row that does. Without it, it is the error it always was.
        final cursorRow = _config.skipInvalidPulledRows
            ? position
            : _strictPositionOf(kind, page.items.last);

        var moved = false;
        if (cursorRow != null) {
          final (nextSince, nextAfterId) = cursorRow;
          moved = !nextSince.isAtSameMomentAs(since) || nextAfterId != afterId;
          since = nextSince;
          afterId = nextAfterId;
          await _cursorService.set(kind, Cursor(ts: since, lastId: afterId));
        }

        done += page.items.length;
        _events
          ..emit(
            PullPageProcessedEvent(
              kind: kind,
              pageSize: page.items.length,
              totalDone: done,
            ),
          )
          ..emit(SyncProgress(SyncPhase.pull, done, done));

        token = page.nextPageToken;
        if (token == null && page.items.length < _config.pageSize) {
          break;
        }
        // A full page that neither moved the cursor nor names a next page
        // would be asked for again, and answered the same way, without end.
        if (token == null && !moved) break;
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
