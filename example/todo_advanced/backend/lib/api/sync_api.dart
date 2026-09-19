import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/models/sync_record.dart';
import 'package:todo_advanced_backend/repositories/sync_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';
import 'package:todo_advanced_backend/utils/server_clock.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _jsonHeaders = {'Content-Type': 'application/json'};

/// Thrown by a [RecordParser] when the request body is not a valid record.
///
/// The message is what the client sees in `{"error": …}` of the `400`, so
/// write it for a human ("title is required and must be 1-500 characters").
class InvalidRecord implements Exception {
  const InvalidRecord(this.message);
  final String message;
}

/// Builds the record a write wants to store, or throws [InvalidRecord].
///
/// [id] comes from the URL (`PUT /todos/{id}`) or from the body / a fresh
/// uuid (`POST /todos`), and [now] is the version the server stamps on it.
typedef RecordParser<T extends SyncRecord> = T Function(
  String id,
  Map<String, dynamic> json,
  DateTime now,
);

/// Reads the `title` every kind in this example requires.
String requiredTitle(Map<String, dynamic> json) {
  final title = json['title'];
  if (title == null ||
      title is! String ||
      title.isEmpty ||
      title.length > 500) {
    throw const InvalidRecord('title is required and must be 1-500 characters');
  }
  return title;
}

/// The REST endpoints of one synced kind.
///
/// `/todos` and `/notes` are the same eight lines of routing on top of this:
/// list with `updatedSince`/`limit`/`pageToken`/`includeDeleted`, upsert with
/// the `_baseUpdatedAt` version check, and soft delete. Holding it in one
/// place is what keeps the two kinds honestly identical — a second kind that
/// quietly disagrees about paging or conflicts would not demonstrate much.
class SyncApi<T extends SyncRecord> {
  const SyncApi({
    required this.kind,
    required this.repository,
    required this.simulations,
    required this.parse,
    required this.notFoundMessage,
  });

  /// The wire name of the kind (`todos`, `notes`).
  final String kind;
  final SyncRepository<T> repository;
  final SimulationService simulations;
  final RecordParser<T> parse;

  /// What a `404` says, e.g. `'Todo not found'`.
  final String notFoundMessage;

  /// Handles `GET /{kind}` and `POST /{kind}`.
  Future<Response> collection(Request request) async {
    return switch (request.method) {
      HttpMethod.get => _list(request),
      HttpMethod.post => await _create(request),
      _ => Response(statusCode: 405),
    };
  }

  /// Handles `GET`, `PUT` and `DELETE` on `/{kind}/{id}`.
  Future<Response> entity(Request request, String id) async {
    return switch (request.method) {
      HttpMethod.get => _read(id),
      HttpMethod.put => await _update(request, id),
      HttpMethod.delete => _delete(request, id),
      _ => Response(statusCode: 405),
    };
  }

  Response _list(Request request) {
    final params = request.uri.queryParameters;

    DateTime? updatedSince;
    if (params['updatedSince'] != null) {
      updatedSince = DateTime.tryParse(params['updatedSince']!);
    }

    final limit = (int.tryParse(params['limit'] ?? '') ?? 500).clamp(1, 1000);
    final pageToken = params['pageToken'];

    // Armed via `POST /simulate/empty_page`: nothing on this page, more behind
    // it. The token matches no record, so the next request starts from the top.
    if (simulations.takeEmptyPage(kind)) {
      const next = 'after-the-empty-page';
      return Response(
        body: jsonEncode({'items': <Object>[], 'nextPageToken': next}),
        headers: {..._jsonHeaders, 'X-Next-Page-Token': next},
      );
    }

    // Sync clients ask for tombstones by default (`includeDeleted=true`);
    // without them a delete never reaches the user's other devices.
    final includeDeleted = params['includeDeleted'] != 'false';

    final records = repository.list(
      updatedSince: updatedSince,
      limit: limit + 1,
      pageToken: pageToken,
      includeDeleted: includeDeleted,
    );

    String? nextPageToken;
    List<T> result;
    if (records.length > limit) {
      result = records.sublist(0, limit);
      nextPageToken = result.last.id;
    } else {
      result = records;
    }

    return Response(
      body: jsonEncode({
        'items': result.map((r) => r.toJson()).toList(),
        'nextPageToken': ?nextPageToken,
      }),
      headers: {..._jsonHeaders, 'X-Next-Page-Token': ?nextPageToken},
    );
  }

  Future<Response> _create(Request request) async {
    try {
      final json = await _decode(request);
      // The client normally generates the id itself and uses PUT; POST is
      // here for the rare client that lets the server name the record.
      final id = json['id'] as String? ?? _uuid.v4();
      final created = repository.create(parse(id, json, serverNow()));

      return Response(
        statusCode: 201,
        body: jsonEncode(created.toJson()),
        headers: _jsonHeaders,
      );
    } on InvalidRecord catch (e) {
      return _error(400, e.message);
    } on Object {
      return _error(400, 'Invalid request body');
    }
  }

  Response _read(String id) {
    final record = repository.get(id);
    if (record == null || record.deletedAt != null) {
      return _error(404, notFoundMessage);
    }
    return Response(body: jsonEncode(record.toJson()), headers: _jsonHeaders);
  }

  Future<Response> _update(Request request, String id) async {
    final headers = request.headers;
    final idempotencyKey = headers['x-idempotency-key'];
    final forceUpdate = headers['x-force-update']?.toLowerCase() == 'true';

    try {
      final json = await _decode(request);
      final incoming = parse(id, json, serverNow());

      // RestTransport sends the version it edited as `_baseUpdatedAt`
      // (camelCase, inside the body) — type-check before cast.
      DateTime? baseUpdatedAt;
      final baseUpdatedAtValue = json['_baseUpdatedAt'];
      if (baseUpdatedAtValue is String) {
        baseUpdatedAt = DateTime.tryParse(baseUpdatedAtValue);
      }

      final result = repository.update(
        id,
        incoming,
        baseUpdatedAt: baseUpdatedAt,
        forceUpdate: forceUpdate,
        idempotencyKey: idempotencyKey,
      );

      return _respond(result);
    } on InvalidRecord catch (e) {
      return _error(400, e.message);
    } on Object {
      return _error(400, 'Invalid request body');
    }
  }

  Response _delete(Request request, String id) {
    final headers = request.headers;
    final idempotencyKey = headers['x-idempotency-key'];
    final forceDelete = headers['x-force-delete']?.toLowerCase() == 'true';

    // A delete carries the version it was based on in the query string —
    // `DELETE /{kind}/{id}?_baseUpdatedAt=…` — because a DELETE has no body.
    // That is what `RestTransport` sends and what docs/backend-transport.md
    // specifies. The header is accepted as well for hand-written clients.
    final baseUpdatedAtValue =
        request.uri.queryParameters['_baseUpdatedAt'] ??
        headers['x-base-updated-at'];
    final baseUpdatedAt = baseUpdatedAtValue == null
        ? null
        : DateTime.tryParse(baseUpdatedAtValue);

    final result = repository.delete(
      id,
      baseUpdatedAt: baseUpdatedAt,
      forceDelete: forceDelete,
      idempotencyKey: idempotencyKey,
    );

    return switch (result) {
      OperationSuccess<T>() => Response(statusCode: 204),
      OperationConflict<T>(:final current) => _conflict(current),
      OperationNotFound<T>() => _error(404, notFoundMessage),
    };
  }

  /// The answer to a write: the saved record, the current one on a conflict,
  /// or a `404`. Clients re-base their queued edits onto the record they get
  /// back, so a successful write must always return it.
  Response _respond(OperationResult<T> result) {
    return switch (result) {
      OperationSuccess<T>(:final record) => Response(
        body: jsonEncode(record?.toJson()),
        headers: _jsonHeaders,
      ),
      OperationConflict<T>(:final current) => _conflict(current),
      OperationNotFound<T>() => _error(404, notFoundMessage),
    };
  }

  Response _conflict(T current) => Response(
    statusCode: 409,
    body: jsonEncode({'error': 'conflict', 'current': current.toJson()}),
    headers: _jsonHeaders,
  );

  Response _error(int statusCode, String message) => Response(
    statusCode: statusCode,
    body: jsonEncode({'error': message}),
    headers: _jsonHeaders,
  );

  Future<Map<String, dynamic>> _decode(Request request) async {
    return jsonDecode(await request.body()) as Map<String, dynamic>;
  }
}
