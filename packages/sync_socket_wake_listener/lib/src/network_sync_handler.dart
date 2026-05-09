import 'dart:async' show StreamSubscription;

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart' show SyncEngine;

/// Triggers a full sync whenever the device regains network connectivity.
///
/// Listens to `Connectivity.onConnectivityChanged` and calls [onReconnect]
/// (default: full `engine.sync()`) whenever any non-none connectivity type
/// appears after a period with no connectivity.
///
/// Call [start] to begin listening and [dispose] to release resources.
class NetworkSyncHandler<DB extends GeneratedDatabase> {
  NetworkSyncHandler({
    required this.engine,
    Connectivity? connectivity,
    Future<void> Function()? onReconnect,
  }) : _connectivity = connectivity ?? Connectivity(),
       _onReconnect = onReconnect;

  /// The sync engine to trigger on reconnect.
  final SyncEngine<DB> engine;

  final Connectivity _connectivity;
  final Future<void> Function()? _onReconnect;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _wasOffline = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Start listening for connectivity changes.
  void start() {
    _subscription = _connectivity.onConnectivityChanged.listen(_onChanged);
  }

  /// Stop listening and release resources.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _onChanged(List<ConnectivityResult> results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);

    if (!isOnline) {
      _wasOffline = true;
      return;
    }

    if (_wasOffline) {
      _wasOffline = false;
      final fn = _onReconnect;
      if (fn != null) {
        fn();
      } else {
        engine.sync();
      }
    }
  }
}
