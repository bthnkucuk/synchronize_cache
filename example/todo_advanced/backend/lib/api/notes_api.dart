import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/api/sync_api.dart';
import 'package:todo_advanced_backend/models/note.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// The `/notes` endpoints, built from what the middleware provides.
SyncApi<Note> notesApi(RequestContext context) => SyncApi<Note>(
  kind: 'notes',
  repository: context.read<NoteRepository>(),
  simulations: context.read<SimulationService>(),
  parse: parseNote,
  notFoundMessage: 'Note not found',
);

/// Reads a note out of a request body, or throws [InvalidRecord].
Note parseNote(String id, Map<String, dynamic> json, DateTime now) {
  return Note(
    id: id,
    title: requiredTitle(json),
    body: json['body'] as String?,
    pinned: json['pinned'] as bool? ?? false,
    updatedAt: now,
  );
}
