import 'package:flutter/foundation.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

/// Why a queued write did not get through, in words a user can act on.
///
/// [environmental] is the distinction the whole retry budget turns on: a
/// failure that is not this item's fault (no connection, expired sign-in,
/// server down, "slow down") is **not** counted as an attempt, so the item
/// waits instead of ever becoming stuck.
@immutable
class FailureReason {
  const FailureReason(this.words, {required this.environmental});

  final String words;
  final bool environmental;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FailureReason &&
          other.words == words &&
          other.environmental == environmental;

  @override
  int get hashCode => Object.hash(words, environmental);

  @override
  String toString() => 'FailureReason($words, environmental: $environmental)';
}

/// The precise translation, from the error the engine actually classified.
///
/// Prefer this over [describeStoredFailure]: it comes from
/// `OperationFailedEvent.errorInfo` and never has to guess.
FailureReason describeFailure(SyncErrorInfo info) {
  final status = info.statusCode;
  final words = switch (info.category) {
    SyncErrorCategory.network => 'No connection to the server',
    SyncErrorCategory.auth => 'Your sign-in has expired',
    SyncErrorCategory.server =>
      'The server is having trouble'
          '${status == null ? '' : ' (HTTP $status)'}',
    SyncErrorCategory.parse => 'The server sent something we cannot read',
    SyncErrorCategory.database => 'This device could not store the change',
    SyncErrorCategory.conflict => 'Someone else changed this item',
    SyncErrorCategory.unknown => _unknownWords(status, info.message),
  };
  return FailureReason(words, environmental: info.isEnvironmental);
}

String _unknownWords(int? status, String? message) => switch (status) {
  null =>
    message == null || message.isEmpty
        ? 'The change could not be sent'
        : message,
  408 || 425 => 'The request took too long; it will be tried again',
  429 => 'The server asked us to slow down',
  >= 500 => 'The server is having trouble (HTTP $status)',
  _ => 'The server refused this item (HTTP $status)',
};

/// The best guess from what the outbox stored.
///
/// `sync_outbox_meta.last_error` is only a string — it survives a reload,
/// which the live `SyncErrorInfo` does not — so the chip can still explain
/// itself after the app is reopened.
FailureReason describeStoredFailure(String lastError) {
  final status = _statusIn(lastError);
  if (status != null) {
    return describeFailure(
      SyncErrorInfo(
        category: switch (status) {
          401 || 403 => SyncErrorCategory.auth,
          >= 500 => SyncErrorCategory.server,
          _ => SyncErrorCategory.unknown,
        },
        retryable: status >= 500 || const {408, 425, 429}.contains(status),
        statusCode: status,
      ),
    );
  }

  const networkMarkers = [
    'NetworkException',
    'ClientException',
    'TimeoutException',
    'MaxRetriesExceeded',
    'SocketException',
    'Failed host lookup',
  ];
  if (networkMarkers.any(lastError.contains)) {
    return const FailureReason(
      'No connection to the server',
      environmental: true,
    );
  }

  return FailureReason(lastError, environmental: false);
}

/// Pulls `401` out of `TransportException: HTTP error 401 (status: 401)`.
int? _statusIn(String message) {
  final match =
      RegExp(r'status:\s*(\d{3})').firstMatch(message) ??
      RegExp(r'HTTP error (\d{3})').firstMatch(message);
  return match == null ? null : int.tryParse(match.group(1)!);
}
