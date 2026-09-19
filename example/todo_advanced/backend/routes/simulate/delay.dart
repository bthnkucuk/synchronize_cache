import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/delay` — body: `{"milliseconds": 6000, "requests": 1}`.
///
/// Arms an artificial delay for the next API requests, simulating a stalled
/// connection.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  try {
    final json =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final milliseconds = json['milliseconds'] as int?;
    final requests = json['requests'] as int? ?? 1;

    if (milliseconds == null || milliseconds < 0 || milliseconds > 60000) {
      return Response(
        statusCode: 400,
        body: jsonEncode({'error': 'milliseconds must be between 0 and 60000'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    context.read<SimulationService>().delayNextRequests(
      Duration(milliseconds: milliseconds),
      count: requests,
    );

    return Response(
      body: jsonEncode({'message': 'Delay armed', 'requests': requests}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (_) {
    return Response(
      statusCode: 400,
      body: jsonEncode({'error': 'Invalid request body'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
