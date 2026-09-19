import 'package:meta/meta.dart';
import 'package:offline_first_sync_drift/src/conflict_resolution.dart';
import 'package:offline_first_sync_drift/src/op.dart';

/// Pull result: list of JSON items and next page pointer.
@immutable
final class const PullPage({
  required final List<Map<String, Object?>> items,
  final String? nextPageToken,
});

/// Push result for a single operation.
final class const OpPushResult({
  required final String opId,
  required final PushResult result,
}) {
  bool get isSuccess => result is PushSuccess;
  bool get isConflict => result is PushConflict;
  bool get isNotFound => result is PushNotFound;
  bool get isError => result is PushError;
}

/// Push result for a batch of operations.
class BatchPushResult {
  const BatchPushResult({required this.results});

  final List<OpPushResult> results;

  /// Whether all operations succeeded.
  bool get allSuccess => results.every((r) => r.isSuccess);

  /// Whether there are conflicts.
  bool get hasConflicts => results.any((r) => r.isConflict);

  /// Whether there are errors.
  bool get hasErrors => results.any((r) => r.isError);

  /// Conflict operations.
  Iterable<OpPushResult> get conflicts => results.where((r) => r.isConflict);

  /// Successful operations.
  Iterable<OpPushResult> get successes => results.where((r) => r.isSuccess);

  /// Failed operations.
  Iterable<OpPushResult> get errors => results.where((r) => r.isError);
}

/// Network transport interface.
abstract interface class TransportAdapter {
  /// Pull a page of data from the server.
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  });

  /// Push operations to the server.
  /// Returns a per-operation result, including conflicts.
  Future<BatchPushResult> push(List<Op> ops);

  /// Force-push an operation (ignore version conflict).
  /// Used by the `clientWins` strategy.
  Future<PushResult> forcePush(Op op);

  /// Fetch the current server version of an entity.
  Future<FetchResult> fetch({required String kind, required String id});

  /// Check server availability.
  Future<bool> health();
}

/// Result of fetching a single entity.
sealed class const FetchResult();

/// Entity found.
final class const FetchSuccess({
  required final Map<String, Object?> data,
  final String? version,
}) extends FetchResult;

/// Entity not found.
final class const FetchNotFound() extends FetchResult;

/// Fetch error.
final class const FetchError(final Object error, [final StackTrace? stackTrace])
    extends FetchResult;
