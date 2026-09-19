import 'package:flutter_test/flutter_test.dart';
import 'package:todo_advanced_frontend/services/auto_sync.dart';

/// The engine never says when its `Timer.periodic` fires next, so the app
/// works it out. These are the sums the countdown shows.
void main() {
  final started = DateTime.utc(2026, 9, 20, 10);
  const minute = AutoSyncSettings(
    enabled: true,
    interval: Duration(minutes: 1),
  );

  group('timeUntilNextSync', () {
    test('is null while automatic sync is off', () {
      expect(
        timeUntilNextSync(
          settings: AutoSyncSettings.off,
          startedAt: started,
          now: started,
        ),
        isNull,
      );
    });

    test('is null before the timer has been started', () {
      expect(
        timeUntilNextSync(settings: minute, startedAt: null, now: started),
        isNull,
      );
    });

    test('counts down within the first interval', () {
      expect(
        timeUntilNextSync(
          settings: minute,
          startedAt: started,
          now: started.add(const Duration(seconds: 18)),
        ),
        const Duration(seconds: 42),
      );
    });

    test('resets at every tick instead of going negative', () {
      // Two and a half intervals in: the next tick is at 3 minutes.
      expect(
        timeUntilNextSync(
          settings: minute,
          startedAt: started,
          now: started.add(const Duration(minutes: 2, seconds: 30)),
        ),
        const Duration(seconds: 30),
      );
    });

    test('is a whole interval exactly on a tick', () {
      expect(
        timeUntilNextSync(
          settings: minute,
          startedAt: started,
          now: started.add(const Duration(minutes: 1)),
        ),
        const Duration(minutes: 1),
      );
    });

    test('survives a clock that jumped backwards', () {
      expect(
        timeUntilNextSync(
          settings: minute,
          startedAt: started,
          now: started.subtract(const Duration(minutes: 5)),
        ),
        const Duration(minutes: 1),
      );
    });

    test('works for every interval the panel offers', () {
      for (final interval in autoSyncIntervals) {
        expect(
          timeUntilNextSync(
            settings: AutoSyncSettings(enabled: true, interval: interval),
            startedAt: started,
            now: started,
          ),
          interval,
          reason: '$interval should start a full interval away',
        );
      }
    });
  });

  group('formatCountdown', () {
    test('rounds up so it never shows 0:00 while still waiting', () {
      expect(formatCountdown(const Duration(milliseconds: 1)), '0:01');
      expect(formatCountdown(Duration.zero), '0:00');
    });

    test('pads seconds', () {
      expect(formatCountdown(const Duration(seconds: 42)), '0:42');
      expect(formatCountdown(const Duration(seconds: 65)), '1:05');
      expect(formatCountdown(const Duration(minutes: 5)), '5:00');
    });
  });

  group('describeInterval', () {
    test('reads like English', () {
      expect(describeInterval(const Duration(seconds: 15)), 'every 15 seconds');
      expect(describeInterval(const Duration(minutes: 1)), 'every minute');
      expect(describeInterval(const Duration(minutes: 5)), 'every 5 minutes');
    });
  });
}
