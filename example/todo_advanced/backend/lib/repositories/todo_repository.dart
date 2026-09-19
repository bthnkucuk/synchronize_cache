import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/sync_repository.dart';

export 'package:todo_advanced_backend/repositories/sync_repository.dart'
    show
        OperationConflict,
        OperationNotFound,
        OperationResult,
        OperationSuccess,
        RecordChanged;

/// In-memory repository for todos.
///
/// Everything about the sync contract lives in [SyncRepository]; a kind only
/// has to say what its wire name is and how one of its records becomes a
/// tombstone.
class TodoRepository extends SyncRepository<Todo> {
  TodoRepository({super.onChanged})
    : super(
        kind: 'todos',
        tombstone: (todo, at) => todo.copyWith(updatedAt: at, deletedAt: at),
      );
}
