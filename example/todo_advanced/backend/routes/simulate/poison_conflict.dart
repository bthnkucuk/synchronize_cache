import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/poison_conflict` — body: `{"id": "…", "requests": 5}`.
///
/// The next conflict answer(s) (`409`) about that record carry a `current`
/// whose fields are `null` — a record the client's model cannot read.
/// `requests: 0` disarms it.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  try {
    final json =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final id = json['id'] as String?;
    final requests = json['requests'] as int? ?? 1;
    if (id == null || id.isEmpty || requests < 0 || requests > 100) {
      throw const FormatException('id / requests');
    }

    context.read<SimulationService>().poisonNextConflicts(
      entityId: id,
      count: requests,
    );
    return Response.json(
      body: {
        'message': 'Poisoned conflicts armed',
        'id': id,
        'requests': requests,
      },
    );
  } on Object {
    return Response.json(
      statusCode: 400,
      body: {'error': 'id is required; requests must be between 0 and 100'},
    );
  }
}
