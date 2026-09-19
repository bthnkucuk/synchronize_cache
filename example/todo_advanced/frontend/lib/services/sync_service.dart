import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';

import '../database/database.dart';
import '../repositories/settings_repository.dart';
import '../search/app_search.dart';
import '../sync/note_sync.dart';
import 'auto_sync.dart';
import 'conflict_handler.dart';
import 'item_sync_state.dart';
import 'live_updates.dart';
import 'network_switch.dart';
import 'notes_conflict_policy.dart';
import 'sync_failure.dart';

/// Extracts user-friendly error message from exception.
String _sanitizeError(Object error) {
  final message = error.toString();
  if (message.contains('SocketException') ||
      message.contains('ClientException')) {
    return 'Network connection failed. Check your internet connection.';
  }
  if (message.contains('TimeoutException')) {
    return 'Request timed out. Server may be slow or unavailable.';
  }
  if (message.contains('HandshakeException')) {
    return 'Secure connection failed. Check server certificate.';
  }
  if (message.contains('FormatException')) {
    return 'Server returned invalid data.';
  }
  if (message.length > 100) {
    return 'Sync failed. Please try again.';
  }
  return message;
}

/// What the last run of a sync did.
@immutable
class LastSyncSummary {
  const LastSyncSummary({
    required this.what,
    required this.at,
    required this.stats,
    required this.stuckOps,
    this.firstError,
  });

  /// `Sync`, `Send now`, `Get changes`, `Full resync`, `Automatic sync`.
  final String what;
  final DateTime at;
  final SyncStats stats;
  final int stuckOps;
  final FailureReason? firstError;

  String get headline =>
      '$what — ${stats.pushed} sent, ${stats.pulled} received, '
      '${stats.conflicts} conflicts, ${stats.errors} errors';
}

/// Service for synchronizing todos and notes with the server.
///
/// Owns the [SyncEngine] and everything the sync panel drives: automatic
/// sync and its countdown, "send right after every change", the manual
/// buttons and the stuck list.
class SyncService extends ChangeNotifier {
  SyncService({
    required AppDatabase db,
    required String baseUrl,
    required ConflictHandler conflictHandler,
    required this.todoSync,
    SyncableTable<Note>? noteSync,
    this.settings,
    NetworkSwitch? networkSwitch,
    this.search,
    int maxRetries = 1,
    int maxPushRetries = 5,
  }) : _db = db,
       _conflictHandler = conflictHandler,
       networkSwitch = networkSwitch ?? NetworkSwitch() {
    _noteSync = noteSync ?? noteSyncTable(db);
    _transport = RestTransport(
      base: Uri.parse(baseUrl),
      // No auth for demo
      token: () async => '',
      client: SwitchableClient(this.networkSwitch),
      maxRetries: maxRetries,
      // An interactive app must answer "Send now" quickly, also when it
      // cannot get through. RestTransport's defaults (5 retries backing off
      // 1 s → 16 s) are meant for unattended background syncs: a tap without
      // a connection kept this screen "Syncing…" for about a minute — 31 s
      // for the push, then 31 s for the pull. Nothing is lost by giving up
      // sooner: the change stays queued and the next sync (or live update,
      // or tap) tries again.
      backoffMin: const Duration(milliseconds: 250),
      backoffMax: const Duration(seconds: 1),
      requestTimeout: const Duration(seconds: 10),
    );
    _maxPushRetries = maxPushRetries;

    _buildEngine();

    itemStates = ItemSyncStateStore(
      db: db,
      maxTryCount: const SyncConfig().maxOutboxTryCount,
      conflictedItems: () => conflictHandler.conflictedItems,
    );
    conflictHandler.addListener(itemStates.conflictsChanged);

    live = LiveUpdates(
      backendUrl: Uri.parse(baseUrl),
      onChanged: _pullBecauseServerSaidSo,
      log: (message) => _conflictHandler.logEvent(message),
    );
    live.addListener(notifyListeners);
  }

  final AppDatabase _db;
  final ConflictHandler _conflictHandler;

  /// The todo table registered with the engine.
  final SyncableTable<Todo> todoSync;

  /// Where this device's panel settings live; `null` in tests.
  final SettingsRepository? settings;

  /// The search index, re-armed after a sync brought new rows in.
  final AppSearch? search;

  /// The client-side "airplane mode" the Sync lab flips.
  final NetworkSwitch networkSwitch;

  late final SyncableTable<Note> _noteSync;
  late final RestTransport _transport;
  late final int _maxPushRetries;
  late SyncEngine<AppDatabase> _engine;
  StreamSubscription<SyncEvent>? _engineSubscription;

  /// Per-item sync states for the chips on every card.
  late final ItemSyncStateStore itemStates;

  /// The backend's live change feed.
  late final LiveUpdates live;

  StreamSubscription<int>? _pendingSubscription;
  StreamSubscription<int>? _stuckSubscription;

  /// Events are forwarded through our own stream: the engine is rebuilt when
  /// "send right after every change" is toggled, and a rebuild closes its
  /// stream underneath anybody listening to it.
  final _events = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  /// The retry budget after which an operation counts as stuck.
  int get maxOutboxTryCount => const SyncConfig().maxOutboxTryCount;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  String? _error;
  String? get error => _error;

  SyncStats? _lastStats;
  SyncStats? get lastStats => _lastStats;

  LastSyncSummary? _lastSync;
  LastSyncSummary? get lastSync => _lastSync;

  double _progress = 0;
  double get progress => _progress;

  bool get isSyncing => _status == SyncStatus.syncing;

  int _pendingCount = 0;

  /// Operations still waiting in the outbox, stuck ones included.
  int get pendingCount => _pendingCount;

  int _stuckCount = 0;

  /// Operations that ran out of retries.
  int get stuckCount => _stuckCount;

  AutoSyncSettings _autoSync = AutoSyncSettings.off;
  AutoSyncSettings get autoSync => _autoSync;

  DateTime? _autoSyncStartedAt;

  /// When the next automatic sync is due, or `null` when it is off.
  Duration? timeUntilNextAutoSync([DateTime? now]) => timeUntilNextSync(
    settings: _autoSync,
    startedAt: _autoSyncStartedAt,
    now: now ?? DateTime.now(),
  );

  bool _pushOnChange = false;

  /// Whether a write is pushed right away instead of waiting for a sync.
  bool get pushOnChange => _pushOnChange;

  /// How long the engine waits after a write before pushing, so a burst of
  /// edits becomes one request.
  Duration get pushDebounce => const SyncConfig().enqueuePushDebounce;

  ConflictHandler get conflictHandler => _conflictHandler;

  /// The kinds this app syncs.
  static const kinds = {'todos', 'notes'};

  // ---------------------------------------------------------------------
  // Engine lifecycle
  // ---------------------------------------------------------------------

  void _buildEngine() {
    _engine = SyncEngine<AppDatabase>(
      db: _db,
      transport: _transport,
      tables: [todoSync, _noteSync],
      config: SyncConfig(
        // Todos ask the user; see `tableConflictConfigs` for notes.
        conflictStrategy: ConflictStrategy.manual,
        pageSize: 500,
        maxPushRetries: _maxPushRetries,
        conflictResolver: _conflictHandler.resolve,
        pushOnEnqueue: _pushOnChange,
      ),
      tableConflictConfigs: {
        // Notes settle themselves. This is `manual` with an automatic
        // resolver rather than `ConflictStrategy.autoPreserve` because
        // `autoPreserve` cannot resolve a conflicting delete — see
        // `notes_conflict_policy.dart`.
        'notes': TableConflictConfig(
          strategy: ConflictStrategy.manual,
          resolver: (conflict) => resolveNoteConflict(
            conflict,
            log: (message) => _conflictHandler.logEvent(message),
          ),
        ),
      },
    );
    _engineSubscription = _engine.events.listen(_handleEvent);
  }

  /// Rebuilds the engine, which is the only way to change a [SyncConfig].
  Future<void> _rebuildEngine() async {
    // A sync in flight holds the old engine; let it finish first, otherwise
    // its completion lands on a disposed event stream.
    while (isSyncing) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final wasAuto = _autoSync.enabled;
    await _engineSubscription?.cancel();
    _engine
      ..stopAuto()
      ..dispose();
    _buildEngine();
    if (wasAuto) _applyAutoSync();
  }

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  /// Starts everything that talks to the outside world.
  ///
  /// Nothing in the constructor opens a socket, a timer or a database
  /// stream: a service that starts real work the moment it is built cannot
  /// be built inside a widget test, and hides the app's startup order. `main`
  /// calls this once, after the providers are in place.
  Future<void> start() async {
    _pendingSubscription ??= _db.watchOutboxCount().listen(
      (count) => _update(() => _pendingCount = count),
    );
    _stuckSubscription ??= _db
        .watchStuckOutboxCount(minTryCount: maxOutboxTryCount)
        .listen((count) => _update(() => _stuckCount = count));
    itemStates.start();
    await _loadSettings();
  }

  /// Restores this device's panel settings and starts what they ask for.
  Future<void> _loadSettings() async {
    final settings = this.settings;
    if (settings != null) {
      _autoSync = AutoSyncSettings(
        enabled: await settings.readBool(
          SettingKeys.autoSyncEnabled,
          orElse: false,
        ),
        interval: Duration(
          seconds: await settings.readInt(
            SettingKeys.autoSyncSeconds,
            orElse: 60,
          ),
        ),
      );
      _pushOnChange = await settings.readBool(
        SettingKeys.pushOnChange,
        orElse: false,
      );
      if (_pushOnChange) await _rebuildEngine();
      await live.setEnabled(
        value: await settings.readBool(SettingKeys.liveUpdates, orElse: true),
      );
    } else {
      await live.setEnabled(value: true);
    }
    _applyAutoSync();
    notifyListeners();
  }

  Future<void> setAutoSync(AutoSyncSettings value) async {
    _autoSync = value;
    _applyAutoSync();
    await settings?.writeBool(
      SettingKeys.autoSyncEnabled,
      value: value.enabled,
    );
    await settings?.writeInt(
      SettingKeys.autoSyncSeconds,
      value.interval.inSeconds,
    );
    _conflictHandler.logEvent(
      value.enabled
          ? 'Automatic sync on, ${describeInterval(value.interval)}'
          : 'Automatic sync off — changes stay on this device until you '
                'press Send now',
    );
    notifyListeners();
  }

  void _applyAutoSync() {
    _engine.stopAuto();
    if (_autoSync.enabled) {
      _engine.startAuto(interval: _autoSync.interval);
      _autoSyncStartedAt = DateTime.now();
    } else {
      _autoSyncStartedAt = null;
    }
  }

  Future<void> setPushOnChange({required bool value}) async {
    if (_pushOnChange == value) return;
    _pushOnChange = value;
    await _rebuildEngine();
    await settings?.writeBool(SettingKeys.pushOnChange, value: value);
    _conflictHandler.logEvent(
      value
          ? 'Every change is now sent about '
                '${pushDebounce.inMilliseconds} ms after you make it'
          : 'Changes now wait for a sync',
    );
    notifyListeners();
  }

  Future<void> setLiveUpdates({required bool value}) async {
    await live.setEnabled(value: value);
    await settings?.writeBool(SettingKeys.liveUpdates, value: value);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // The buttons
  // ---------------------------------------------------------------------

  /// Push and pull.
  Future<SyncStats> sync() => _run('Sync');

  /// Push only: deliver what is queued here.
  Future<SyncStats> sendNow() => _run('Send now', pullKinds: const {});

  /// Pull only: fetch what other devices did.
  Future<SyncStats> getChanges() => _run('Get changes', pushKinds: const {});

  /// Forgets the cursors and reads everything again.
  Future<SyncStats> fullResync({bool clearData = false}) async {
    _begin();
    try {
      final stats = await _engine.fullResync(clearData: clearData);
      _finish('Full resync', stats, null, 0);
      await search?.refresh();
      return stats;
    } on Object catch (e) {
      _fail(e);
      rethrow;
    }
  }

  Future<SyncStats> _run(
    String what, {
    Set<String>? pushKinds,
    Set<String>? pullKinds,
  }) async {
    _begin();
    try {
      final result = await _engine.syncRun(
        pushKinds: pushKinds,
        pullKinds: pullKinds,
      );
      _finish(what, result.stats, result.firstError, result.stuckOpsCount);
      await search?.refresh();
      return result.stats;
    } on Object catch (e) {
      _fail(e);
      rethrow;
    }
  }

  void _begin() {
    _status = SyncStatus.syncing;
    _error = null;
    _progress = 0;
    notifyListeners();
  }

  void _finish(
    String what,
    SyncStats stats,
    SyncErrorInfo? firstError,
    int stuckOps,
  ) {
    _lastStats = stats;
    _lastSync = LastSyncSummary(
      what: what,
      at: DateTime.now(),
      stats: stats,
      stuckOps: stuckOps,
      firstError: firstError == null ? null : describeFailure(firstError),
    );
    _status = SyncStatus.idle;
    _progress = 1;
    if (_autoSync.enabled) _autoSyncStartedAt ??= DateTime.now();
    _conflictHandler.logEvent(_lastSync!.headline);
    notifyListeners();
  }

  void _fail(Object e) {
    _error = _sanitizeError(e);
    _status = SyncStatus.error;
    _conflictHandler.logEvent(
      'Sync failed: $_error',
      level: SyncLogLevel.error,
    );
    notifyListeners();
  }

  /// Starts automatic sync at the given interval.
  ///
  /// The panel goes through [setAutoSync], which also remembers the choice;
  /// this is the plain version for tests and for code that just wants the
  /// timer running.
  void startAuto({Duration interval = const Duration(minutes: 5)}) {
    _autoSync = AutoSyncSettings(enabled: true, interval: interval);
    _applyAutoSync();
    _conflictHandler.logEvent('Auto-sync started (interval: $interval)');
    notifyListeners();
  }

  /// Stops automatic sync.
  void stopAuto() {
    _autoSync = _autoSync.copyWith(enabled: false);
    _applyAutoSync();
    _conflictHandler.logEvent('Auto-sync stopped');
    notifyListeners();
  }

  /// Gets pending operation count.
  ///
  /// [pendingCount] is the same number kept live for the UI; this reads it
  /// on demand.
  Future<int> getPendingCount() async {
    final ops = await _db.takeOutbox();
    return ops.length;
  }

  /// The operations that ran out of retries.
  Future<List<Op>> stuckOperations() => _engine.getStuckOperations();

  /// Puts stuck operations back in the queue with a fresh budget.
  Future<void> retryStuck() async {
    await _engine.retryStuckOperations();
    _conflictHandler.logEvent('Stuck changes put back in the queue');
    notifyListeners();
  }

  /// Throws stuck operations away. The local rows keep whatever they have.
  Future<void> discardStuck() async {
    await _engine.dropStuckOperations();
    _conflictHandler.logEvent(
      'Stuck changes discarded',
      level: SyncLogLevel.warning,
    );
    notifyListeners();
  }

  /// Checks server health.
  Future<bool> checkHealth() async {
    try {
      return await _transport.health();
    } on Object {
      return false;
    }
  }

  /// Triggers server-side simulation endpoint.
  Future<void> triggerServerSimulation(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final uri = Uri.parse('${_transport.base}$endpoint');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode >= 400) {
        throw Exception('Server returned ${response.statusCode}');
      }

      _conflictHandler.logEvent(
        'Server simulation triggered: $endpoint',
        level: SyncLogLevel.warning,
      );
    } on Object catch (e) {
      _conflictHandler.logEvent(
        'Simulation failed: $e',
        level: SyncLogLevel.error,
      );
      rethrow;
    }
  }

  /// A pull of one kind, because the server said that kind changed.
  Future<void> _pullBecauseServerSaidSo(String kind) async {
    if (isSyncing) return;
    await _run('Live update', pushKinds: const {}, pullKinds: {kind});
  }

  void _handleEvent(SyncEvent event) {
    _events.add(event);

    switch (event) {
      case SyncStarted(:final phase):
        _status = SyncStatus.syncing;
        _progress = 0;
        _conflictHandler.logEvent('Sync $phase started...');
        notifyListeners();

      case SyncProgress(:final done, :final total):
        if (total > 0) {
          _progress = done / total;
          notifyListeners();
        }

      case SyncCompleted(:final stats):
        _lastStats = stats;
        _status = SyncStatus.idle;
        _progress = 1;
        notifyListeners();

      case SyncErrorEvent(:final error):
        _error = _sanitizeError(error);
        _status = SyncStatus.error;
        notifyListeners();

      case OperationPushedEvent(
        :final kind,
        :final entityId,
        :final operationType,
      ):
        _conflictHandler.logEvent('$operationType $kind: $entityId');

      case OperationFailedEvent(:final opId, :final errorInfo, :final kind):
        // The precise reason, while it is still in memory; the outbox only
        // keeps the message as a string.
        itemStates.recordFailure(opId, errorInfo);
        _conflictHandler.logEvent(
          '$kind: ${describeFailure(errorInfo).words}',
          level: SyncLogLevel.warning,
        );

      case CacheUpdateEvent(:final kind, :final upserts, :final deletes):
        _conflictHandler.logEvent(
          'Cache: $kind - $upserts upserts, $deletes deletes',
        );

      case ConflictDetectedEvent(:final conflict):
        _conflictHandler.logEvent(
          'Conflict: ${conflict.kind}/${conflict.entityId}',
          level: SyncLogLevel.warning,
        );

      case ConflictResolvedEvent(:final conflict, :final resolution):
        _conflictHandler.logEvent(
          'Resolved: ${conflict.kind}/${conflict.entityId} -> '
          '${resolution.runtimeType}',
        );

      default:
        if (kDebugMode) {
          debugPrint('SyncEvent: $event');
        }
    }
  }

  void _update(VoidCallback change) {
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _pendingSubscription?.cancel();
    _stuckSubscription?.cancel();
    _engineSubscription?.cancel();
    _conflictHandler.removeListener(itemStates.conflictsChanged);
    live
      ..removeListener(notifyListeners)
      ..dispose();
    itemStates.dispose();
    _events.close();
    _engine.dispose();
    super.dispose();
  }
}

/// Sync status states.
enum SyncStatus {
  /// Not syncing, ready for sync.
  idle,

  /// Currently syncing.
  syncing,

  /// Last sync failed.
  error,
}
