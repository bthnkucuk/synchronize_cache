import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/poison_row` — body: `{"lists": 3, "kind": "todos"}`.
///
/// The next non-empty list response(s) carry one record whose required
/// fields are `null` — a row the client's model cannot read. `lists: 0`
/// disarms it; without `kind` it applies to whichever kind is listed next.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  try {
    final body = await context.request.body();
    final json = body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    final lists = json['lists'] as int? ?? 1;
    final kind = json['kind'] as String?;
    if (lists < 0 || lists > 100) throw const FormatException('lists');

    context.read<SimulationService>().poisonNextLists(count: lists, kind: kind);
    return Response.json(
      body: {'message': 'Poisoned rows armed', 'lists': lists, 'kind': kind},
    );
  } on Object {
    return Response.json(
      statusCode: 400,
      body: {'error': 'lists must be between 0 and 100'},
    );
  }
}
