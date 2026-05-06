import 'dart:async';

import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
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

class PullStats {
  const PullStats({required this.pulled});

  final int pulled;
}

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
class SyncEngine<DB extends GeneratedDatabase> {
  SyncEngine({
    required DB db,
    required TransportAdapter transport,
    required List<SyncableTable<dynamic>> tables,
    SyncConfig config = const SyncConfig(),
    Map<String, TableConflictConfig>? tableConflictConfigs,
  }) : _db = db,
       _transport = transport,
       _tables = _buildTablesMap(tables),
       _config = config,
       _tableConflictConfigs = tableConflictConfigs ?? {} {
    if (db is! SyncDatabaseMixin) {
      throw ArgumentError(
        'Database must implement SyncDatabaseMixin. '
        'Add "with SyncDatabaseMixin" to your database class.',
      );
    }

    _initServices();
  }

  final DB _db;
  final TransportAdapter _transport;
  final Map<String, SyncableTable<dynamic>> _tables;
  final SyncConfig _config;
  final Map<String, TableConflictConfig> _tableConflictConfigs;

  final _events = StreamController<SyncEvent>.broadcast();

  late final OutboxService _outboxService;
  late final CursorService _cursorService;
  late final ConflictService<DB> _conflictService;
  late final PushService _pushService;
  late final PullService<DB> _pullService;

  SyncDatabaseMixin get _syncDb => _db as SyncDatabaseMixin;

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

  void _initServices() {
    _outboxService = OutboxService(_syncDb);
    _cursorService = CursorService(_syncDb);
    _conflictService = ConflictService<DB>(
      db: _db,
      transport: _transport,
      tables: _tables,
      config: _config,
      tableConflictConfigs: _tableConflictConfigs,
      events: _events,
    );
    _pushService = PushService(
      outbox: _outboxService,
      transport: _transport,
      conflictService: _conflictService,
      config: _config,
      events: _events,
    );
    _pullService = PullService<DB>(
      db: _db,
      transport: _transport,
      tables: _tables,
      cursorService: _cursorService,
      config: _config,
      events: _events,
    );
  }

  /// Stream of sync events for monitoring progress and errors.
  Stream<SyncEvent> get events => _events.stream;

  /// Service for managing outbox operations.
  OutboxService get outbox => _outboxService;

  /// Service for managing sync cursors.
  CursorService get cursors => _cursorService;

  /// Return operations that reached stuck threshold.
  Future<List<Op>> getStuckOperations({Set<String>? kinds}) {
    return _outboxService.getStuck(
      minTryCount: _config.maxOutboxTryCount,
      kinds: kinds,
    );
  }

  /// Reset retry counters for stuck operations.
  Future<void> retryStuckOperations({Set<String>? kinds}) async {
    final stuck = await getStuckOperations(kinds: kinds);
    await _outboxService.resetTryCount(stuck.map((op) => op.opId));
  }

  /// Drop stuck operations from outbox.
  Future<void> dropStuckOperations({Set<String>? kinds}) async {
    final stuck = await getStuckOperations(kinds: kinds);
    await _outboxService.ack(stuck.map((op) => op.opId));
  }

  Timer? _autoTimer;

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
    _autoTimer = Timer.periodic(interval, (_) => sync());
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
    // 1. If a full resync is already in flight, share it.
    if (_fullResyncFuture != null) return _fullResyncFuture!;

    // 2. If a full resync is due, trigger one (fullResync() manages its own
    //    single-flight _fullResyncFuture lock).
    final lastFullResync = await _cursorService.getLastFullResync();
    final now = DateTime.now();
    final needsFullResync =
        lastFullResync == null ||
        now.difference(lastFullResync) >= _config.fullResyncInterval;

    if (needsFullResync) {
      // Delegate to fullResync() so _fullResyncFuture is properly set and all
      // concurrent callers hitting this branch share the same run.
      return _ensureFullResync(
        reason: FullResyncReason.scheduled,
        clearData: false,
        started: now,
      );
    }

    // 3. Per-kind incremental sync.
    final allKinds =
        (pushKinds ?? const <String>{}).union(pullKinds ?? const <String>{});

    final targetKinds =
        allKinds.isEmpty ? _tables.keys.toSet() : allKinds;

    final futures = targetKinds.map((kind) {
      final pushForKind =
          (pushKinds == null || pushKinds.contains(kind))
              ? <String>{kind}
              : <String>{};
      final pullForKind =
          (pullKinds == null || pullKinds.contains(kind))
              ? <String>{kind}
              : <String>{};

      if (!_kindRunFutures.containsKey(kind)) {
        // Register a cleanup before storing so the entry is always removed
        // when the run finishes, even if it throws.
        late final Future<SyncRunResult> guarded;
        guarded = _doSyncRunForKind(
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

    try {
      if (pushKinds.isNotEmpty) {
        _events.add(SyncStarted(SyncPhase.push));
        pushStats = await _pushService.pushAll(kinds: pushKinds);
        stats = stats.copyWith(
          pushed: pushStats.pushed,
          conflicts: pushStats.conflicts,
          conflictsResolved: pushStats.conflictsResolved,
          errors: pushStats.errors,
        );
      }

      if (pullKinds.isNotEmpty) {
        _events.add(SyncStarted(SyncPhase.pull));
        final pulled = await _pullService.pullKinds(pullKinds);
        pullStats = PullStats(pulled: pulled);
        stats = stats.copyWith(pulled: pullStats.pulled);
      }

      _events.add(
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
      _events.add(SyncErrorEvent(SyncPhase.pull, e, st));
      rethrow;
    } catch (e, st) {
      final exception = SyncOperationException(
        'Sync failed for kind=$kind',
        phase: 'sync',
        cause: e,
        stackTrace: st,
      );
      _events.add(SyncErrorEvent(SyncPhase.pull, exception, st));
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
  }) {
    return _outboxService.watchPendingCount(
      kinds: kinds,
      maxTryCountExclusive: includeStuck ? null : _config.maxOutboxTryCount,
    );
  }

  /// Perform a full resynchronization.
  ///
  /// [clearData] — if true, clears local data before pull.
  /// Default is false — data remains, cursors are reset,
  /// then pull applies data on top (insertOrReplace).
  ///
  /// If a full resync is already in progress, concurrent callers will
  /// receive the same Future and share the result.
  Future<SyncStats> fullResync({bool clearData = false}) async {
    final run = await _ensureFullResync(
      reason: FullResyncReason.manual,
      clearData: clearData,
      started: DateTime.now(),
    );
    return run.stats;
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

    try {
      _events
        ..add(FullResyncStarted(reason))
        ..add(SyncStarted(SyncPhase.push));

      pushStats = await _pushService.pushAll();
      stats = stats.copyWith(
        pushed: pushStats.pushed,
        conflicts: pushStats.conflicts,
        conflictsResolved: pushStats.conflictsResolved,
        errors: pushStats.errors,
      );

      await _cursorService.resetAll(_tables.keys.toSet());

      if (clearData) {
        final tableNames =
            _tables.values.map((t) => t.table.actualTableName).toList();
        await _syncDb.clearSyncableTables(tableNames);
      }

      _events.add(SyncStarted(SyncPhase.pull));
      final pulled = await _pullService.pullKinds(_tables.keys.toSet());
      pullStats = PullStats(pulled: pulled);
      stats = stats.copyWith(pulled: pullStats.pulled);

      await _cursorService.setLastFullResync(DateTime.now());

      _events.add(
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
      _events.add(SyncErrorEvent(SyncPhase.pull, e, st));
      rethrow;
    } catch (e, st) {
      final exception = SyncOperationException(
        'Full resync failed',
        phase: 'fullResync',
        cause: e,
        stackTrace: st,
      );
      _events.add(SyncErrorEvent(SyncPhase.pull, exception, st));
      throw exception;
    } finally {
      await sub.cancel();
    }
  }

  /// Release resources.
  ///
  /// IMPORTANT: Always call this method when done using the engine
  /// to prevent memory leaks from the event stream controller.
  void dispose() {
    stopAuto();
    _events.close();
  }
}
