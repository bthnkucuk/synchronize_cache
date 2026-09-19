import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:todo_advanced_backend/services/change_hub.dart';

import '../../routes/ws.dart' as ws;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late ChangeHub hub;
  late _MockRequestContext context;

  setUp(() {
    hub = ChangeHub();
    context = _MockRequestContext();
    when(() => context.read<ChangeHub>()).thenReturn(hub);
  });

  // The upgrade itself needs a real socket, so it is covered by the HTTP
  // smoke test rather than here. What a unit test can pin down is that the
  // route refuses anything that is not a WebSocket handshake instead of
  // leaving a half-registered client behind in the hub.
  test('a plain GET is not upgraded and registers no client', () async {
    when(() => context.request)
        .thenReturn(Request.get(Uri.parse('http://localhost/ws')));

    final response = await ws.onRequest(context);

    expect(response.statusCode, isNot(101));
    expect(hub.clientCount, 0);
  });
}
