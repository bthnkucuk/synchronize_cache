import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/fail_writes` — body: `{"status": 401, "requests": 6}`.
///
/// The next write(s) to `/todos` fail with that status and are not applied:
/// `401` for an expired token, `503` for an outage, `429` for rate limiting.
/// `requests: 0` disarms it.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final (status, requests) = await _read(context);
  if (status == null || requests == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'status must be 400-599 and requests between 0 and 100'},
    );
  }

  context.read<SimulationService>().failNextWrites(
    status: status,
    count: requests,
  );
  return Response.json(
    body: {'message': 'Write failures armed', 'status': status},
  );
}

Future<(int?, int?)> _read(RequestContext context) async {
  try {
    final json =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final status = json['status'] as int?;
    final requests = json['requests'] as int? ?? 1;
    return (
      status != null && status >= 400 && status <= 599 ? status : null,
      requests >= 0 && requests <= 100 ? requests : null,
    );
  } on Object {
    return (null, null);
  }
}
