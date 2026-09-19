import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/utils/server_clock.dart';

/// Service for simulating server-side modifications to todos.
///
/// This demonstrates scenarios where the server modifies data independently,
/// which can cause conflicts with client changes.
class SimulationService {
  SimulationService(this._repository);

  final TodoRepository _repository;

  Duration _pendingDelay = Duration.zero;
  int _delayedRequests = 0;

  /// Makes the next [count] API requests respond only after [delay].
  ///
  /// Simulates a stalled connection (captive portal, overloaded server) so
  /// clients can demonstrate their request timeout handling.
  void delayNextRequests(Duration delay, {int count = 1}) {
    _pendingDelay = delay;
    _delayedRequests = count;
  }

  /// Returns the delay to apply to the current request and consumes one slot.
  Duration takeDelay() {
    if (_delayedRequests <= 0) return Duration.zero;
    _delayedRequests--;
    return _pendingDelay;
  }

  int _bareConflicts = 0;
  int _emptyPages = 0;

  /// Makes the next [count] writes answer `409` with an error body instead
  /// of the current record.
  ///
  /// This is what a proxy, an API gateway or a framework's default error
  /// handler puts in front of a real backend: a conflict status that does
  /// not carry the row the client would need to resolve it.
  void answerNextWritesWithBareConflict({int count = 1}) =>
      _bareConflicts = count;

  /// Whether the current write must be answered with a bare `409`.
  bool takeBareConflict() {
    if (_bareConflicts <= 0) return false;
    _bareConflicts--;
    return true;
  }

  /// Makes the next [count] list requests return an empty page that still
  /// names a next page.
  ///
  /// Servers that filter rows after paginating (row-level permissions, a
  /// DynamoDB `FilterExpression`) legitimately produce such pages.
  void answerNextListsWithEmptyPage({int count = 1}) => _emptyPages = count;

  /// Whether the current list request must return an empty page.
  bool takeEmptyPage() {
    if (_emptyPages <= 0) return false;
    _emptyPages--;
    return true;
  }

  /// Adds a reminder to a todo's description.
  ///
  /// Simulates a server-side process that adds a reminder notice.
  /// Returns the updated todo or null if not found.
  Todo? addReminder(String id, String reminderText) {
    final current = _repository.get(id);
    if (current == null || current.deletedAt != null) return null;

    final now = serverNow();
    final newDescription = current.description != null
        ? '${current.description}\n\n📋 Reminder: $reminderText'
        : '📋 Reminder: $reminderText';

    final updated = current.copyWith(
      description: newDescription,
      updatedAt: now,
    );

    final result = _repository.update(id, updated, forceUpdate: true);
    if (result is OperationSuccess) {
      return result.todo;
    }
    return null;
  }

  /// Auto-completes overdue todos.
  ///
  /// Simulates a server-side cron job that marks overdue incomplete todos.
  /// Returns list of todos that were auto-completed.
  List<Todo> autoCompleteOverdue() {
    final now = serverNow();
    final completed = <Todo>[];

    final allTodos = _repository.list(limit: 1000);
    for (final todo in allTodos) {
      if (!todo.completed &&
          todo.dueDate != null &&
          todo.dueDate!.isBefore(now)) {
        final updated = todo.copyWith(
          completed: true,
          description: todo.description != null
              ? '${todo.description}\n\n⏰ Auto-completed (overdue)'
              : '⏰ Auto-completed (overdue)',
          updatedAt: now,
        );

        final result = _repository.update(todo.id, updated, forceUpdate: true);
        if (result is OperationSuccess && result.todo != null) {
          completed.add(result.todo!);
        }
      }
    }

    return completed;
  }

  /// Changes a todo's priority.
  ///
  /// Simulates a server-side priority adjustment.
  /// Returns the updated todo or null if not found.
  Todo? changePriority(String id, int newPriority) {
    final current = _repository.get(id);
    if (current == null || current.deletedAt != null) return null;

    final now = serverNow();
    final updated = current.copyWith(priority: newPriority, updatedAt: now);

    final result = _repository.update(id, updated, forceUpdate: true);
    if (result is OperationSuccess) {
      return result.todo;
    }
    return null;
  }
}
