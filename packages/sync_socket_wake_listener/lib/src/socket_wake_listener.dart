import 'dart:async' show StreamSubscription, Timer;
import 'dart:ui' show AppLifecycleState;

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart' show SyncEngine;
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Provides the socket.io server base URL.
typedef SocketUrlProvider = Future<String> Function();

/// Provides the socket.io path (e.g. `/realtime.io`).
typedef SocketPathProvider = Future<String> Function();

/// Provides the auth payload sent on socket handshake.
///
/// The server's connect handler reads:
///   `auth.get("X-Bundle-Identifier")` and `auth.get("Authorization")`.
/// Include both keys in the returned map.
typedef SocketAuthProvider = Future<Map<String, Object?>> Function();

/// Hook called for non-fatal info / debug log lines.
typedef SocketLog = void Function(String message);

/// Hook called when an exception is caught inside the listener.
typedef SocketErrorHandler = void Function(
    Object error, StackTrace stackTrace, [String? context]);

/// Listens for `sync:wake` socket.io events and triggers a targeted pull sync.
///
/// The server emits `sync:wake` with `{"kind": "<bare-kind-name>"}` to the
/// room `uid:{user_id}` whenever a server-side write occurs that the client
/// should pull.  This listener wires that signal to `engine.sync(pullKinds: {kind})`.
///
/// Lifecycle is managed automatically via [WidgetsBindingObserver]:
/// - App resumes → reconnect socket.
/// - App pauses/detaches → disconnect socket.
///
/// Auth-state changes (sign-in / sign-out) are handled by [authStateChanges]:
/// - `true` → open socket.
/// - `false` → close socket.
///
/// Config-driven: every external dependency is injected via constructor
/// callbacks so the class is reusable across apps and easy to fake in tests.
class SocketWakeListener<DB extends GeneratedDatabase> with WidgetsBindingObserver {
  SocketWakeListener({
    required this.urlProvider,
    required this.pathProvider,
    required this.authProvider,
    required this.authStateChanges,
    required this.engine,
    required this.onWake,
    this.reconnectInterval = const Duration(minutes: 1),
    this.reconnectionDelay = const Duration(seconds: 2),
    this.reconnectionDelayMax = const Duration(seconds: 20),
    this.transports = const ['websocket'],
    SocketLog? logger,
    SocketErrorHandler? onError,
  }) : _log = logger ?? _noopLog,
       _onError = onError ?? _noopError;

  /// Resolves the socket.io server base URL each time the socket is set up.
  final SocketUrlProvider urlProvider;

  /// Resolves the socket.io path (e.g. `/realtime.io`).
  final SocketPathProvider pathProvider;

  /// Resolves the auth payload sent during the socket handshake.
  final SocketAuthProvider authProvider;

  /// Stream that emits `true` when an authenticated user is present and
  /// `false` when the user signs out. The listener opens / tears down the
  /// socket in lock-step with this stream.
  final Stream<bool> authStateChanges;

  /// The sync engine to drive when a wake signal arrives.
  final SyncEngine<DB> engine;

  /// Called with the bare kind name every time `sync:wake` fires.
  ///
  /// Default implementation: `engine.sync(pullKinds: {kind})`.  Override to
  /// add throttling, logging, or error handling around the sync call.
  final Future<void> Function(String kind) onWake;

  /// How often to retry connecting after a transient drop.
  final Duration reconnectInterval;

  /// Initial socket.io reconnection delay.
  final Duration reconnectionDelay;

  /// Maximum socket.io reconnection delay.
  final Duration reconnectionDelayMax;

  /// Allowed socket.io transports (defaults to `['websocket']`).
  final List<String> transports;

  final SocketLog _log;
  final SocketErrorHandler _onError;

  io.Socket? _socket;
  StreamSubscription<bool>? _authSubscription;
  Timer? _reconnectionTimer;
  bool _started = false;

  static void _noopLog(String msg) {}
  static void _noopError(Object err, StackTrace st, [String? ctx]) {}

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Start the listener.  Safe to call multiple times.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await _setupAuthSubscription();
  }

  /// Dispose the listener and release all resources.
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _stop();
    _started = false;
  }

  // ---------------------------------------------------------------------------
  // WidgetsBindingObserver
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _reconnect();
      case AppLifecycleState.detached:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _disconnectSocket();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _setupAuthSubscription() async {
    _authSubscription = authStateChanges.listen((isAuthenticated) async {
      _clearTimer();
      await _clearSocket();
      if (isAuthenticated) {
        await _setupSocket();
        _reconnectionTimer = Timer.periodic(reconnectInterval, (_) async {
          if (_socket?.connected ?? false) return;
          await _setupSocket();
        });
      }
    });
  }

  Future<void> _setupSocket() async {
    await _clearSocket();

    final serverUrl = await urlProvider();
    final realtimePath = await pathProvider();

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(transports)
          .setPath(realtimePath)
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(reconnectionDelay.inMilliseconds)
          .setReconnectionDelayMax(reconnectionDelayMax.inMilliseconds)
          .setAuthFn((callback) async {
            final auth = await authProvider();
            callback(auth);
          })
          .build(),
    );

    _socket!.onConnect((_) {
      _log('SocketWakeListener: connected');
      // Catch up changes that may have happened while disconnected.
      _catchUpSync();
    });
    _socket!.onDisconnect((_) => _log('SocketWakeListener: disconnected'));
    _socket!.onConnectError((e) => _log('SocketWakeListener: connect error $e'));

    _socket!.on('sync:wake', (data) {
      try {
        final kind = (data as Map<dynamic, dynamic>?)?['kind'] as String?;
        if (kind == null || kind.isEmpty) {
          _log('SocketWakeListener: sync:wake missing kind field — $data');
          return;
        }
        _log('SocketWakeListener: sync:wake kind=$kind');
        onWake(kind).catchError((Object e, StackTrace st) {
          _onError(e, st, 'SocketWakeListener onWake kind=$kind');
        });
      } catch (e, st) {
        _onError(e, st, 'SocketWakeListener sync:wake handler data=$data');
      }
    });
  }

  Future<void> _catchUpSync() async {
    try {
      await engine.sync();
    } catch (e, st) {
      _onError(e, st, 'SocketWakeListener onConnect catch-up sync');
    }
  }

  Future<void> _clearSocket() async {
    _socket?.dispose();
    _socket = null;
  }

  void _clearTimer() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
  }

  void _disconnectSocket() {
    _socket?.disconnect();
  }

  void _reconnect() {
    if (!(_socket?.connected ?? false)) {
      _setupSocket().catchError(
        (Object e, StackTrace st) => _onError(e, st, 'SocketWakeListener _reconnect'),
      );
    }
  }

  Future<void> _stop() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    _clearTimer();
    await _clearSocket();
  }
}
