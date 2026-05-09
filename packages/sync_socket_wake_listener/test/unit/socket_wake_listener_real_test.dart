// Tests the real SocketWakeListener at the boundaries we can exercise
// without a live socket.io server: start/dispose lifecycle, idempotency,
// auth-state subscription routing, and provider hookup.
//
// Auth=true paths trigger an actual `io.io(...)` call which immediately tries
// to open a WebSocket. Under TestWidgetsFlutterBinding all HTTP traffic is
// mocked and that connect attempt rejects with `Unsupported operation:
// Mocked response`. We guard those tests with `runZonedGuarded` so the
// expected connection failure does not crash the test — our assertions
// fire *before* that async error surfaces. Actual socket connect /
// `sync:wake` event flow is covered by the payload-parsing replica tests.
@TestOn('vm')
library;

import 'dart:async';

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart'
    show SyncEngine;
import 'package:sync_socket_wake_listener/src/socket_wake_listener.dart';

class _MockEngine extends Mock implements SyncEngine<GeneratedDatabase> {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockEngine engine;
  late StreamController<bool> authState;
  late int urlCalls;
  late int pathCalls;
  late int authProviderCalls;

  setUp(() {
    engine = _MockEngine();
    authState = StreamController<bool>.broadcast();
    urlCalls = 0;
    pathCalls = 0;
    authProviderCalls = 0;
  });

  tearDown(() async {
    await authState.close();
  });

  SocketWakeListener<GeneratedDatabase> makeListener() =>
      SocketWakeListener<GeneratedDatabase>(
        urlProvider: () async {
          urlCalls++;
          return 'http://localhost:1';
        },
        pathProvider: () async {
          pathCalls++;
          return '/realtime.io';
        },
        authProvider: () async {
          authProviderCalls++;
          return const {'Authorization': 'Bearer x'};
        },
        authStateChanges: authState.stream,
        engine: engine,
        onWake: (_) async {},
      );

  // Wraps a test body so the async WebSocket failure produced by socket.io
  // under the mocked HTTP binding is not treated as a test failure. The
  // assertions inside [body] fire synchronously after our `_flush()` calls,
  // well before the WebSocket failure surfaces.
  Future<void> guarded(Future<void> Function() body) {
    final completer = Completer<void>();
    runZonedGuarded(() async {
      try {
        await body();
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    }, (_, __) {
      // Swallow async errors from the socket.io connect attempt.
    });
    return completer.future;
  }

  test('start() then dispose() completes without throwing', () async {
    final listener = makeListener();
    await listener.start();
    await listener.dispose();
  });

  test('dispose() before start() is a no-op', () async {
    await makeListener().dispose();
  });

  test('signing out (auth=false) does not trigger socket setup', () async {
    final listener = makeListener();
    await listener.start();

    authState.add(false);
    await _flush();

    expect(urlCalls, equals(0));
    expect(pathCalls, equals(0));
    expect(authProviderCalls, equals(0));

    await listener.dispose();
  });

  test('events delivered after dispose() are ignored', () async {
    final listener = makeListener();
    await listener.start();
    await listener.dispose();

    authState.add(true);
    await _flush();

    expect(urlCalls, equals(0));
    expect(pathCalls, equals(0));
  });

  test('signing in (auth=true) triggers socket setup; providers are called',
      () async {
    await guarded(() async {
      final listener = makeListener();
      await listener.start();

      authState.add(true);
      await _flush();

      expect(urlCalls, equals(1));
      expect(pathCalls, equals(1));

      await listener.dispose();
    });
  });

  test('start() is idempotent — calling twice subscribes once', () async {
    await guarded(() async {
      final listener = makeListener();
      await listener.start();
      await listener.start();

      authState.add(true);
      await _flush();

      // urlProvider is invoked once per socket setup. With two start()
      // calls but a single auth event, exactly one setup should run.
      expect(urlCalls, equals(1));
      expect(pathCalls, equals(1));

      await listener.dispose();
    });
  });

  test('auth=true → false flow tears down without re-running setup',
      () async {
    await guarded(() async {
      final listener = makeListener();
      await listener.start();

      authState.add(true);
      await _flush();
      final urlAfterSignIn = urlCalls;

      authState.add(false);
      await _flush();

      expect(urlCalls, equals(urlAfterSignIn),
          reason: 'sign-out must not provoke a new setup');

      await listener.dispose();
    });
  });

  test('start() after dispose() re-arms the auth subscription', () async {
    await guarded(() async {
      final listener = makeListener();
      await listener.start();
      await listener.dispose();

      await listener.start();

      authState.add(true);
      await _flush();

      expect(urlCalls, equals(1));

      await listener.dispose();
    });
  });

  test('multiple sign-in events trigger setup each time', () async {
    await guarded(() async {
      final listener = makeListener();
      await listener.start();

      authState.add(true);
      await _flush();
      authState.add(true);
      await _flush();

      // Each sign-in event re-runs setup — the listener tears down the
      // previous socket and creates a fresh one.
      expect(urlCalls, equals(2));
      expect(pathCalls, equals(2));

      await listener.dispose();
    });
  });
}

Future<void> _flush() async {
  // Drain microtasks + a few event-loop ticks so chained async work inside
  // the listener has a chance to settle before assertions.
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
