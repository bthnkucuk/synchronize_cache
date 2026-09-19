import 'package:todo_advanced_backend/models/note.dart';
import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/utils/server_clock.dart';

/// Service for simulating what a real server does to a client's data:
/// other devices editing the same records, outages, slow links and the
/// awkward responses a proxy can produce.
///
/// Each simulation is *armed* for a number of requests and then consumed, so
/// a demo can set one up and watch exactly one sync run hit it.
class SimulationService {
  SimulationService(this._todos, this._notes);

  final TodoRepository _todos;
  final NoteRepository _notes;

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

  int _failingWrites = 0;
  int _failureStatus = 503;
  String? _failingEntityId;

  /// Makes the next [count] writes fail with [status] (a `401` for an expired
  /// token, a `503` for an outage) without applying them.
  ///
  /// With [entityId] only writes to that one record fail. That is how a
  /// single poisoned item is demonstrated: it burns through the client's
  /// retry budget and ends up stuck, while every other record keeps syncing.
  void failNextWrites({required int status, int count = 1, String? entityId}) {
    _failureStatus = status;
    _failingWrites = count;
    _failingEntityId = entityId;
  }

  /// The status the current write to [entityId] must fail with, or `null`.
  ///
  /// A scoped failure is only consumed by the record it names, so the slots
  /// are not eaten by unrelated traffic.
  int? takeWriteFailure([String? entityId]) {
    if (_failingWrites <= 0) return null;
    if (_failingEntityId != null && _failingEntityId != entityId) return null;
    _failingWrites--;
    return _failureStatus;
  }

  int _emptyPages = 0;
  String? _emptyPageKind;

  /// Makes the next [count] list requests return an empty page that still
  /// names a next page.
  ///
  /// Servers that filter rows after paginating (row-level permissions, a
  /// DynamoDB `FilterExpression`) legitimately produce such pages. With
  /// [kind] only `GET /todos` or only `GET /notes` is affected, so the
  /// experiment is not consumed by whichever pull happens to run first.
  void answerNextListsWithEmptyPage({int count = 1, String? kind}) {
    _emptyPages = count;
    _emptyPageKind = kind;
  }

  /// Whether the current list request for [kind] must return an empty page.
  bool takeEmptyPage([String? kind]) {
    if (_emptyPages <= 0) return false;
    if (_emptyPageKind != null && _emptyPageKind != kind) return false;
    _emptyPages--;
    return true;
  }

  /// Adds a reminder to a todo's description.
  ///
  /// Simulates a server-side process that adds a reminder notice.
  /// Returns the updated todo or null if not found.
  Todo? addReminder(String id, String reminderText) {
    final current = _todos.get(id);
    if (current == null || current.deletedAt != null) return null;

    final now = serverNow();
    final newDescription = current.description != null
        ? '${current.description}\n\n📋 Reminder: $reminderText'
        : '📋 Reminder: $reminderText';

    final updated = current.copyWith(
      description: newDescription,
      updatedAt: now,
    );

    final result = _todos.update(id, updated, forceUpdate: true);
    if (result is OperationSuccess<Todo>) {
      return result.record;
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

    final allTodos = _todos.list(limit: 1000);
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

        final result = _todos.update(todo.id, updated, forceUpdate: true);
        if (result is OperationSuccess<Todo> && result.record != null) {
          completed.add(result.record!);
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
    final current = _todos.get(id);
    if (current == null || current.deletedAt != null) return null;

    final now = serverNow();
    final updated = current.copyWith(priority: newPriority, updatedAt: now);

    final result = _todos.update(id, updated, forceUpdate: true);
    if (result is OperationSuccess<Todo>) {
      return result.record;
    }
    return null;
  }

  /// Edits a note as if another device had done it.
  ///
  /// The counterpart of [addReminder]/[changePriority] for the second kind.
  /// Leaves out fields the caller did not name, so `{"id": …, "body": …}`
  /// changes only the body — which is what makes the automatic field-level
  /// merge of the notes strategy visible.
  /// Returns the updated note or null if not found.
  Note? editNote(String id, {String? title, String? body}) {
    final current = _notes.get(id);
    if (current == null || current.deletedAt != null) return null;

    final updated = current.copyWith(
      title: title,
      body: body,
      updatedAt: serverNow(),
    );

    final result = _notes.update(id, updated, forceUpdate: true);
    if (result is OperationSuccess<Note>) {
      return result.record;
    }
    return null;
  }
}
