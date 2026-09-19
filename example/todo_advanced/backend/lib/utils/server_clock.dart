/// The current time as a version timestamp (`updated_at`).
///
/// Truncated to milliseconds on purpose. Clients send the version they
/// edited back as `_baseUpdatedAt` and the server compares it for equality,
/// so a version must survive a round trip through every client. Browsers
/// (JavaScript `Date`, and therefore Dart on the web) cannot represent
/// microseconds: with `DateTime.now()`'s full precision no web client could
/// ever echo a version back, and each of its edits would be a conflict.
DateTime serverNow() {
  final now = DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  );
}
