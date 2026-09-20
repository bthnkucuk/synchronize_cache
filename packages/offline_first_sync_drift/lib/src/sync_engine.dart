import 'dart:async';

import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/constants.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/internal/event_emitter.dart';
import 'package:offline_first_sync_drift/src/op.dart';
import 'package:offline_first_sync_drift/src/services/conflict_service.dart';
import 'package:offline_first_sync_drift/src/services/cursor_service.dart';
import 'package:offline_first_sync_drift/src/services/outbox_service.dart';
import 'package:offline_first_sync_drift/src/services/pull_service.dart';
import 'package:offline_first_sync_drift/src/services/push_service.dart';
import 'package:offline_first_sync_drift/src/sync_database.dart';
import 'package:offline_first_sync_drift/src/sync_error.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

/// Rich result model for a sync run.
class SyncRunResult {
  const SyncRunResult({
    required this.push,
    required this.pull,
    required this.stats,
    required this.duration,
    required this.kindsPushed,
    required this.kindsPulled,
    required this.stuckOpsCount,
    this.firstError,
  });

  final PushStats push;
  final PullStats pull;
  final SyncStats stats;
  final Duration duration;
  final Set<String> kindsPushed;
  final Set<String> kindsPulled;
  final int stuckOpsCount;
  final SyncErrorInfo? firstError;

  bool get hadErrors => stats.errors > 0 || firstError != null;
}

final class const PullStats({required final int pulled});

/// Synchronization engine: push → pull with pagination and conflict resolution.
///
/// The core engine that orchestrates the sync process between local database
/// and remote server. Handles:
/// - Pushing local changes from outbox to server
/// - Pulling remote changes with cursor-based pagination
/// - Conflict resolution with multiple strategies
/// - Automatic background sync
///
/// Example:
/// ```dart
/// final engine = SyncEngine(
///   db: database,
///   transport: RestTransport(base: Uri.parse('https://api.example.com')),
///   tables: [
///     SyncableTable<Todo>(
///       kind: 'todos',
///       table: database.todos,
///       fromJson: Todo.fromJson,
///       toJson: (t) => t.toJson(),
///       toInsertable: (t) => t.toInsertable(),
///     ),
///   ],
/// );
///
/// await engine.sync();
/// ```
class SyncEngine<DB extends GeneratedDatabase>({
  required final DB _db,
  required final TransportAdapter _transport,
  required List<SyncableTable<dynamic>> tables,
  final SyncConfig _config = const SyncConfig(),
  Map<String, TableConflictConfig>? tableConflictConfigs,
}) {
  this {
    if (_db is! SyncDatabaseMixin) {
      throw ArgumentError(
        'Database must implement SyncDatabaseMixin. '
        'Add "with SyncDatabaseMixin" to your database class.',
      );
    }

    _registerEnqueuePushHook();
  }

  final Map<String, SyncableTable<dynamic>> _tables = _buildTablesMap(tables);
  final Map<String, TableConflictConfig> _tableConflictConfigs =
      tableConflictConfigs ?? {};

  final _events = StreamController<SyncEvent>.broadcast();

  // Created on first use: by then the constructor has checked the database.
  late final OutboxService _outboxService = OutboxService(_syncDb);
  late final CursorService _cursorService = CursorService(_syncDb);
  late final ConflictService<DB> _conflictService = ConflictService<DB>(
    db: _db,
    transport: _transport,
    tables: _tables,
    config: _config,
    tableConflictConfigs: _tableConflictConfigs,
    events: _events,
  );
  late final PushService _pushService = PushService(
    db: _db,
    outbox: _outboxService,
    transport: _transport,
    conflictService: _conflictService,
    tables: _tables,
    config: _config,
    events: _events,
  );
  late final PullService<DB> _pullService = PullService<DB>(
    db: _db,
    transport: _transport,
    tables: _tables,
    cursorService: _cursorService,
    config: _config,
    events: _events,
  );

  SyncDatabaseMixin get _syncDb => _db as SyncDatabaseMixin;

  Future<void>? _outboxIndexesReady;

  /// A database created by an older version of this package has the outbox
  /// without its indexes; create them before the first sync of this engine.
  Future<void> _ensureOutboxIndexes() =>
      _outboxIndexesReady ??= _createOutboxIndexes();

  Future<void> _createOutboxIndexes() async {
    try {
      await _syncDb.ensureSyncIndexes();
    } catch (_) {
      // They only make the outbox queries faster: never fail a sync over
      // them, try again with the next one.
      _outboxIndexesReady = null;
    }
  }

  static Map<String, SyncableTable<dynamic>> _buildTablesMap(
    List<SyncableTable<dynamic>> tables,
  ) {
    final map = <String, SyncableTable<dynamic>>{};
    for (final table in tables) {
      final kind = table.kind.trim();
      if (kind.isEmpty) {
        throw ArgumentError.value(
          table.kind,
          'tables.kind',
          'kind must not be empty',
        );
      }
      if (map.containsKey(kind)) {
        throw ArgumentError(
          'Duplicate table kind "$kind". Each SyncableTable kind must be unique.',
        );
      }
      map[kind] = table;
    }
    return map;
  }

  /// Stream of sync events for monitoring progress and errors.
  Stream<SyncEvent> get events => _events.stream;

  /// Service for managing outbox operations.
  OutboxService get outbox => _outboxService;

  /// Service for managing sync cursors.
  CursorService get cursors => _cursorService;

  /// Return operations that reached stuck threshold.
  Future<List<Op>> getStuckOperations({Set<String>? kinds}) => _outboxService
      .getStuck(minTryCount: _config.maxOutboxTryCount, kinds: kinds);

  /// Reset retry counters for stuck operations.
  Future<void> retryStuckOperations({Set<String>? kinds}) async {
    final stuck = await getStuckOperations(kinds: kinds);
    await _outboxService.resetTryCount(stuck.map((op) => op.opId));
  }

  /// Drop stuck operations from outbox.
  ///
  /// A dropped operation was never applied by the server, but its effect is
  /// still in the local row: the edit that was given up, a row that was
  /// created, a row marked as deleted. With the operation gone nothing would
  /// say so any more — the row would differ from the server while looking
  /// synced, until it happens to change there again. So every affected row is
  /// fetched again and written back (or removed, when the server does not
  /// have it). An operation whose row cannot be fetched right now — no
  /// connection — is **kept**, so that "no operation queued" keeps meaning
  /// "same as the server"; a [SyncErrorEvent] reports it.
  ///
  /// Two cases leave the row as it is: newer operations of the same row are
  /// still queued (the row is theirs, also when they were enqueued while the
  /// server was being asked), or the server's version is one this app cannot
  /// read (dropped as asked, and reported with a [ParseException]).
  Future<void> dropStuckOperations({Set<String>? kinds}) async {
    final stuck = await getStuckOperations(kinds: kinds);

    final byEntity = <(String, String), List<String>>{};
    for (final op in stuck) {
      byEntity.putIfAbsent((op.kind, op.id), () => []).add(op.opId);
    }

    // Row by row, each one settled on its own: a row that cannot be restored
    // (or an error while trying) does not keep the others.
    for (final MapEntry(key: (kind, id), value: opIds) in byEntity.entries) {
      if (await _hasLiveOps(kind, id)) {
        // Newer edits of the same row that are still on their way keep their
        // say: the row is theirs until they are pushed.
        await _outboxService.ack(opIds);
      } else {
        await _discard(kind, id, opIds);
      }
    }
  }

  /// Whether `(kind, id)` has operations queued that are not stuck.
  Future<bool> _hasLiveOps(String kind, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 FROM ${TableNames.syncOutbox} '
          'WHERE ${TableColumns.kind} = ? AND ${TableColumns.entityId} = ? '
          'AND ${TableColumns.tryCount} < ? LIMIT 1',
          variables: [
            Variable.withString(kind),
            Variable.withString(id),
            Variable.withInt(_config.maxOutboxTryCount),
          ],
        )
        .get();
    return rows.isNotEmpty;
  }

  /// Drops the stuck operations [opIds] of `(kind, id)` and makes the local
  /// row what the server has. Leaves both alone when the server could not be
  /// asked.
  Future<void> _discard(String kind, String id, List<String> opIds) async {
    final tableConfig = _tables[kind];
    if (tableConfig == null) {
      await _outboxService.ack(opIds);
      return;
    }

    final FetchResult result;
    try {
      result = await _transport.fetch(kind: kind, id: id);
    } on Object catch (e, st) {
      _events.emit(SyncErrorEvent(SyncPhase.push, e, st));
      return;
    }

    Insertable<dynamic>? serverRow;
    switch (result) {
      case FetchError(:final error, :final stackTrace):
        _events.emit(SyncErrorEvent(SyncPhase.push, error, stackTrace));
        return;
      case FetchSuccess(:final data):
        try {
          serverRow = tableConfig.getInsertable(tableConfig.fromJson(data));
        } on Object catch (e, st) {
          // The server has the row, in a form this app cannot read — a pull
          // skips such a row too. The operations are dropped as asked; the
          // local row cannot be made the server's, and the app is told.
          _reportUnrestoredRow(kind, id, e, st);
        }
      case FetchNotFound():
        break;
    }

    await _db.transaction(() async {
      // An edit made while the server was being asked owns the row now.
      if (!await _hasLiveOps(kind, id)) {
        try {
          if (serverRow != null) {
            await _db.into(tableConfig.table).insertOnConflictUpdate(serverRow);
          } else if (result is FetchNotFound) {
            await _deleteLocalRow(tableConfig, id);
          }
        } on Object catch (e, st) {
          _reportUnrestoredRow(kind, id, e, st);
        }
      }
      await _outboxService.ack(opIds);
    });
  }

  Future<void> _deleteLocalRow(
    SyncableTable<dynamic> tableConfig,
    String id,
  ) async {
    final pk = tableConfig.table.$primaryKey;
    if (pk.length != 1) return;
    await _db.customUpdate(
      'DELETE FROM "${tableConfig.table.actualTableName}" '
      'WHERE "${pk.first.name}" = ?',
      variables: [Variable.withString(id)],
      updates: {tableConfig.table},
      updateKind: UpdateKind.delete,
    );
  }

  void _reportUnrestoredRow(
    String kind,
    String id,
    Object error,
    StackTrace stackTrace,
  ) {
    _events.emit(
      SyncErrorEvent(
        SyncPhase.push,
        ParseException(
          'Dropped the stuck operations of "$kind" $id, but its row could '
          'not be restored from the server: $error',
          error,
          stackTrace,
        ),
        stackTrace,
      ),
    );
  }

  Timer? _autoTimer;

  /// Per-kind debounce timers driving [SyncConfig.pushOnEnqueue] auto-pushes.
  final Map<String, Timer> _enqueuePushTimers = {};

  /// Set of kinds with a pending debounced push.
  final Set<String> _pendingPushKinds = {};

  /// Stable closure registered as the database `onOutboxCommitted` hook.
  /// Stored as a field so it can be reliably compared at dispose time.
  late final OnOutboxCommittedCallback _enqueueHook = _scheduleEnqueuePush;

  /// Whether [dispose] has been called. Guards against scheduling a push
  /// after the engine is torn down.
  bool _disposed = false;

  /// Per-kind in-flight sync Futures.
  ///
  /// When [sync] is called for a specific kind that already has a run in
  /// progress, the caller joins the existing Future instead of launching
  /// a duplicate. Different kinds are always run concurrently and
  /// independently.
  final Map<String, Future<SyncRunResult>> _kindRunFutures = {};

  /// Current full-resync Future.
  ///
  /// When a full-resync is in progress all concurrent [sync] and [fullResync]
  /// callers share this Future and receive the same result.
  Future<SyncRunResult>? _fullResyncFuture;

  /// Start automatic periodic synchronization.
  ///
  /// [interval] — time between sync attempts (default: 5 minutes).
  void startAuto({Duration interval = const Duration(minutes: 5)}) {
    stopAuto();
    _autoTimer = Timer.periodic(interval, (_) {
      // Fire-and-forget: a run that fails has reported itself on [events].
      // Dropping the future turned every failed tick — each one, while the
      // device is offline — into an unhandled asynchronous error.
      unawaited(sync().catchError((Object _) => const SyncStats()));
    });
  }

  /// Stop automatic synchronization.
  void stopAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// Perform synchronization.
  ///
  /// [pushKinds] — if specified, push only these entity kinds.
  /// [pullKinds] — if specified, pull only these entity kinds.
  ///
  /// [kinds] is a legacy alias that applies the same filter to push and pull.
  /// Use [pushKinds]/[pullKinds] for explicit behavior.
  ///
  /// Concurrent callers for the **same** kind share an in-flight Future and
  /// receive the same result. Callers for **different** kinds run in parallel.
  /// A full-resync (manual or scheduled) is still fully serialised — all
  /// concurrent callers share a single [_fullResyncFuture].
  Future<SyncStats> sync({
    @Deprecated('Use pushKinds/pullKinds instead.') Set<String>? kinds,
    Set<String>? pushKinds,
    Set<String>? pullKinds,
  }) async {
    if (kinds != null && (pushKinds != null || pullKinds != null)) {
      throw ArgumentError(
        'Do not combine legacy "kinds" with "pushKinds"/"pullKinds".',
      );
    }

    final targetPushKinds = pushKinds ?? kinds;
    final targetPullKinds = pullKinds ?? kinds;

    return (await _runSync(
      pushKinds: targetPushKinds,
      pullKinds: targetPullKinds,
    )).stats;
  }

  /// Perform synchronization and return structured run metadata.
  Future<SyncRunResult> syncRun({
    @Deprecated('Use pushKinds/pullKinds instead.') Set<String>? kinds,
    Set<String>? pushKinds,
    Set<String>? pullKinds,
  }) async {
    if (kinds != null && (pushKinds != null || pullKinds != null)) {
      throw ArgumentError(
        'Do not combine legacy "kinds" with "pushKinds"/"pullKinds".',
      );
    }
    final targetPushKinds = pushKinds ?? kinds;
    final targetPullKinds = pullKinds ?? kinds;
    return _runSync(pushKinds: targetPushKinds, pullKinds: targetPullKinds);
  }

  /// Core dispatch: full-resync gate → per-kind incremental.
  Future<SyncRunResult> _runSync({
    Set<String>? pushKinds,
    Set<String>? pullKinds,
  }) async {
    _checkNotDisposed();
    await _ensureOutboxIndexes();

    // 1. If a full resync is already in flight, share it.
    if (_fullResyncFuture != null) return _fullResyncFuture!;

    // 2. If a full resync is due, trigger one (fullResync() manages its own
    //    single-flight _fullResyncFuture lock). One that was interrupted is
    //    due as well, whenever the last complete one was: the marker must not
    //    outlive the work, or the next scheduled resync would "continue" a
    //    resync that incremental pulls finished long ago instead of starting
    //    from zero.
    final lastFullResync = await _cursorService.getLastFullResync();
    final now = DateTime.now();
    final needsFullResync =
        lastFullResync == null ||
        now.difference(lastFullResync) >= _config.fullResyncInterval ||
        await _cursorService.isFullResyncInProgress();

    // The periodic full resync is a pull of everything. A caller that asked
    // for a push only — the debounced push after a local write, "Send now" —
    // must not get it as a side effect; the next sync that pulls will.
    final pushOnly = pullKinds != null && pullKinds.isEmpty;

    if (needsFullResync && !pushOnly) {
      // Delegate to fullResync() so _fullResyncFuture is properly set and all
      // concurrent callers hitting this branch share the same run.
      return _ensureFullResync(
        reason: FullResyncReason.scheduled,
        clearData: false,
        started: now,
      );
    }

    // A full resync may have started while the cursors were read. From here
    // to the registration of the per-kind runs nothing is awaited, so a full
    // resync that starts later finds them and waits.
    if (_fullResyncFuture != null) return _fullResyncFuture!;

    // 3. Per-kind incremental sync.
    final allKinds = (pushKinds ?? const <String>{}).union(
      pullKinds ?? const <String>{},
    );

    final targetKinds = allKinds.isEmpty ? _tables.keys.toSet() : allKinds;

    final futures = targetKinds.map((kind) {
      final pushForKind = (pushKinds == null || pushKinds.contains(kind))
          ? <String>{kind}
          : <String>{};
      final pullForKind = (pullKinds == null || pullKinds.contains(kind))
          ? <String>{kind}
          : <String>{};

      if (!_kindRunFutures.containsKey(kind)) {
        // Register a cleanup before storing so the entry is always removed
        // when the run finishes, even if it throws.
        late final Future<SyncRunResult> guarded;
        guarded =
            _doSyncRunForKind(
              kind: kind,
              pushKinds: pushForKind,
              pullKinds: pullForKind,
            ).whenComplete(() {
              // Only remove if the map still holds this exact future, avoiding a
              // race where a new run for the same kind has already been stored.
              if (identical(_kindRunFutures[kind], guarded)) {
                _kindRunFutures.remove(kind);
              }
            });
        _kindRunFutures[kind] = guarded;
      }
      return _kindRunFutures[kind]!;
    }).toList();

    final results = await Future.wait(futures);
    return _mergeResults(results);
  }

  /// Run push+pull for exactly one kind, without the full-resync gate.
  Future<SyncRunResult> _doSyncRunForKind({
    required String kind,
    required Set<String> pushKinds,
    required Set<String> pullKinds,
  }) async {
    final started = DateTime.now();
    var stats = const SyncStats();
    var pushStats = const PushStats();
    var pullStats = const PullStats(pulled: 0);

    SyncErrorInfo? firstError;
    final sub = events.listen((event) {
      if (firstError != null) return;
      if (event is SyncErrorEvent) {
        firstError = event.errorInfo;
      } else if (event is OperationFailedEvent) {
        firstError = event.errorInfo;
      }
    });

    var phase = SyncPhase.push;
    try {
      if (pushKinds.isNotEmpty) {
        _events.emit(const SyncStarted(SyncPhase.push));
        pushStats = await _pushService.pushAll(kinds: pushKinds);
        stats = stats.copyWith(
          pushed: pushStats.pushed,
          conflicts: pushStats.conflicts,
          conflictsResolved: pushStats.conflictsResolved,
          errors: pushStats.errors,
        );
      }

      if (pullKinds.isNotEmpty) {
        phase = SyncPhase.pull;
        _events.emit(const SyncStarted(SyncPhase.pull));
        final pulled = await _pullService.pullKinds(pullKinds);
        pullStats = PullStats(pulled: pulled);
        stats = stats.copyWith(pulled: pullStats.pulled);
      }

      _events.emit(
        SyncCompleted(
          DateTime.now().difference(started),
          DateTime.now(),
          stats: stats,
        ),
      );

      return SyncRunResult(
        push: pushStats,
        pull: pullStats,
        stats: stats,
        duration: DateTime.now().difference(started),
        kindsPushed: pushKinds,
        kindsPulled: pullKinds,
        stuckOpsCount: await _outboxService.countStuck(
          minTryCount: _config.maxOutboxTryCount,
        ),
        firstError: firstError,
      );
    } on SyncException catch (e, st) {
      _events.emit(SyncErrorEvent(phase, e, st));
      rethrow;
    } catch (e, st) {
      final exception = SyncOperationException(
        'Sync failed for kind=$kind',
        phase: 'sync',
        cause: e,
        stackTrace: st,
      );
      _events.emit(SyncErrorEvent(phase, exception, st));
      throw exception;
    } finally {
      await sub.cancel();
    }
  }

  /// Merge a list of per-kind [SyncRunResult]s into one aggregate result.
  SyncRunResult _mergeResults(List<SyncRunResult> results) {
    if (results.length == 1) return results.first;

    var pushed = 0;
    var conflicts = 0;
    var conflictsResolved = 0;
    var errors = 0;
    var pulled = 0;
    final kindsPushed = <String>{};
    final kindsPulled = <String>{};
    SyncErrorInfo? firstError;
    Duration duration = Duration.zero;

    for (final r in results) {
      pushed += r.push.pushed;
      conflicts += r.push.conflicts;
      conflictsResolved += r.push.conflictsResolved;
      errors += r.push.errors;
      pulled += r.pull.pulled;
      kindsPushed.addAll(r.kindsPushed);
      kindsPulled.addAll(r.kindsPulled);
      firstError ??= r.firstError;
      if (r.duration > duration) duration = r.duration;
    }

    final mergedPushStats = PushStats(
      pushed: pushed,
      conflicts: conflicts,
      conflictsResolved: conflictsResolved,
      errors: errors,
    );
    final mergedPullStats = PullStats(pulled: pulled);
    final mergedStats = SyncStats(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      conflictsResolved: conflictsResolved,
      errors: errors,
    );

    return SyncRunResult(
      push: mergedPushStats,
      pull: mergedPullStats,
      stats: mergedStats,
      duration: duration,
      kindsPushed: kindsPushed,
      kindsPulled: kindsPulled,
      stuckOpsCount: results.last.stuckOpsCount,
      firstError: firstError,
    );
  }

  /// Reactive count of pending operations (excluding stuck by default).
  Stream<int> watchPendingPushCount({
    Set<String>? kinds,
    bool includeStuck = false,
  }) => _outboxService.watchPendingCount(
    kinds: kinds,
    maxTryCountExclusive: includeStuck ? null : _config.maxOutboxTryCount,
  );

  /// Perform a full resynchronization.
  ///
  /// [clearData] — if true, clears local data before pull.
  /// Default is false — data remains, cursors are reset,
  /// then pull applies data on top (insertOrReplace).
  ///
  /// If a full resync is already in progress, concurrent callers will
  /// receive the same Future and share the result.
  Future<SyncStats> fullResync({bool clearData = false}) async {
    _checkNotDisposed();
    final run = await _ensureFullResync(
      reason: FullResyncReason.manual,
      clearData: clearData,
      started: DateTime.now(),
    );
    return run.stats;
  }

  /// A sync that is running when [dispose] is called finishes quietly;
  /// starting one afterwards is a mistake of the caller. It always failed —
  /// with "Cannot add new events after calling close", from the first event
  /// the run tried to report.
  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError(
        'This SyncEngine was disposed; create a new one to keep syncing.',
      );
    }
  }

  /// Internal single-flight wrapper around [_doFullResyncRun].
  ///
  /// Sets [_fullResyncFuture] so any concurrent caller (via [_runSync] or
  /// [fullResync]) joins the in-progress run rather than starting a new one.
  Future<SyncRunResult> _ensureFullResync({
    required FullResyncReason reason,
    required bool clearData,
    required DateTime started,
  }) {
    if (_fullResyncFuture != null) return _fullResyncFuture!;

    final created = _doFullResyncRun(
      reason: reason,
      clearData: clearData,
      started: started,
    );
    _fullResyncFuture = created;
    return created.whenComplete(() {
      if (identical(_fullResyncFuture, created)) {
        _fullResyncFuture = null;
      }
    });
  }

  Future<SyncRunResult> _doFullResyncRun({
    required FullResyncReason reason,
    required bool clearData,
    required DateTime started,
  }) async {
    var stats = const SyncStats();
    var pushStats = const PushStats();
    var pullStats = const PullStats(pulled: 0);

    SyncErrorInfo? firstError;
    final sub = events.listen((event) {
      if (firstError != null) return;
      if (event is SyncErrorEvent) {
        firstError = event.errorInfo;
      } else if (event is OperationFailedEvent) {
        firstError = event.errorInfo;
      }
    });

    var phase = SyncPhase.push;
    try {
      await _ensureOutboxIndexes();

      // Per-kind runs that are under way — the debounced push after a local
      // write, a sync of one kind — have taken operations from the outbox and
      // not acknowledged them yet. Pushing now would send those a second
      // time. No new one can start: `_runSync` joins this resync instead.
      while (_kindRunFutures.isNotEmpty) {
        await Future.wait([
          for (final run in _kindRunFutures.values.toList())
            run.then<void>((_) {}, onError: (Object _) {}),
        ]);
      }

      _events
        ..emit(FullResyncStarted(reason))
        ..emit(const SyncStarted(SyncPhase.push));

      pushStats = await _pushService.pushAll();
      stats = stats.copyWith(
        pushed: pushStats.pushed,
        conflicts: pushStats.conflicts,
        conflictsResolved: pushStats.conflictsResolved,
        errors: pushStats.errors,
      );

      // A full resync can be hundreds of requests. Every page it stores moves
      // that kind's cursor, so an interrupted one has not lost anything — as
      // long as the next attempt does not reset the cursors (and wipe the
      // tables) again. It used to: on a connection that drops now and then
      // the resync started over every time and might never finish.
      // `clearData` is an explicit request for a clean slate, so it always
      // starts over; call `fullResync()` without it to continue instead.
      final resuming =
          !clearData && await _cursorService.isFullResyncInProgress();
      if (!resuming) {
        await _cursorService.resetAll(_tables.keys.toSet());

        if (clearData) {
          final tableNames = _tables.values
              .map((t) => t.table.actualTableName)
              .toList();
          await _syncDb.clearSyncableTables(tableNames);
        }
        await _cursorService.setFullResyncInProgress(inProgress: true);
      }

      phase = SyncPhase.pull;
      _events.emit(const SyncStarted(SyncPhase.pull));
      final pulled = await _pullService.pullKinds(_tables.keys.toSet());
      pullStats = PullStats(pulled: pulled);
      stats = stats.copyWith(pulled: pullStats.pulled);

      await _cursorService.setLastFullResync(DateTime.now());
      await _cursorService.setFullResyncInProgress(inProgress: false);

      _events.emit(
        SyncCompleted(
          DateTime.now().difference(started),
          DateTime.now(),
          stats: stats,
        ),
      );

      return SyncRunResult(
        push: pushStats,
        pull: pullStats,
        stats: stats,
        duration: DateTime.now().difference(started),
        kindsPushed: _tables.keys.toSet(),
        kindsPulled: _tables.keys.toSet(),
        stuckOpsCount: await _outboxService.countStuck(
          minTryCount: _config.maxOutboxTryCount,
        ),
        firstError: firstError,
      );
    } on SyncException catch (e, st) {
      _events.emit(SyncErrorEvent(phase, e, st));
      rethrow;
    } catch (e, st) {
      final exception = SyncOperationException(
        'Full resync failed',
        phase: 'fullResync',
        cause: e,
        stackTrace: st,
      );
      _events.emit(SyncErrorEvent(phase, exception, st));
      throw exception;
    } finally {
      await sub.cancel();
    }
  }

  /// Register the post-commit outbox hook on the database mixin so that every
  /// successful enqueue made through [SyncEntityWriter] schedules a debounced
  /// per-kind auto-push when [SyncConfig.pushOnEnqueue] is enabled. If the
  /// flag is disabled the hook becomes a no-op early; we still install it so
  /// the config can be re-read at runtime via [SyncConfig.copyWith] if a
  /// future caller wants to flip it.
  void _registerEnqueuePushHook() {
    _syncDb.onOutboxCommitted = _enqueueHook;
  }

  /// Schedule (or reset) a debounced per-kind push.
  ///
  /// Same kind with rapid successive writes resets the timer (coalesces).
  /// Different kinds debounce independently and run in parallel via the
  /// per-kind sync locks.
  void _scheduleEnqueuePush(String kind) {
    if (!_config.pushOnEnqueue) return;
    if (_disposed) return;
    _pendingPushKinds.add(kind);
    _enqueuePushTimers[kind]?.cancel();
    _enqueuePushTimers[kind] = Timer(_config.enqueuePushDebounce, () {
      _enqueuePushTimers.remove(kind);
      _pendingPushKinds.remove(kind);
      if (_disposed) return;
      // Fire-and-forget; sync() reports its own errors via the events stream.
      // Restrict to push-only for this kind so we don't trigger an unwanted
      // pull cycle on every write. Empty pullKinds means "no kinds to pull".
      unawaited(
        sync(
          pushKinds: {kind},
          pullKinds: const <String>{},
        ).catchError((Object _) => const SyncStats()),
      );
    });
  }

  /// Cancel all pending debounced enqueue-pushes and clear pending state.
  void _cancelEnqueuePushTimers() {
    for (final timer in _enqueuePushTimers.values) {
      timer.cancel();
    }
    _enqueuePushTimers.clear();
    _pendingPushKinds.clear();
  }

  /// Release resources.
  ///
  /// IMPORTANT: Always call this method when done using the engine
  /// to prevent memory leaks from the event stream controller.
  void dispose() {
    _disposed = true;
    stopAuto();
    _cancelEnqueuePushTimers();
    // Detach the hook so a database that outlives the engine does not retain
    // a reference to the disposed engine's closure.
    if (identical(_syncDb.onOutboxCommitted, _enqueueHook)) {
      _syncDb.onOutboxCommitted = null;
    }
    _events.close();
  }
}
