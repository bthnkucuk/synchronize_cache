import 'package:flutter/foundation.dart';

/// The intervals the sync panel offers.
const autoSyncIntervals = <Duration>[
  Duration(seconds: 15),
  Duration(minutes: 1),
  Duration(minutes: 5),
];

/// How automatic sync is set up on this device.
@immutable
class AutoSyncSettings {
  const AutoSyncSettings({required this.enabled, required this.interval});

  static const off = AutoSyncSettings(
    enabled: false,
    interval: Duration(minutes: 1),
  );

  final bool enabled;
  final Duration interval;

  AutoSyncSettings copyWith({bool? enabled, Duration? interval}) =>
      AutoSyncSettings(
        enabled: enabled ?? this.enabled,
        interval: interval ?? this.interval,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoSyncSettings &&
          other.enabled == enabled &&
          other.interval == interval;

  @override
  int get hashCode => Object.hash(enabled, interval);
}

/// How long until the next automatic sync, or `null` when there is none.
///
/// The engine drives automatic sync with a plain `Timer.periodic` and does
/// not expose when it will fire next, so the app works it out from the
/// moment the timer was started and the interval. That is the whole trick
/// behind the "Next automatic sync in 0:42" line — and it is pure, so the
/// countdown can be tested without waiting a minute for it.
Duration? timeUntilNextSync({
  required AutoSyncSettings settings,
  required DateTime? startedAt,
  required DateTime now,
}) {
  if (!settings.enabled || startedAt == null) return null;
  if (settings.interval <= Duration.zero) return Duration.zero;

  final elapsed = now.difference(startedAt);
  if (elapsed.isNegative) return settings.interval;

  final ticksDone = elapsed.inMicroseconds ~/ settings.interval.inMicroseconds;
  final next = startedAt.add(settings.interval * (ticksDone + 1));
  final remaining = next.difference(now);
  return remaining.isNegative ? Duration.zero : remaining;
}

/// `0:42`, `1:05`, `5:00` — minutes and seconds, rounded up so the countdown
/// never shows 0:00 while it is still waiting.
String formatCountdown(Duration remaining) {
  final seconds = (remaining.inMilliseconds / 1000).ceil();
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// `every 15 seconds`, `every minute`, `every 5 minutes`.
String describeInterval(Duration interval) {
  if (interval.inSeconds < 60) return 'every ${interval.inSeconds} seconds';
  if (interval.inMinutes == 1) return 'every minute';
  return 'every ${interval.inMinutes} minutes';
}
