import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/api/sync_api.dart';
import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// The `/todos` endpoints, built from what the middleware provides.
SyncApi<Todo> todosApi(RequestContext context) => SyncApi<Todo>(
  kind: 'todos',
  repository: context.read<TodoRepository>(),
  simulations: context.read<SimulationService>(),
  parse: parseTodo,
  notFoundMessage: 'Todo not found',
);

/// Reads a todo out of a request body, or throws [InvalidRecord].
///
/// Out-of-range values are clamped rather than rejected, because a sync
/// client cannot show a `400` to anyone: the write is already in its outbox.
Todo parseTodo(String id, Map<String, dynamic> json, DateTime now) {
  final title = requiredTitle(json);
  final priority = (json['priority'] as int? ?? 3).clamp(1, 5);

  // Parse due_date safely (type-check before cast).
  DateTime? dueDate;
  final dueDateValue = json['due_date'];
  if (dueDateValue is String) {
    dueDate = DateTime.tryParse(dueDateValue);
  }

  return Todo(
    id: id,
    title: title,
    description: json['description'] as String?,
    completed: json['completed'] as bool? ?? false,
    priority: priority,
    dueDate: dueDate,
    updatedAt: now,
  );
}
