import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_advanced_frontend/services/live_updates.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A channel the test drives by hand, standing in for the backend's `/ws`.
class _FakeChannel implements WebSocketChannel {
  _FakeChannel();

  final _incoming = StreamController<dynamic>();
  final sent = <dynamic>[];
  bool closed = false;

  /// Delivers a frame. A closed socket silently swallows it, exactly as a
  /// real one would once the app has hung up.
  void emit(Object frame) {
    if (!_incoming.isClosed) _incoming.add(frame);
  }

  void drop() => _incoming.close();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  Future<void> get ready => Future.value();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeChannel _channel;

  @override
  void add(dynamic data) => _channel.sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closed = true;
    if (!_channel._incoming.isClosed) await _channel._incoming.close();
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> get done => Future.value();
}

void main() {
  late _FakeChannel channel;
  late List<String> pulled;
  late List<String> logged;
  late LiveUpdates live;

  LiveUpdates build() => LiveUpdates(
    backendUrl: Uri.parse('http://localhost:8080'),
    onChanged: (kind) async => pulled.add(kind),
    log: logged.add,
    connect: (_) => channel,
    debounce: const Duration(milliseconds: 10),
  );

  setUp(() {
    channel = _FakeChannel();
    pulled = [];
    logged = [];
    live = build();
  });

  tearDown(() => live.dispose());

  test('starts off and opens nothing until switched on', () {
    expect(live.state, LiveUpdatesState.off);
    expect(live.description, contains('off'));
  });

  test('a hello frame reports connected and counts the other apps', () async {
    await live.setEnabled(value: true);
    channel.emit(jsonEncode({'type': 'hello', 'clients': 2}));
    await Future<void>.delayed(Duration.zero);

    expect(live.state, LiveUpdatesState.connected);
    expect(live.connectedClients, 2);
    expect(live.description, contains('2 apps online'));
  });

  test('a changed frame pulls that kind and logs why', () async {
    await live.setEnabled(value: true);
    channel.emit(jsonEncode({'type': 'hello', 'clients': 1}));
    channel.emit(
      jsonEncode({
        'type': 'changed',
        'kind': 'todos',
        'id': 'todo-1',
        'at': '2026-09-20T10:00:00.000Z',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(pulled, ['todos']);
    expect(logged, contains('Woken by server: todos changed elsewhere'));
  });

  test('a burst of frames becomes one pull per kind', () async {
    await live.setEnabled(value: true);
    for (var i = 0; i < 5; i++) {
      channel.emit(
        jsonEncode({'type': 'changed', 'kind': 'todos', 'id': 'todo-$i'}),
      );
    }
    channel.emit(
      jsonEncode({'type': 'changed', 'kind': 'notes', 'id': 'note-1'}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(pulled, ['todos', 'notes']);
  });

  test('a frame that is not JSON, or has no kind, is ignored', () async {
    await live.setEnabled(value: true);
    channel
      ..emit('not json at all')
      ..emit(jsonEncode({'type': 'changed'}))
      ..emit(jsonEncode({'type': 'something-else', 'kind': 'todos'}));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(pulled, isEmpty);
  });

  test('a dropped socket goes to reconnecting, not to off', () async {
    await live.setEnabled(value: true);
    channel.emit(jsonEncode({'type': 'hello', 'clients': 1}));
    await Future<void>.delayed(Duration.zero);

    channel.drop();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(live.state, LiveUpdatesState.reconnecting);
    expect(live.enabled, isTrue);
    expect(logged.any((line) => line.contains('retrying in')), isTrue);
  });

  test('switching off closes the socket and stops reconnecting', () async {
    await live.setEnabled(value: true);
    await live.setEnabled(value: false);

    expect(live.state, LiveUpdatesState.off);
    expect(channel.closed, isTrue);

    channel.emit(jsonEncode({'type': 'changed', 'kind': 'todos'}));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(pulled, isEmpty);
  });
}
