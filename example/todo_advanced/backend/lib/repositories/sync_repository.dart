import 'package:todo_advanced_backend/models/sync_record.dart';
import 'package:todo_advanced_backend/utils/server_clock.dart';

/// Represents the result of an update/delete operation.
sealed class OperationResult<T extends SyncRecord> {}

/// Operation succeeded.
///
/// [record] is the stored row. It is `null` only for a delete that was
/// already applied by an earlier request with the same idempotency key.
class OperationSuccess<T extends SyncRecord> extends OperationResult<T> {
  OperationSuccess(this.record);
  final T? record;
}

/// Operation failed due to conflict; [current] is what the server holds.
class OperationConflict<T extends SyncRecord> extends OperationResult<T> {
  OperationConflict(this.current);
  final T current;
}

/// Operation failed because entity not found.
class OperationNotFound<T extends SyncRecord> extends OperationResult<T> {}

/// Called after a write actually changed a record.
///
/// The repository knows nothing about WebSockets; the middleware wires this
/// to `ChangeHub.recordChanged` so every write — a client push, a delete or
/// one of the `/simulate/*` endpoints — wakes the other connected apps.
typedef RecordChanged = void Function({
  required String kind,
  required String id,
  required DateTime at,
});

/// In-memory store for one synced kind, with conflict detection.
///
/// Written once and reused by [todos] and [notes]: the sync contract (version
/// check, idempotency, soft delete, `(updated_at, id)` paging) is identical
/// for every kind, only the record type differs.
class SyncRepository<T extends SyncRecord> {
  SyncRepository({required this.kind, required this.tombstone, this.onChanged});

  /// The wire name of this kind (`todos`, `notes`), used in change frames.
  final String kind;

  /// Turns a record into its soft-deleted version, stamped at the given time.
  ///
  /// The only thing this class cannot do generically: a tombstone is still a
  /// record of its kind, so the kind has to build it.
  final T Function(T record, DateTime at) tombstone;

  /// Notified after every write that changed something. Optional so tests can
  /// use a repository without a live change feed.
  final RecordChanged? onChanged;

  final Map<String, T> _records = {};
  final Set<String> _processedIdempotencyKeys = {};

  /// Maximum number of idempotency keys to retain (prevents memory leak).
  static const _maxIdempotencyKeys = 1000;

  /// Adds an idempotency key and cleans up if over limit.
  void _addIdempotencyKey(String key) {
    _processedIdempotencyKeys.add(key);
    if (_processedIdempotencyKeys.length > _maxIdempotencyKeys) {
      // Simple cleanup: clear all when over limit (acceptable for demo)
      _processedIdempotencyKeys.clear();
      _processedIdempotencyKeys.add(key);
    }
  }

  void _announce(T record) {
    onChanged?.call(kind: kind, id: record.id, at: record.updatedAt);
  }

  /// Lists records in `(updated_at, id)` order, with optional pagination.
  ///
  /// With [includeDeleted] the soft-deleted records are part of the result,
  /// as tombstones (`deleted_at` set). A sync client needs them: they are the
  /// only way it learns that another device deleted something.
  List<T> list({
    DateTime? updatedSince,
    int limit = 500,
    String? pageToken,
    bool includeDeleted = false,
  }) {
    var records = _records.values.where(
      (r) => includeDeleted || r.deletedAt == null,
    );

    if (updatedSince != null) {
      records = records.where((r) => r.updatedAt.isAfter(updatedSince));
    }

    var sorted = records.toList()
      ..sort((a, b) {
        final cmp = a.updatedAt.compareTo(b.updatedAt);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });

    if (pageToken != null) {
      final idx = sorted.indexWhere((r) => r.id == pageToken);
      if (idx != -1) {
        sorted = sorted.sublist(idx + 1);
      }
    }

    if (sorted.length > limit) {
      return sorted.sublist(0, limit);
    }
    return sorted;
  }

  /// Gets a record by id.
  T? get(String id) => _records[id];

  /// Creates a new record.
  T create(T record) {
    _records[record.id] = record;
    _announce(record);
    return record;
  }

  /// Updates a record with conflict detection.
  ///
  /// If [baseUpdatedAt] is provided, checks that current.updatedAt matches.
  /// Returns [OperationConflict] if there's a mismatch.
  /// If [forceUpdate] is true, skips conflict check.
  OperationResult<T> update(
    String id,
    T updated, {
    DateTime? baseUpdatedAt,
    bool forceUpdate = false,
    String? idempotencyKey,
  }) {
    if (idempotencyKey != null &&
        _processedIdempotencyKeys.contains(idempotencyKey)) {
      final current = _records[id];
      return current != null
          ? OperationSuccess<T>(current)
          : OperationNotFound<T>();
    }

    final current = _records[id];
    if (current == null) {
      _records[id] = updated;
      if (idempotencyKey != null) {
        _addIdempotencyKey(idempotencyKey);
      }
      _announce(updated);
      return OperationSuccess<T>(updated);
    }

    if (!forceUpdate && baseUpdatedAt != null) {
      if (current.updatedAt != baseUpdatedAt) {
        return OperationConflict<T>(current);
      }
    }

    _records[id] = updated;
    if (idempotencyKey != null) {
      _addIdempotencyKey(idempotencyKey);
    }
    _announce(updated);
    return OperationSuccess<T>(updated);
  }

  /// Soft-deletes a record with conflict detection.
  ///
  /// If [baseUpdatedAt] is provided, checks that current.updatedAt matches.
  /// Returns [OperationConflict] if there's a mismatch.
  /// If [forceDelete] is true, skips conflict check.
  OperationResult<T> delete(
    String id, {
    DateTime? baseUpdatedAt,
    bool forceDelete = false,
    String? idempotencyKey,
  }) {
    if (idempotencyKey != null &&
        _processedIdempotencyKeys.contains(idempotencyKey)) {
      return OperationSuccess<T>(null);
    }

    final current = _records[id];
    if (current == null) {
      return OperationNotFound<T>();
    }

    if (!forceDelete && baseUpdatedAt != null) {
      if (current.updatedAt != baseUpdatedAt) {
        return OperationConflict<T>(current);
      }
    }

    final deleted = tombstone(current, serverNow());
    _records[id] = deleted;
    if (idempotencyKey != null) {
      _addIdempotencyKey(idempotencyKey);
    }
    _announce(deleted);
    return OperationSuccess<T>(deleted);
  }

  /// Checks if an idempotency key was already processed.
  bool isIdempotencyKeyProcessed(String key) {
    return _processedIdempotencyKeys.contains(key);
  }

  /// Clears all data (for testing, and for `POST /reset`).
  void clear() {
    _records.clear();
    _processedIdempotencyKeys.clear();
  }
}
