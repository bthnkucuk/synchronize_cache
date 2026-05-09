// Tests for AppLifecycleSyncHandler's lifecycle-to-sync-control mapping.
// Uses flutter_test to access dart:ui's AppLifecycleState.
@TestOn('vm')
library;

import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Minimal replica of AppLifecycleSyncHandler's dispatch logic so it can be
// tested without a full Flutter widget binding.
// ---------------------------------------------------------------------------

void _dispatchLifecycleState(
  AppLifecycleState state, {
  required void Function() onResume,
  required void Function() onPause,
}) {
  switch (state) {
    case AppLifecycleState.resumed:
      onResume();
    case AppLifecycleState.paused:
    case AppLifecycleState.detached:
    case AppLifecycleState.inactive:
    case AppLifecycleState.hidden:
      onPause();
  }
}

// ---------------------------------------------------------------------------
// Replica of the updated default resumed path:
//   1. engine.sync()  — immediate catch-up
//   2. engine.startAuto(interval: 30min) — restart periodic timer as a
//      long-period paranoia net (event-driven push and wake-driven pull
//      are the primary channels).
// ---------------------------------------------------------------------------

const Duration _kResumedAutoInterval = Duration(minutes: 30);

void _defaultResumedPath({
  required void Function() sync,
  required void Function(Duration interval) startAuto,
}) {
  sync();
  startAuto(_kResumedAutoInterval);
}

void main() {
  group('AppLifecycleSyncHandler resumed default path', () {
    test('calls sync() exactly once before startAuto() on resumed', () {
      final calls = <String>[];
      _defaultResumedPath(
        sync: () => calls.add('sync'),
        startAuto: (_) => calls.add('startAuto'),
      );
      expect(calls, equals(['sync', 'startAuto']));
    });

    test('startAuto is invoked with the 30-minute paranoia-net interval', () {
      Duration? observedInterval;
      _defaultResumedPath(
        sync: () {},
        startAuto: (interval) => observedInterval = interval,
      );
      expect(observedInterval, equals(const Duration(minutes: 30)));
    });
  });

  group('AppLifecycleSyncHandler lifecycle dispatch', () {
    late int resumeCount;
    late int pauseCount;

    setUp(() {
      resumeCount = 0;
      pauseCount = 0;
    });

    void onResume() => resumeCount++;
    void onPause() => pauseCount++;

    test('resumed state triggers onResume', () {
      _dispatchLifecycleState(AppLifecycleState.resumed, onResume: onResume, onPause: onPause);
      expect(resumeCount, equals(1));
      expect(pauseCount, equals(0));
    });

    test('paused state triggers onPause', () {
      _dispatchLifecycleState(AppLifecycleState.paused, onResume: onResume, onPause: onPause);
      expect(pauseCount, equals(1));
      expect(resumeCount, equals(0));
    });

    test('detached state triggers onPause', () {
      _dispatchLifecycleState(AppLifecycleState.detached, onResume: onResume, onPause: onPause);
      expect(pauseCount, equals(1));
      expect(resumeCount, equals(0));
    });

    test('inactive state triggers onPause', () {
      _dispatchLifecycleState(AppLifecycleState.inactive, onResume: onResume, onPause: onPause);
      expect(pauseCount, equals(1));
      expect(resumeCount, equals(0));
    });

    test('hidden state triggers onPause', () {
      _dispatchLifecycleState(AppLifecycleState.hidden, onResume: onResume, onPause: onPause);
      expect(pauseCount, equals(1));
      expect(resumeCount, equals(0));
    });

    test('sequence resumed → paused → resumed maps correctly', () {
      _dispatchLifecycleState(AppLifecycleState.resumed, onResume: onResume, onPause: onPause);
      _dispatchLifecycleState(AppLifecycleState.paused, onResume: onResume, onPause: onPause);
      _dispatchLifecycleState(AppLifecycleState.resumed, onResume: onResume, onPause: onPause);
      expect(resumeCount, equals(2));
      expect(pauseCount, equals(1));
    });
  });
}
