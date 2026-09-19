import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/api/todos_api.dart';

/// `GET /todos/{id}`, `PUT /todos/{id}` (upsert with the `_baseUpdatedAt`
/// version check) and `DELETE /todos/{id}` (soft delete).
///
/// The behaviour lives in `SyncApi`, which `/notes` uses as well.
Future<Response> onRequest(RequestContext context, String id) =>
    todosApi(context).entity(context.request, id);
