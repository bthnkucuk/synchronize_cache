import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/api/notes_api.dart';

/// `GET /notes/{id}`, `PUT /notes/{id}` (upsert with the `_baseUpdatedAt`
/// version check) and `DELETE /notes/{id}` (soft delete).
///
/// Same contract as `/todos`, from the same `SyncApi`.
Future<Response> onRequest(RequestContext context, String id) =>
    notesApi(context).entity(context.request, id);
