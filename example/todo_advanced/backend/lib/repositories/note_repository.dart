import 'package:todo_advanced_backend/models/note.dart';
import 'package:todo_advanced_backend/repositories/sync_repository.dart';

export 'package:todo_advanced_backend/repositories/sync_repository.dart'
    show
        OperationConflict,
        OperationNotFound,
        OperationResult,
        OperationSuccess,
        RecordChanged;

/// In-memory repository for notes.
///
/// Identical in behaviour to `TodoRepository` — that is the point: both are
/// thin declarations on top of the shared [SyncRepository].
class NoteRepository extends SyncRepository<Note> {
  NoteRepository({super.onChanged})
    : super(
        kind: 'notes',
        tombstone: (note, at) => note.copyWith(updatedAt: at, deletedAt: at),
      );
}
