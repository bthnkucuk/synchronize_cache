import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
import 'package:todo_advanced_backend/services/change_hub.dart';

/// `GET /ws` — the live change feed.
///
/// A client connects and listens; it never has to send anything. Two frames
/// exist, both JSON text:
///
/// ```json
/// {"type": "hello",   "clients": 2}
/// {"type": "changed", "kind": "todos", "id": "…", "at": "2026-09-19T…Z"}
/// ```
///
/// A `changed` frame is a *hint*, not data: it says "this kind moved on, ask
/// for it". The client answers with its normal pull, which is what makes a
/// second app instance update within a second instead of at its next timer
/// tick. Nothing breaks without this socket — the app just waits longer.
Future<Response> onRequest(RequestContext context) async {
  final hub = context.read<ChangeHub>();

  final handler = webSocketHandler(
    (channel, protocol) {
      final token = hub.add(channel.sink.add);
      channel.sink.add(hub.helloFrame());

      // Nothing is expected from the client, but the stream still has to be
      // listened to: without a subscription the channel never notices that
      // the socket closed and the hub would keep a dead client forever.
      channel.stream.listen(
        (_) {},
        onDone: () => hub.remove(token),
        onError: (Object _) => hub.remove(token),
        cancelOnError: true,
      );
    },
    // Round-trip keep-alive: a tab that was closed without a proper close
    // frame (or a laptop that went to sleep) is noticed within a minute.
    pingInterval: const Duration(seconds: 30),
  );

  return handler(context);
}
