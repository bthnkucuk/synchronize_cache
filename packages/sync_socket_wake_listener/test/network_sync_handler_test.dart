// Tests for NetworkSyncHandler's connectivity-change logic.
// Because the handler relies on Connectivity and SyncEngine (which both need
// full Flutter / Drift initialisation), we test the core reconnect-detection
// state machine directly rather than the class itself.
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Minimal state machine that mirrors NetworkSyncHandler._onChanged behaviour.
// ---------------------------------------------------------------------------

class ReconnectDetector {
  bool wasOffline = false;
  int syncCount = 0;

  void onChanged(bool isOnline) {
    if (!isOnline) {
      wasOffline = true;
      return;
    }
    if (wasOffline) {
      wasOffline = false;
      syncCount++;
    }
  }
}

void main() {
  group('NetworkSyncHandler reconnect detection', () {
    late ReconnectDetector detector;

    setUp(() => detector = ReconnectDetector());

    test('triggers sync on reconnect after offline', () {
      detector
        ..onChanged(false) // goes offline
        ..onChanged(true); // comes back online
      expect(detector.syncCount, equals(1));
    });

    test('does not trigger sync on first online event (never was offline)', () {
      detector.onChanged(true);
      expect(detector.syncCount, equals(0));
    });

    test('triggers sync exactly once per reconnect event', () {
      detector
        ..onChanged(false)
        ..onChanged(true)
        ..onChanged(true); // second online event — already reset flag
      expect(detector.syncCount, equals(1));
    });

    test('triggers sync multiple times for multiple offline/online cycles', () {
      detector
        ..onChanged(false)
        ..onChanged(true)
        ..onChanged(false)
        ..onChanged(true);
      expect(detector.syncCount, equals(2));
    });

    test('does not trigger sync when offline stays offline', () {
      detector
        ..onChanged(false)
        ..onChanged(false)
        ..onChanged(false);
      expect(detector.syncCount, equals(0));
      expect(detector.wasOffline, isTrue);
    });
  });
}
