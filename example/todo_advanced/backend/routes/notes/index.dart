import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/api/notes_api.dart';

/// `GET /notes` — the sync pull (`updatedSince`, `limit`, `pageToken`,
/// `includeDeleted`), and `POST /notes` — create with a server-chosen id.
///
/// Same contract as `/todos`, from the same `SyncApi`.
Future<Response> onRequest(RequestContext context) =>
    notesApi(context).collection(context.request);
