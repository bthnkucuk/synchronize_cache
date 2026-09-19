import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// How the app is doing on the backend's live change feed.
enum LiveUpdatesState {
  /// The user switched live updates off.
  off,

  /// Trying to open the socket.
  connecting,

  /// Connected; a change on the server reaches this device in about a second.
  connected,

  /// The socket dropped and a retry is scheduled.
  reconnecting,
}

/// Opens a channel to `url`. Injected so tests can hand in a fake.
typedef ChannelFactory = WebSocketChannel Function(Uri url);

/// Listens to the backend's `GET /ws` feed and pulls when it says so.
///
/// Sync is a pull model: without this, a change made on device A reaches
/// device B at B's next timer tick — up to five minutes later. The feed
/// carries no data, only "kind X moved on"; the app answers with its normal
/// pull, so nothing about paging, tombstones or conflicts has to be
/// duplicated here.
///
/// Turning it off is a feature, not a fallback: with live updates off the
/// difference between "arrives instantly" and "arrives at the next sync"
/// becomes something you can watch.
class LiveUpdates extends ChangeNotifier {
  LiveUpdates({
    required Uri backendUrl,
    required this.onChanged,
    required this.log,
    ChannelFactory? connect,
    this.debounce = const Duration(milliseconds: 300),
  }) : _url = _feedUrl(backendUrl),
       _connect = connect ?? WebSocketChannel.connect;

  final Uri _url;

  /// Runs a pull of one kind after the server said it changed.
  final Future<void> Function(String kind) onChanged;

  /// Writes a line into the app's sync log.
  final void Function(String message) log;
  final ChannelFactory _connect;

  /// How long several `changed` frames are collected before one pull runs.
  ///
  /// The server cannot tell whose write it was, so this device is woken by
  /// its own pushes too; a burst of five writes must not cause five pulls.
  final Duration debounce;

  /// Backoff bounds for reconnects.
  static const _minRetry = Duration(seconds: 1);
  static const _maxRetry = Duration(seconds: 30);

  LiveUpdatesState _state = LiveUpdatesState.off;
  LiveUpdatesState get state => _state;

  /// How many apps the server said were listening, from the `hello` frame.
  int? _clients;
  int? get connectedClients => _clients;

  /// Whether the user wants live updates at all.
  bool get enabled => _enabled;
  bool _enabled = false;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _debounceTimer;
  Duration _retryIn = _minRetry;
  final Set<String> _pendingKinds = {};
  bool _disposed = false;

  /// A sentence for the sync panel.
  String get description => switch (_state) {
    LiveUpdatesState.off =>
      'Live updates: off — other devices reach you at the next sync',
    LiveUpdatesState.connecting => 'Live updates: on — connecting…',
    LiveUpdatesState.connected =>
      'Live updates: on — connected'
          '${_clients == null || _clients! < 2 ? '' : ', $_clients apps online'}',
    LiveUpdatesState.reconnecting => 'Live updates: on — reconnecting…',
  };

  /// Switches the feed on or off.
  Future<void> setEnabled({required bool value}) async {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      _retryIn = _minRetry;
      _open();
    } else {
      await _close();
      _setState(LiveUpdatesState.off);
      log('Live updates switched off');
    }
  }

  void _open() {
    if (_disposed || !_enabled) return;
    _retryTimer?.cancel();
    _setState(
      _state == LiveUpdatesState.reconnecting
          ? LiveUpdatesState.reconnecting
          : LiveUpdatesState.connecting,
    );

    try {
      final channel = _connect(_url);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onFrame,
        onDone: () => _scheduleRetry('the server closed the connection'),
        onError: (Object error) => _scheduleRetry('$error'),
        cancelOnError: true,
      );
    } on Object catch (error) {
      _scheduleRetry('$error');
    }
  }

  void _onFrame(dynamic frame) {
    if (frame is! String) return;

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(frame) as Map<String, dynamic>;
    } on Object {
      return;
    }

    switch (json['type']) {
      case 'hello':
        _clients = json['clients'] as int?;
        _retryIn = _minRetry;
        _setState(LiveUpdatesState.connected);
        log('Live updates connected (${_clients ?? 1} app(s) online)');
      case 'changed':
        final kind = json['kind'] as String?;
        if (kind == null || kind.isEmpty) return;
        // A frame can arrive before `hello` is processed on a slow tab.
        if (_state != LiveUpdatesState.connected) {
          _setState(LiveUpdatesState.connected);
        }
        log('Woken by server: $kind changed elsewhere');
        _pendingKinds.add(kind);
        _debounceTimer?.cancel();
        _debounceTimer = Timer(debounce, _pullPending);
    }
  }

  Future<void> _pullPending() async {
    final kinds = _pendingKinds.toList();
    _pendingKinds.clear();
    for (final kind in kinds) {
      try {
        await onChanged(kind);
      } on Object catch (error) {
        log('Pull after a server wake failed: $error');
      }
    }
  }

  void _scheduleRetry(String reason) {
    if (_disposed || !_enabled) return;
    _cancelChannel();
    _setState(LiveUpdatesState.reconnecting);
    log('Live updates lost ($reason); retrying in ${_retryIn.inSeconds}s');

    _retryTimer?.cancel();
    _retryTimer = Timer(_retryIn, _open);
    // Exponential backoff so a backend that is down does not turn into a
    // reconnect storm; reset by the next `hello`.
    _retryIn = Duration(
      milliseconds: math.min(
        _retryIn.inMilliseconds * 2,
        _maxRetry.inMilliseconds,
      ),
    );
  }

  void _cancelChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _close() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingKinds.clear();
    _clients = null;
    _cancelChannel();
  }

  void _setState(LiveUpdatesState state) {
    if (_state == state) return;
    _state = state;
    if (!_disposed) notifyListeners();
  }

  /// `http://host/` → `ws://host/ws` (and `https` → `wss`).
  static Uri _feedUrl(Uri backendUrl) => backendUrl.replace(
    scheme: backendUrl.scheme == 'https' ? 'wss' : 'ws',
    path: '/ws',
  );

  @override
  void dispose() {
    _disposed = true;
    _enabled = false;
    _close();
    super.dispose();
  }
}
