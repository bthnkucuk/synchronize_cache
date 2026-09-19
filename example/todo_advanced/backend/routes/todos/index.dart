import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/api/todos_api.dart';

/// `GET /todos` — the sync pull (`updatedSince`, `limit`, `pageToken`,
/// `includeDeleted`), and `POST /todos` — create with a server-chosen id.
///
/// The behaviour lives in `SyncApi`, which `/notes` uses as well.
Future<Response> onRequest(RequestContext context) =>
    todosApi(context).collection(context.request);
