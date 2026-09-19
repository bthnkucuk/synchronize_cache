import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/bare_conflict` — body: `{"requests": 1}`.
///
/// The next write(s) to `/todos` are answered with `409 {"error": "conflict"}`
/// — a conflict status without the current record — and are not applied.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final requests = await _requests(context);
  if (requests == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'requests must be between 1 and 100'},
    );
  }

  context.read<SimulationService>().answerNextWritesWithBareConflict(
    count: requests,
  );
  return Response.json(
    body: {'message': 'Bare conflict armed', 'requests': requests},
  );
}

Future<int?> _requests(RequestContext context) async {
  try {
    final body = await context.request.body();
    final json = body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    final requests = json['requests'] as int? ?? 1;
    return requests >= 1 && requests <= 100 ? requests : null;
  } on Object {
    return null;
  }
}
