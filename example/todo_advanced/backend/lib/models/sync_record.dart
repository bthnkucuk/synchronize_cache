/// What every synced kind (`todos`, `notes`, …) has in common.
///
/// The sync contract only cares about three things per record: which row it
/// is ([id]), which version of it the server holds ([updatedAt]) and whether
/// it is a tombstone ([deletedAt]). Everything else is the kind's own
/// business. Keeping that in one interface is what lets `SyncRepository` and
/// the route helpers in `lib/api/` be written once and used by every kind.
abstract interface class const SyncRecord() {
  /// Client-generated identifier. The client picks it so a row created
  /// offline keeps the same id once it reaches the server.
  String get id;

  /// The version of this record. Clients echo it back as `_baseUpdatedAt`
  /// to say "this is what I edited"; the server compares it for equality.
  DateTime get updatedAt;

  /// Set once the record was soft-deleted. A pull still returns the record
  /// so other devices learn about the delete.
  DateTime? get deletedAt;

  /// The record on the wire, in snake_case (`updated_at`, `deleted_at`).
  Map<String, dynamic> toJson();
}
