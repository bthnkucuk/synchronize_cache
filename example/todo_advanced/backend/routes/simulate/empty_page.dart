import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/empty_page` — body: `{"pages": 1, "kind": "notes"}`.
///
/// The next list request(s) return `{"items": [], "nextPageToken": ...}`: an
/// empty page that is not the last one. With `kind` only `GET /todos` or
/// only `GET /notes` is affected, so a pull of the other kind cannot consume
/// the experiment first.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final (pages, kind) = await _read(context);
  if (pages == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'pages must be between 1 and 100'},
    );
  }

  context.read<SimulationService>().answerNextListsWithEmptyPage(
    count: pages,
    kind: kind,
  );
  return Response.json(
    body: {'message': 'Empty page armed', 'pages': pages, 'kind': ?kind},
  );
}

Future<(int?, String?)> _read(RequestContext context) async {
  try {
    final body = await context.request.body();
    final json = body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    final pages = json['pages'] as int? ?? 1;
    return (pages >= 1 && pages <= 100 ? pages : null, json['kind'] as String?);
  } on Object {
    return (null, null);
  }
}
