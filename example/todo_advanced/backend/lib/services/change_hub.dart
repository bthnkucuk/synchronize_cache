import 'dart:convert';

/// Sends one JSON text frame to one connected client.
typedef FrameSink = void Function(String frame);

/// The live change feed behind `GET /ws`.
///
/// Sync is a pull model: an app only learns about other devices' writes when
/// its timer fires or the user presses "Get changes". This hub is the one
/// push in the system, and it deliberately pushes as little as possible —
/// *that* a kind changed, never the row itself. The client answers with a
/// normal pull, so the data still travels over the one code path that knows
/// about paging, tombstones and conflicts.
///
/// It is deliberately free of `WebSocketChannel`: a listener is just a
/// function that takes a frame, which keeps it unit-testable and keeps the
/// socket plumbing in `routes/ws.dart`.
class ChangeHub {
  final Map<int, FrameSink> _clients = {};
  int _nextToken = 0;

  /// How many apps are listening right now.
  int get clientCount => _clients.length;

  /// Registers [sink] and returns the token needed to [remove] it again.
  int add(FrameSink sink) {
    final token = _nextToken++;
    _clients[token] = sink;
    return token;
  }

  /// Unregisters a client. Safe to call twice (a socket can report both an
  /// error and completion).
  void remove(int token) => _clients.remove(token);

  /// The frame a client receives right after it connects.
  ///
  /// `clients` counts this client too, so the first tab sees `1` and the
  /// second sees `2` — enough for the app to say "another device is online".
  String helloFrame() => jsonEncode({'type': 'hello', 'clients': clientCount});

  /// Tells every connected app that one record changed.
  ///
  /// Wired to `SyncRepository.onChanged`, so it covers every write the
  /// server applies: client pushes, deletes and the `/simulate/*` endpoints.
  /// The sender gets the frame back as well — the app cannot tell whose
  /// write it was, so it debounces and pulls; a pull of its own change is
  /// harmless.
  void recordChanged({
    required String kind,
    required String id,
    required DateTime at,
  }) {
    broadcast(
      jsonEncode({
        'type': 'changed',
        'kind': kind,
        'id': id,
        'at': at.toUtc().toIso8601String(),
      }),
    );
  }

  /// Sends [frame] to every client, dropping the ones that have gone away.
  ///
  /// Writing to a socket that closed between the last read and now throws;
  /// one dead tab must not stop the others from being woken.
  void broadcast(String frame) {
    for (final entry in _clients.entries.toList()) {
      try {
        entry.value(frame);
      } on Object {
        _clients.remove(entry.key);
      }
    }
  }
}
