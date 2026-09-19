import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/fail_writes` — body:
/// `{"status": 401, "requests": 6, "id": "<entity id>"}`.
///
/// The next write(s) to `/todos` or `/notes` fail with that status and are
/// not applied: `401` for an expired token, `503` for an outage, `429` for
/// rate limiting, `422` for a record the server refuses.
///
/// With `id` only writes to that one record fail, and only they consume a
/// slot. That is the difference between "everything is stuck" and "one
/// poisoned item is stuck": with `{"status": 422, "requests": 100, "id": …}`
/// that record burns through the client's retry budget and lands in the
/// stuck list, while every other record keeps syncing normally.
///
/// `requests: 0` disarms it.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final (status, requests, id) = await _read(context);
  if (status == null || requests == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'status must be 400-599 and requests between 0 and 100'},
    );
  }

  context.read<SimulationService>().failNextWrites(
    status: status,
    count: requests,
    entityId: id,
  );
  return Response.json(
    body: {
      'message': 'Write failures armed',
      'status': status,
      'requests': requests,
      'id': ?id,
    },
  );
}

Future<(int?, int?, String?)> _read(RequestContext context) async {
  try {
    final json =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final status = json['status'] as int?;
    final requests = json['requests'] as int? ?? 1;
    final id = json['id'] as String?;
    return (
      status != null && status >= 400 && status <= 599 ? status : null,
      requests >= 0 && requests <= 100 ? requests : null,
      id,
    );
  } on Object {
    return (null, null, null);
  }
}
