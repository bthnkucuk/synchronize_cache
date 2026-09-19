/// Encoding of version timestamps in `sync_outbox.base_updated_at`.
///
/// Servers detect conflicts by comparing `_baseUpdatedAt` with their
/// `updated_at` for **equality**, and most store microseconds (PostgreSQL
/// `timestamptz`, Dart's `DateTime.now()`). The column used to hold
/// milliseconds, so the version an op was based on lost its last three digits
/// on the way through the outbox.
///
/// The column stays an `INTEGER` — no schema change — but new rows hold
/// **microseconds** since the epoch. Rows written by older versions hold
/// milliseconds; the two are told apart by magnitude: `1e14` milliseconds is
/// the year 5138, `1e14` microseconds is March 1973, and a server version
/// timestamp is neither that late nor that early.
library;

const _microsecondsThreshold = 100000000000000; // 1e14

/// Value to store in `sync_outbox.base_updated_at` for [version].
int encodeOutboxTimestamp(DateTime version) =>
    version.toUtc().microsecondsSinceEpoch;

/// Reads a `sync_outbox.base_updated_at` value written by any version.
DateTime decodeOutboxTimestamp(int stored) =>
    stored.abs() >= _microsecondsThreshold
    ? DateTime.fromMicrosecondsSinceEpoch(stored, isUtc: true)
    : DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);
