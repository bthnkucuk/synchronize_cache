import 'package:meta/meta.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/op.dart';
import 'package:offline_first_sync_drift/src/sync_database.dart';

/// Service for working with the outbox queue.
@immutable
final class const OutboxService(final SyncDatabaseMixin _db) {
  /// Add operation to the send queue.
  Future<void> enqueue(Op op) async {
    try {
      await _db.enqueue(op);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Get operations from queue for sending.
  ///
  /// If [kinds] is provided, only operations for those kinds are returned.
  Future<List<Op>> take({
    int limit = 100,
    Set<String>? kinds,
    int? maxTryCountExclusive,
  }) async {
    try {
      return await _db.takeOutbox(
        limit: limit,
        kinds: kinds,
        maxTryCountExclusive: maxTryCountExclusive,
      );
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Re-base the queued ops of one entity onto the version the server just
  /// reported. See [SyncDatabaseMixin.rebaseOutboxOps].
  Future<void> rebase({
    required String kind,
    required String entityId,
    required DateTime serverVersion,
  }) async {
    try {
      await _db.rebaseOutboxOps(
        kind: kind,
        entityId: entityId,
        serverVersion: serverVersion,
      );
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Re-base the ops still queued for the given `(kind, entity id)`s onto the
  /// versions the server just reported, touching only entities that have any.
  /// See [SyncDatabaseMixin.rebaseQueuedOutboxOps].
  Future<void> rebaseAll(Map<(String, String), DateTime> serverVersions) async {
    if (serverVersions.isEmpty) return;
    try {
      await _db.rebaseQueuedOutboxOps(serverVersions);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Acknowledge sent operations (remove from queue).
  Future<void> ack(Iterable<String> opIds) async {
    if (opIds.isEmpty) return;
    try {
      await _db.ackOutbox(opIds);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Purge operations older than threshold.
  Future<int> purgeOlderThan(DateTime threshold) async {
    try {
      return await _db.purgeOutboxOlderThan(threshold);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Check whether queue contains operations.
  Future<bool> hasOperations({Set<String>? kinds}) async {
    final ops = await take(limit: 1, kinds: kinds);
    return ops.isNotEmpty;
  }

  /// Reactive stream of pending operations count.
  Stream<int> watchPendingCount({
    Set<String>? kinds,
    int? maxTryCountExclusive,
  }) => _db.watchOutboxCount(
    kinds: kinds,
    maxTryCountExclusive: maxTryCountExclusive,
  );

  /// Reactive stream indicating whether pending operations exist.
  Stream<bool> watchHasOperations({
    Set<String>? kinds,
    int? maxTryCountExclusive,
  }) => watchPendingCount(
    kinds: kinds,
    maxTryCountExclusive: maxTryCountExclusive,
  ).map((count) => count > 0);

  /// Increment try count for operations.
  Future<void> incrementTryCount(Iterable<String> opIds) async {
    try {
      await _db.incrementOutboxTryCount(opIds);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Record per-operation failures: increments tryCount and stores metadata.
  ///
  /// Pass `countAttempts: false` for failures that are not the operation's
  /// fault; see [SyncDatabaseMixin.recordOutboxFailures].
  Future<void> recordFailures(
    Map<String, String> errors, {
    DateTime? triedAt,
    bool countAttempts = true,
  }) async {
    try {
      await _db.recordOutboxFailures(
        errors,
        triedAt: triedAt,
        countAttempts: countAttempts,
      );
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Reset try count for operations.
  Future<void> resetTryCount(Iterable<String> opIds) async {
    try {
      await _db.resetOutboxTryCount(opIds);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Get operations treated as stuck.
  Future<List<Op>> getStuck({
    required int minTryCount,
    int limit = 100,
    Set<String>? kinds,
  }) async {
    try {
      return await _db.getStuckOutbox(
        minTryCount: minTryCount,
        limit: limit,
        kinds: kinds,
      );
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Count operations treated as stuck.
  Future<int> countStuck({required int minTryCount, Set<String>? kinds}) async {
    try {
      return await _db.countStuckOutbox(minTryCount: minTryCount, kinds: kinds);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }
}
