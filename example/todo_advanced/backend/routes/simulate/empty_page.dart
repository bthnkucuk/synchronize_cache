import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/empty_page` — body: `{"pages": 1}`.
///
/// The next `GET /todos` request(s) return `{"items": [], "nextPageToken":
/// ...}`: an empty page that is not the last one.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  final pages = await _pages(context);
  if (pages == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'pages must be between 1 and 100'},
    );
  }

  context.read<SimulationService>().answerNextListsWithEmptyPage(count: pages);
  return Response.json(body: {'message': 'Empty page armed', 'pages': pages});
}

Future<int?> _pages(RequestContext context) async {
  try {
    final body = await context.request.body();
    final json = body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    final pages = json['pages'] as int? ?? 1;
    return pages >= 1 && pages <= 100 ? pages : null;
  } on Object {
    return null;
  }
}
