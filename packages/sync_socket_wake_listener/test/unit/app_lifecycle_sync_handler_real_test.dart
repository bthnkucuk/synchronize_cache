// Tests the real AppLifecycleSyncHandler against the Flutter
// WidgetsBinding. Custom onResume/onPause callbacks are supplied so the
// SyncEngine is never invoked — full engine wiring is exercised by the
// integration tests in offline_first_sync_drift.
@TestOn('vm')
library;

import 'dart:ui' show AppLifecycleState;

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart'
    show SyncEngine, SyncStats;
import 'package:sync_socket_wake_listener/src/app_lifecycle_sync_handler.dart';

class _MockEngine extends Mock implements SyncEngine<GeneratedDatabase> {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late _MockEngine engine;

  setUp(() {
    engine = _MockEngine();
  });

  AppLifecycleSyncHandler<GeneratedDatabase> makeHandler({
    void Function()? onResume,
    void Function()? onPause,
  }) =>
      AppLifecycleSyncHandler<GeneratedDatabase>(
        engine: engine,
        onResume: onResume,
        onPause: onPause,
      );

  void deliver(AppLifecycleState state, AppLifecycleSyncHandler<dynamic> h) {
    h.didChangeAppLifecycleState(state);
  }

  group('lifecycle dispatch (custom callbacks)', () {
    test('resumed → onResume; pause/detach/inactive/hidden → onPause', () {
      var resumed = 0;
      var paused = 0;
      final h = makeHandler(
        onResume: () => resumed++,
        onPause: () => paused++,
      )..start();

      deliver(AppLifecycleState.resumed, h);
      deliver(AppLifecycleState.paused, h);
      deliver(AppLifecycleState.detached, h);
      deliver(AppLifecycleState.inactive, h);
      deliver(AppLifecycleState.hidden, h);

      expect(resumed, equals(1));
      expect(paused, equals(4));
      h.dispose();
    });

    test('start/dispose can be called multiple times safely', () {
      makeHandler(onResume: () {}, onPause: () {})
        ..start()
        ..start()
        ..dispose()
        ..dispose();
      // No exception means start/dispose tolerated double invocation.
    });

    test('callback errors propagate (Flutter binding catches them)', () {
      final h = makeHandler(
        onResume: () => throw StateError('boom'),
        onPause: () {},
      )..start();

      expect(
        () => deliver(AppLifecycleState.resumed, h),
        throwsStateError,
      );
      h.dispose();
    });
  });

  group('default lifecycle paths (no custom callbacks)', () {
    test('resumed calls engine.sync() then engine.startAuto(30 minutes)', () {
      when(() => engine.sync()).thenAnswer((_) async => const SyncStats());
      when(() => engine.startAuto(interval: any(named: 'interval')))
          .thenAnswer((_) {});

      final h = makeHandler()..start();
      deliver(AppLifecycleState.resumed, h);

      verify(() => engine.sync()).called(1);
      verify(
        () => engine.startAuto(interval: const Duration(minutes: 30)),
      ).called(1);
      h.dispose();
    });

    test('paused/detached/inactive/hidden each call engine.stopAuto()', () {
      when(() => engine.stopAuto()).thenAnswer((_) {});

      final h = makeHandler()..start();
      deliver(AppLifecycleState.paused, h);
      deliver(AppLifecycleState.detached, h);
      deliver(AppLifecycleState.inactive, h);
      deliver(AppLifecycleState.hidden, h);

      verify(() => engine.stopAuto()).called(4);
      h.dispose();
    });
  });
}
