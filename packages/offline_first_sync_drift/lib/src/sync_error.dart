import 'dart:async';

import 'package:offline_first_sync_drift/src/exceptions.dart';

/// High-level category for sync failures.
enum SyncErrorCategory {
  network,
  auth,
  server,
  parse,
  database,
  conflict,
  unknown,
}

/// Normalized error payload for UI and telemetry.
class SyncErrorInfo {
  const SyncErrorInfo({
    required this.category,
    required this.retryable,
    this.statusCode,
    this.message,
  });

  final SyncErrorCategory category;
  final bool retryable;
  final int? statusCode;
  final String? message;

  /// Statuses with which a server says "not now" rather than "not this":
  /// request timeout, too early, too many requests.
  static const _notNowStatuses = {408, 425, 429};

  /// Whether the failure describes the conditions an operation was sent
  /// under — no connectivity, a timeout, missing or expired credentials,
  /// rate limiting, a server that is down — rather than the operation.
  ///
  /// Such a failure is nothing the operation can be blamed for, so it does
  /// not use up its retry budget (`SyncConfig.maxOutboxTryCount`). That
  /// budget exists to get an operation the server will never accept out of
  /// the way; a device that was offline for a few sync attempts must not end
  /// up with its whole queue parked as "stuck".
  bool get isEnvironmental {
    final code = statusCode;
    return category == SyncErrorCategory.network ||
        category == SyncErrorCategory.auth ||
        (code != null && (code >= 500 || _notNowStatuses.contains(code)));
  }

  static SyncErrorInfo fromError(Object error) {
    if (error is TransportException) {
      final code = error.statusCode;
      if (code == 401 || code == 403) {
        return SyncErrorInfo(
          category: SyncErrorCategory.auth,
          retryable: false,
          statusCode: code,
          message: error.message,
        );
      }
      final isServer = code != null && code >= 500;
      return SyncErrorInfo(
        category: isServer
            ? SyncErrorCategory.server
            : SyncErrorCategory.unknown,
        retryable: isServer || _notNowStatuses.contains(code),
        statusCode: code,
        message: error.message,
      );
    }

    if (error is NetworkException ||
        error is MaxRetriesExceededException ||
        error is TimeoutException) {
      return SyncErrorInfo(
        category: SyncErrorCategory.network,
        retryable: true,
        message: error.toString(),
      );
    }
    if (error is ParseException) {
      return SyncErrorInfo(
        category: SyncErrorCategory.parse,
        retryable: false,
        message: error.message,
      );
    }
    if (error is DatabaseException) {
      return SyncErrorInfo(
        category: SyncErrorCategory.database,
        retryable: false,
        message: error.message,
      );
    }
    if (error is ConflictException) {
      return SyncErrorInfo(
        category: SyncErrorCategory.conflict,
        retryable: true,
        message: error.message,
      );
    }

    return SyncErrorInfo(
      category: SyncErrorCategory.unknown,
      retryable: false,
      message: error.toString(),
    );
  }
}
