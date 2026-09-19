import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/todo.dart';
import '../../repositories/todo_repository.dart';
import '../widgets/todo_card.dart';
import 'todo_edit_screen.dart';

/// The todo list.
///
/// The app bar, the conflict dialog and the navigation live in
/// `HomeScreen`; this is one destination inside it. The server simulations
/// that used to hang off this screen now have a screen of their own — the
/// Sync lab — where each of them says what it proves.
class TodoListScreen extends StatelessWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TodoRepository>();

    return Scaffold(
      body: StreamBuilder<List<Todo>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Text('Failed to load todos'),
                ],
              ),
            );
          }

          final todos = snapshot.data ?? const <Todo>[];
          if (todos.isEmpty) return const _EmptyState();

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 88),
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return TodoCard(
                key: ValueKey(todo.id),
                todo: todo,
                onToggle: () => repo.toggleCompleted(todo),
                onTap: () => _editTodo(context, todo),
                onDelete: () => _deleteTodo(context, repo, todo),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const TodoEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add Todo'),
      ),
    );
  }

  Future<void> _editTodo(BuildContext context, Todo todo) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TodoEditScreen(todo: todo)),
    );
  }

  Future<void> _deleteTodo(
    BuildContext context,
    TodoRepository repo,
    Todo todo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Todo'),
        content: Text('Are you sure you want to delete "${todo.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await repo.delete(todo);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Deleted here. The server still has it until the delete is sent.',
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.checklist,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No todos yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to create your first todo',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
