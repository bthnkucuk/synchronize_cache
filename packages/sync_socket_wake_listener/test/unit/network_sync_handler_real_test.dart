// Tests the real NetworkSyncHandler against an injected Connectivity mock.
@TestOn('vm')
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart'
    show SyncEngine, SyncStats;
import 'package:sync_socket_wake_listener/src/network_sync_handler.dart';

class _MockConnectivity extends Mock implements Connectivity {}

class _MockEngine extends Mock implements SyncEngine<GeneratedDatabase> {}

void main() {
  late StreamController<List<ConnectivityResult>> controller;
  late _MockConnectivity connectivity;
  late _MockEngine engine;

  setUp(() {
    controller = StreamController<List<ConnectivityResult>>.broadcast();
    connectivity = _MockConnectivity();
    engine = _MockEngine();
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  Future<void> emit(List<ConnectivityResult> results) async {
    controller.add(results);
    // Allow the listener to drain the event.
    await Future<void>.delayed(Duration.zero);
  }

  NetworkSyncHandler<GeneratedDatabase> makeHandler({
    Future<void> Function()? onReconnect,
  }) =>
      NetworkSyncHandler<GeneratedDatabase>(
        engine: engine,
        connectivity: connectivity,
        onReconnect: onReconnect,
      );

  test('does not call onReconnect on initial online event', () async {
    var calls = 0;
    final handler = makeHandler(onReconnect: () async => calls++)..start();

    await emit(const [ConnectivityResult.wifi]);

    expect(calls, equals(0));
    handler.dispose();
  });

  test('calls onReconnect once after offline → online transition', () async {
    var calls = 0;
    final handler = makeHandler(onReconnect: () async => calls++)..start();

    await emit(const [ConnectivityResult.none]);
    await emit(const [ConnectivityResult.wifi]);

    expect(calls, equals(1));
    handler.dispose();
  });

  test('subsequent online events without an offline drop do not re-trigger',
      () async {
    var calls = 0;
    final handler = makeHandler(onReconnect: () async => calls++)..start();

    await emit(const [ConnectivityResult.none]);
    await emit(const [ConnectivityResult.wifi]);
    await emit(const [ConnectivityResult.mobile]);

    expect(calls, equals(1));
    handler.dispose();
  });

  test('handles multiple offline/online cycles', () async {
    var calls = 0;
    final handler = makeHandler(onReconnect: () async => calls++)..start();

    for (var i = 0; i < 3; i++) {
      await emit(const [ConnectivityResult.none]);
      await emit(const [ConnectivityResult.wifi]);
    }

    expect(calls, equals(3));
    handler.dispose();
  });

  test('multiple online types in a single event are still treated as online',
      () async {
    var calls = 0;
    final handler = makeHandler(onReconnect: () async => calls++)..start();

    await emit(const [ConnectivityResult.none]);
    await emit(const [ConnectivityResult.wifi, ConnectivityResult.vpn]);

    expect(calls, equals(1));
    handler.dispose();
  });

  test('events delivered after dispose() are ignored', () async {
    var calls = 0;
    final handler = makeHandler(onReconnect: () async => calls++)..start();

    await emit(const [ConnectivityResult.none]);
    handler.dispose();
    await emit(const [ConnectivityResult.wifi]);

    expect(calls, equals(0));
  });

  test('dispose() is safe to call before start()', () {
    final handler = makeHandler();
    expect(handler.dispose, returnsNormally);
  });

  test('a none-only emission does not flip wasOffline back to online',
      () async {
    var calls = 0;
    final handler = makeHandler(onReconnect: () async => calls++)..start();

    await emit(const [ConnectivityResult.none]);
    await emit(const [ConnectivityResult.none]);
    await emit(const [ConnectivityResult.none]);

    expect(calls, equals(0));
    handler.dispose();
  });

  test('falls back to engine.sync() when no onReconnect is provided',
      () async {
    when(() => engine.sync()).thenAnswer((_) async => const SyncStats());

    final handler = makeHandler()..start();

    await emit(const [ConnectivityResult.none]);
    await emit(const [ConnectivityResult.wifi]);

    verify(() => engine.sync()).called(1);
    handler.dispose();
  });
}
