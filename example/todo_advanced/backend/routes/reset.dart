import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';

/// Reset endpoint for testing.
///
/// POST /reset - Clears every kind (todos and notes) from the repositories.
/// Only available in development/testing environments.
///
/// It deliberately sends no `changed` frames on `/ws`: a reset can wipe
/// hundreds of records, and a frame per record would be a storm. Connected
/// apps notice the empty server at their next pull.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  context.read<TodoRepository>().clear();
  context.read<NoteRepository>().clear();
  return Response.json(body: {'status': 'cleared'});
}
