import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

import '../models/todo.dart';
import 'item_sync_state.dart' show ItemKey;

/// Handles conflict resolution for sync operations.
///
/// When a conflict is detected:
/// 1. Stores the conflict for later resolution
/// 2. Notifies listeners (UI shows conflict dialog)
/// 3. User chooses resolution: local, server, or merged
/// 4. Resolution is applied and sync continues
///
/// This is the *manual* strategy, which todos use. Notes take the automatic
/// route in `notes_conflict_policy.dart` — the contrast is the point.
class ConflictHandler extends ChangeNotifier {
  ConflictHandler();

  /// Queue of pending conflicts to resolve.
  final List<ConflictInfo> _pendingConflicts = [];

  /// Currently displayed conflict (if any).
  ConflictInfo? _currentConflict;
  ConflictInfo? get currentConflict => _currentConflict;

  /// Completer for the current conflict resolution.
  Completer<ConflictResolution>? _resolutionCompleter;

  /// Whether there are pending conflicts.
  bool get hasConflicts =>
      _pendingConflicts.isNotEmpty || _currentConflict != null;

  /// Number of pending conflicts.
  int get conflictCount =>
      _pendingConflicts.length + (_currentConflict != null ? 1 : 0);

  /// Every `(kind, id)` waiting for a decision, for the per-item chips.
  Set<ItemKey> get conflictedItems => {
    for (final info in [..._pendingConflicts, ?_currentConflict])
      (info.conflict.kind, info.conflict.entityId),
  };

  /// Sync event log for debugging.
  final List<SyncLogEntry> _log = [];
  List<SyncLogEntry> get log => List.unmodifiable(_log);

  /// Clears the sync log.
  void clearLog() {
    _log.clear();
    notifyListeners();
  }

  /// Maximum log entries to keep in memory.
  static const _maxLogEntries = 100;

  /// Logs a sync event.
  void logEvent(String message, {SyncLogLevel level = SyncLogLevel.info}) {
    _log.add(
      SyncLogEntry(timestamp: DateTime.now(), message: message, level: level),
    );
    // Prevent unbounded memory growth
    while (_log.length > _maxLogEntries) {
      _log.removeAt(0);
    }
    notifyListeners();
  }

  /// The conflict resolver function to pass to SyncConfig.
  ///
  /// This is called by the sync engine when a conflict is detected.
  Future<ConflictResolution> resolve(Conflict conflict) async {
    // A queued *delete* carries no payload, so `localData` is empty — that is
    // the only way a resolver can tell a delete from an edit (`Conflict` has
    // no operation type). The two need different questions: an edit is "whose
    // text wins", a delete is "does it go or does it come back".
    final isDelete = conflict.localData.isEmpty;

    final Todo serverTodo;
    final Todo localTodo;
    try {
      serverTodo = Todo.fromJson(conflict.serverData.cast<String, dynamic>());
      localTodo = isDelete
          ? serverTodo
          : Todo.fromJson(conflict.localData.cast<String, dynamic>());
    } on Object catch (e) {
      logEvent('Failed to parse conflict data: $e', level: SyncLogLevel.error);
      // Defer resolution on parse error - will retry on next sync
      return const DeferResolution();
    }

    final info = ConflictInfo(
      conflict: conflict,
      localTodo: localTodo,
      serverTodo: serverTodo,
      isDelete: isDelete,
    );

    logEvent(
      isDelete
          ? 'You deleted "${serverTodo.title}" while another device was '
                'still editing it'
          : 'Conflict detected for "${info.localTodo.title}"',
      level: SyncLogLevel.warning,
    );

    // Add to queue
    _pendingConflicts.add(info);
    notifyListeners();

    // If no conflict is currently being resolved, start resolution
    if (_currentConflict == null) {
      return _resolveNext();
    }

    // Wait for this conflict to be resolved
    return _waitForResolution(info);
  }

  Future<ConflictResolution> _resolveNext() async {
    if (_pendingConflicts.isEmpty) {
      return const AcceptServer();
    }

    _currentConflict = _pendingConflicts.removeAt(0);
    _resolutionCompleter = Completer<ConflictResolution>();
    notifyListeners();

    return _resolutionCompleter!.future;
  }

  /// Timeout for user to resolve a conflict before auto-deferring.
  static const _resolutionTimeout = Duration(minutes: 5);

  Future<ConflictResolution> _waitForResolution(ConflictInfo info) async {
    final startTime = DateTime.now();

    // Wait until this conflict becomes current and gets resolved
    while (_pendingConflicts.contains(info) || _currentConflict == info) {
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Check for timeout to prevent infinite waiting
      if (DateTime.now().difference(startTime) > _resolutionTimeout) {
        logEvent(
          'Conflict resolution timed out for "${info.localTodo.title}"',
          level: SyncLogLevel.warning,
        );
        // Auto-defer on timeout - will retry on next sync
        return const DeferResolution();
      }
    }

    // Resolution was applied
    return info.resolution ?? const AcceptServer();
  }

  /// Keeps what this device wants.
  ///
  /// For an edit that force-pushes the local version; for a delete it
  /// force-deletes, which is why the library's force path has to accept a
  /// `DeleteOp` — and it does.
  void resolveWithLocal() {
    if (_currentConflict == null || _resolutionCompleter == null) return;

    final conflict = _currentConflict!;
    conflict.resolution = const AcceptClient();

    logEvent(
      conflict.isDelete
          ? 'Deleted anyway: "${conflict.serverTodo.title}"'
          : 'Resolved with local: "${conflict.localTodo.title}"',
    );

    _completeResolution(const AcceptClient());
  }

  /// Takes the other device's version.
  ///
  /// For a delete this brings the row back: the queued delete is dropped and
  /// the server's record is written locally.
  void resolveWithServer() {
    if (_currentConflict == null || _resolutionCompleter == null) return;

    final conflict = _currentConflict!;
    conflict.resolution = const AcceptServer();

    logEvent(
      conflict.isDelete
          ? 'Kept the other device\'s version of '
                '"${conflict.serverTodo.title}"; the delete was dropped'
          : 'Resolved with server: "${conflict.serverTodo.title}"',
    );

    _completeResolution(const AcceptServer());
  }

  /// Resolves the current conflict with a merged version.
  void resolveWithMerged(Todo mergedTodo) {
    if (_currentConflict == null || _resolutionCompleter == null) return;

    final conflict = _currentConflict!;
    // A merged *delete* is meaningless, and the engine cannot push one: it
    // only force-pushes merged data for upserts. Fall back to keeping the
    // other device's version rather than producing an operation that would
    // sit in the outbox forever.
    if (conflict.isDelete) {
      resolveWithServer();
      return;
    }

    final mergedData = mergedTodo.toJson();
    final resolution = AcceptMerged(mergedData.cast<String, Object?>());
    conflict.resolution = resolution;

    logEvent('Resolved with merge: "${mergedTodo.title}"');

    _completeResolution(resolution);
  }

  void _completeResolution(ConflictResolution result) {
    final completer = _resolutionCompleter;
    _currentConflict = null;
    _resolutionCompleter = null;

    completer?.complete(result);
    notifyListeners();

    // Process next conflict if any
    if (_pendingConflicts.isNotEmpty) {
      _resolveNext();
    }
  }

  /// Skips the current conflict (uses server version).
  void skipConflict() {
    resolveWithServer();
  }

  @override
  void dispose() {
    // Complete any pending resolution to prevent hanging futures
    if (_resolutionCompleter != null && !_resolutionCompleter!.isCompleted) {
      _resolutionCompleter!.complete(const DeferResolution());
    }
    _pendingConflicts.clear();
    _currentConflict = null;
    super.dispose();
  }
}

/// Information about a sync conflict.
class ConflictInfo {
  ConflictInfo({
    required this.conflict,
    required this.localTodo,
    required this.serverTodo,
    this.isDelete = false,
  });

  final Conflict conflict;

  /// The version this device wanted to send.
  ///
  /// For a delete ([isDelete]) there is no local *version* — the user asked
  /// for the row to be gone — so this mirrors [serverTodo] and only the
  /// title is meaningful.
  final Todo localTodo;

  /// What the server holds, from the `current` record in its `409`.
  final Todo serverTodo;

  /// Whether the queued operation was a delete rather than an edit.
  final bool isDelete;

  ConflictResolution? resolution;

  /// Gets the fields that differ between local and server.
  ///
  /// Empty for a delete: nothing was edited here, the row was removed.
  List<String> get conflictingFields {
    if (isDelete) return const [];
    final fields = <String>[];

    if (localTodo.title != serverTodo.title) fields.add('title');
    if (localTodo.description != serverTodo.description) {
      fields.add('description');
    }
    if (localTodo.completed != serverTodo.completed) fields.add('completed');
    if (localTodo.priority != serverTodo.priority) fields.add('priority');
    if (localTodo.dueDate != serverTodo.dueDate) fields.add('dueDate');

    return fields;
  }
}

/// Log entry for sync events.
class SyncLogEntry {
  SyncLogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });

  final DateTime timestamp;
  final String message;
  final SyncLogLevel level;
}

/// Log level for sync events.
enum SyncLogLevel { info, warning, error }
