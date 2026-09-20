import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/fail_lists` — body: `{"after": 1, "requests": 1,
/// "status": 503}`.
///
/// Lets `after` list requests through and fails the next `requests` with
/// `status`: a connection that drops in the middle of a long download, such
/// as a full resync. `requests: 0` disarms it.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  try {
    final body = await context.request.body();
    final json = body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    final after = json['after'] as int? ?? 0;
    final requests = json['requests'] as int? ?? 1;
    final status = json['status'] as int? ?? 503;
    if (after < 0 || requests < 0 || requests > 100 || status < 400) {
      throw const FormatException('range');
    }

    context.read<SimulationService>().failListsAfter(
      after: after,
      count: requests,
      status: status,
    );
    return Response.json(
      body: {'message': 'List failures armed', 'after': after},
    );
  } on Object {
    return Response.json(
      statusCode: 400,
      body: {'error': 'after >= 0, requests 0-100, status >= 400'},
    );
  }
}
