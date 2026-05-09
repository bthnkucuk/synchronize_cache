// ignore_for_file: comment_references

import 'dart:ui' show AppLifecycleState;

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart' show SyncEngine;

/// Pauses and resumes sync engine auto-sync in response to app lifecycle events.
///
/// Register with [WidgetsBinding] via [start] and release via [dispose].
///
/// - App resumes → calls [onResume] (default: `engine.startAuto`).
/// - App pauses / detaches → calls [onPause] (default: `engine.stopAuto`).
class AppLifecycleSyncHandler<DB extends GeneratedDatabase> with WidgetsBindingObserver {
  AppLifecycleSyncHandler({
    required this.engine,
    void Function()? onResume,
    void Function()? onPause,
  }) : _onResume = onResume,
       _onPause = onPause;

  /// The sync engine whose automatic sync is controlled.
  final SyncEngine<DB> engine;

  final void Function()? _onResume;
  final void Function()? _onPause;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Register this handler with [WidgetsBinding].
  void start() => WidgetsBinding.instance.addObserver(this);

  /// Unregister from [WidgetsBinding].
  void dispose() => WidgetsBinding.instance.removeObserver(this);

  // ---------------------------------------------------------------------------
  // WidgetsBindingObserver
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_onResume != null) {
          _onResume();
        } else {
          // Trigger an immediate catch-up sync; library decides full vs incremental.
          engine.sync();
          // Restart auto-sync; noop if already running. The interval is
          // bumped to 30 minutes because the periodic timer is no longer
          // the primary push channel — `pushOnEnqueue` handles per-kind
          // event-driven pushes and wake/resume/reconnect handlers drive
          // pulls. The timer remains as a paranoia net for missed wake
          // events or dropped reconnect signals.
          engine.startAuto(interval: const Duration(minutes: 30));
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_onPause != null) {
          _onPause();
        } else {
          engine.stopAuto();
        }
    }
  }
}
