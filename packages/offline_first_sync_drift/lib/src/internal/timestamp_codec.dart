/// Encoding of server version timestamps in the sync tables' `INTEGER`
/// columns: `sync_outbox.base_updated_at` and `sync_cursors.ts`.
///
/// Both are compared with what the server holds — the base for **equality**
/// (`_baseUpdatedAt` vs `updated_at`), the cursor as the lower bound of the
/// next pull — and most servers store microseconds (PostgreSQL `timestamptz`,
/// Dart's `DateTime.now()`). The columns used to hold milliseconds, so a
/// version lost its last three digits on the way through them: a base never
/// equalled the server's version again, and a cursor pointed just before the
/// last row it had seen, which was then delivered again by every pull.
///
/// The columns stay `INTEGER` — no schema change — but new rows hold
/// **microseconds** since the epoch. Rows written by older versions hold
/// milliseconds; the two are told apart by magnitude: `1e14` milliseconds is
/// the year 5138, `1e14` microseconds is March 1973.
///
/// A timestamp whose microsecond value is below that threshold (1966 – 1973,
/// e.g. a legacy row whose `updated_at` was defaulted to the epoch) would be
/// read back as milliseconds, so it is *stored* as milliseconds: encoding and
/// decoding are exact inverses for every date, and only such a timestamp's
/// sub-millisecond digits are dropped.
library;

const _microsecondsThreshold = 100000000000000; // 1e14

/// Value to store for [version].
int encodeTimestamp(DateTime version) {
  final utc = version.toUtc();
  final microseconds = utc.microsecondsSinceEpoch;
  return microseconds.abs() >= _microsecondsThreshold
      ? microseconds
      : utc.millisecondsSinceEpoch;
}

/// Reads a value written by [encodeTimestamp] or by an older version of this
/// package (milliseconds).
DateTime decodeTimestamp(int stored) => stored.abs() >= _microsecondsThreshold
    ? DateTime.fromMicrosecondsSinceEpoch(stored, isUtc: true)
    : DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);
