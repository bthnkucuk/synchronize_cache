import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// `POST /simulate/edit_note` — body: `{"id": "…", "title": "…", "body": "…"}`.
///
/// "Another device edited this note." Both fields are optional and only the
/// ones that are present change, so you can edit the body here while the app
/// edits the title — the case where the notes conflict strategy merges the
/// two versions without asking anybody.
///
/// The counterpart for todos is `/simulate/prioritize` and
/// `/simulate/reminder`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }

  try {
    final json =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;

    final id = json['id'] as String?;
    final title = json['title'] as String?;
    final body = json['body'] as String?;

    if (id == null) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing required field: id'},
      );
    }
    if (title == null && body == null) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Provide at least one of: title, body'},
      );
    }

    final note = context.read<SimulationService>().editNote(
      id,
      title: title,
      body: body,
    );

    if (note == null) {
      return Response.json(statusCode: 404, body: {'error': 'Note not found'});
    }

    return Response.json(
      body: {'message': 'Note edited', 'note': note.toJson()},
    );
  } on Object {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid request body'},
    );
  }
}
