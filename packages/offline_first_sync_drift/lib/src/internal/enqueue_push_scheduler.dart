import 'dart:async';

import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/sync_database.dart';

/// Debounced per-kind pushes after local writes
/// ([SyncConfig.pushOnEnqueue]).
///
/// Installs itself as the database's post-commit outbox hook, so every
/// successful enqueue made through `SyncEntityWriter` schedules a push of
/// that kind. Rapid successive writes of one kind reset its timer (they
/// coalesce); different kinds debounce independently.
final class EnqueuePushScheduler {
  EnqueuePushScheduler({
    required this._db,
    required this._config,
    required this._push,
  });

  final SyncDatabaseMixin _db;
  final SyncConfig _config;

  /// Starts a push of one kind; fire-and-forget.
  final void Function(String kind) _push;

  final Map<String, Timer> _timers = {};
  bool _disposed = false;

  /// Stable closure registered as the hook, so that [dispose] can tell
  /// whether the database still points at this scheduler.
  late final OnOutboxCommittedCallback _hook = _schedule;

  /// Installs the hook. With `pushOnEnqueue` off it is a no-op, but still
  /// installed.
  void attach() => _db.onOutboxCommitted = _hook;

  void _schedule(String kind) {
    if (!_config.pushOnEnqueue || _disposed) return;
    _timers[kind]?.cancel();
    _timers[kind] = Timer(_config.enqueuePushDebounce, () {
      _timers.remove(kind);
      if (_disposed) return;
      _push(kind);
    });
  }

  /// Cancels every pending push and detaches the hook, so that a database
  /// which outlives the engine does not keep a reference to it.
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (identical(_db.onOutboxCommitted, _hook)) {
      _db.onOutboxCommitted = null;
    }
  }
}
