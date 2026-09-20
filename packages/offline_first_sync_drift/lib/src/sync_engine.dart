import 'dart:async';

import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/internal/enqueue_push_scheduler.dart';
import 'package:offline_first_sync_drift/src/internal/event_emitter.dart';
import 'package:offline_first_sync_drift/src/op.dart';
import 'package:offline_first_sync_drift/src/services/conflict_service.dart';
import 'package:offline_first_sync_drift/src/services/cursor_service.dart';
import 'package:offline_first_sync_drift/src/services/outbox_service.dart';
import 'package:offline_first_sync_drift/src/services/pull_service.dart';
import 'package:offline_first_sync_drift/src/services/push_service.dart';
import 'package:offline_first_sync_drift/src/services/stuck_operations_service.dart';
import 'package:offline_first_sync_drift/src/sync_database.dart';
import 'package:offline_first_sync_drift/src/sync_error.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/sync_run_result.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

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

    _enqueuePush.attach();
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

  late final StuckOperationsService<DB> _stuckOperations =
      StuckOperationsService<DB>(
        db: _db,
        outbox: _outboxService,
        transport: _transport,
        tables: _tables,
        config: _config,
        events: _events,
      );
  late final EnqueuePushScheduler _enqueuePush = EnqueuePushScheduler(
    db: _syncDb,
    config: _config,
    push: _pushAfterEnqueue,
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
  Future<List<Op>> getStuckOperations({Set<String>? kinds}) =>
      _stuckOperations.getStuck(kinds: kinds);

  /// Reset retry counters for stuck operations.
  Future<void> retryStuckOperations({Set<String>? kinds}) =>
      _stuckOperations.retry(kinds: kinds);

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
  Future<void> dropStuckOperations({Set<String>? kinds}) =>
      _stuckOperations.drop(kinds: kinds);

  Timer? _autoTimer;

  /// Whether [dispose] has been called.
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
    return SyncRunResult.merge(results);
  }

  /// Run push+pull for exactly one kind, without the full-resync gate.
  Future<SyncRunResult> _doSyncRunForKind({
    required String kind,
    required Set<String> pushKinds,
    required Set<String> pullKinds,
  }) => _reportedRun(
    started: DateTime.now(),
    kindsPushed: pushKinds,
    kindsPulled: pullKinds,
    failure: (e, st) => SyncOperationException(
      'Sync failed for kind=$kind',
      phase: 'sync',
      cause: e,
      stackTrace: st,
    ),
    steps: (run) async {
      if (pushKinds.isNotEmpty) await run.push(pushKinds);
      if (pullKinds.isNotEmpty) await run.pull(pullKinds);
    },
  );

  /// Runs [steps] and reports them the way every run is reported: the first
  /// error seen on [events] while it ran, [SyncCompleted] with the totals, a
  /// [SyncErrorEvent] naming the phase that failed, and a [SyncRunResult].
  Future<SyncRunResult> _reportedRun({
    required DateTime started,
    required Set<String> kindsPushed,
    required Set<String> kindsPulled,
    required SyncOperationException Function(Object error, StackTrace st)
    failure,
    required Future<void> Function(_Run run) steps,
  }) async {
    final run = _Run(_pushService, _pullService, _events);

    SyncErrorInfo? firstError;
    final sub = events.listen((event) {
      if (firstError != null) return;
      if (event is SyncErrorEvent) {
        firstError = event.errorInfo;
      } else if (event is OperationFailedEvent) {
        firstError = event.errorInfo;
      }
    });

    try {
      await steps(run);

      final stats = run.stats;
      _events.emit(
        SyncCompleted(
          DateTime.now().difference(started),
          DateTime.now(),
          stats: stats,
        ),
      );

      return SyncRunResult(
        push: run.pushStats,
        pull: PullStats(pulled: run.pulled),
        stats: stats,
        duration: DateTime.now().difference(started),
        kindsPushed: kindsPushed,
        kindsPulled: kindsPulled,
        stuckOpsCount: await _outboxService.countStuck(
          minTryCount: _config.maxOutboxTryCount,
        ),
        firstError: firstError,
      );
    } on SyncException catch (e, st) {
      _events.emit(SyncErrorEvent(run.phase, e, st));
      rethrow;
    } catch (e, st) {
      final exception = failure(e, st);
      _events.emit(SyncErrorEvent(run.phase, exception, st));
      throw exception;
    } finally {
      await sub.cancel();
    }
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
  }) {
    final allKinds = _tables.keys.toSet();
    return _reportedRun(
      started: started,
      kindsPushed: allKinds,
      kindsPulled: allKinds,
      failure: (e, st) => SyncOperationException(
        'Full resync failed',
        phase: 'fullResync',
        cause: e,
        stackTrace: st,
      ),
      steps: (run) async {
        await _ensureOutboxIndexes();

        // Per-kind runs that are under way — the debounced push after a
        // local write, a sync of one kind — have taken operations from the
        // outbox and not acknowledged them yet. Pushing now would send those
        // a second time. No new one can start: `_runSync` joins this resync
        // instead.
        while (_kindRunFutures.isNotEmpty) {
          await Future.wait([
            for (final kindRun in _kindRunFutures.values.toList())
              kindRun.then<void>((_) {}, onError: (Object _) {}),
          ]);
        }

        _events.emit(FullResyncStarted(reason));
        await run.push(null);

        // A full resync can be hundreds of requests. Every page it stores
        // moves that kind's cursor, so an interrupted one has not lost
        // anything — as long as the next attempt does not reset the cursors
        // (and wipe the tables) again. It used to: on a connection that
        // drops now and then the resync started over every time and might
        // never finish. `clearData` is an explicit request for a clean
        // slate, so it always starts over; call `fullResync()` without it to
        // continue instead.
        final resuming =
            !clearData && await _cursorService.isFullResyncInProgress();
        if (!resuming) {
          await _cursorService.resetAll(allKinds);

          if (clearData) {
            final tableNames = _tables.values
                .map((t) => t.table.actualTableName)
                .toList();
            await _syncDb.clearSyncableTables(tableNames);
          }
          await _cursorService.setFullResyncInProgress(inProgress: true);
        }

        await run.pull(allKinds);

        await _cursorService.setLastFullResync(DateTime.now());
        await _cursorService.setFullResyncInProgress(inProgress: false);
      },
    );
  }

  /// What [SyncConfig.pushOnEnqueue] does after a local write.
  void _pushAfterEnqueue(String kind) {
    // Fire-and-forget; sync() reports its own errors via the events stream.
    // Restrict to push-only for this kind so we don't trigger an unwanted
    // pull cycle on every write. Empty pullKinds means "no kinds to pull".
    unawaited(
      sync(
        pushKinds: {kind},
        pullKinds: const <String>{},
      ).catchError((Object _) => const SyncStats()),
    );
  }

  /// Release resources.
  ///
  /// IMPORTANT: Always call this method when done using the engine
  /// to prevent memory leaks from the event stream controller.
  void dispose() {
    _disposed = true;
    stopAuto();
    _enqueuePush.dispose();
    _events.close();
  }
}

/// The progress of one run: which phase it is in and what it has moved so
/// far — what [SyncEngine._reportedRun] needs to report it, also when it
/// fails half way.
class _Run {
  _Run(this._pushService, this._pullService, this._events);

  final PushService _pushService;
  final PullService<GeneratedDatabase> _pullService;
  final StreamController<SyncEvent> _events;

  var phase = SyncPhase.push;
  var pushStats = const PushStats();
  var pulled = 0;

  SyncStats get stats => SyncStats(
    pushed: pushStats.pushed,
    pulled: pulled,
    conflicts: pushStats.conflicts,
    conflictsResolved: pushStats.conflictsResolved,
    errors: pushStats.errors,
  );

  /// Pushes the queued operations of [kinds]; `null` means every kind.
  Future<void> push(Set<String>? kinds) async {
    _events.emit(const SyncStarted(SyncPhase.push));
    pushStats = await _pushService.pushAll(kinds: kinds);
  }

  Future<void> pull(Set<String> kinds) async {
    phase = SyncPhase.pull;
    _events.emit(const SyncStarted(SyncPhase.pull));
    pulled = await _pullService.pullKinds(kinds);
  }
}
