import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => _get(context),
    HttpMethod.post => await _post(context),
    _ => Response(statusCode: 405),
  };
}

Response _get(RequestContext context) {
  final repository = context.read<TodoRepository>();
  final params = context.request.uri.queryParameters;

  DateTime? updatedSince;
  if (params['updatedSince'] != null) {
    updatedSince = DateTime.tryParse(params['updatedSince']!);
  }

  final limit = (int.tryParse(params['limit'] ?? '') ?? 500).clamp(1, 1000);
  final pageToken = params['pageToken'];

  final todos = repository.list(
    updatedSince: updatedSince,
    limit: limit + 1,
    pageToken: pageToken,
  );

  String? nextPageToken;
  List<Todo> result;
  if (todos.length > limit) {
    result = todos.sublist(0, limit);
    nextPageToken = result.last.id;
  } else {
    result = todos;
  }

  return Response(
    body: jsonEncode({
      'items': result.map((t) => t.toJson()).toList(),
      'nextPageToken': ?nextPageToken,
    }),
    headers: {
      'Content-Type': 'application/json',
      'X-Next-Page-Token': ?nextPageToken,
    },
  );
}

Future<Response> _post(RequestContext context) async {
  final repository = context.read<TodoRepository>();

  try {
    final body = await context.request.body();
    final json = jsonDecode(body) as Map<String, dynamic>;

    // Validate required fields
    final title = json['title'];
    if (title == null ||
        title is! String ||
        title.isEmpty ||
        title.length > 500) {
      return Response(
        statusCode: 400,
        body: jsonEncode({
          'error': 'title is required and must be 1-500 characters',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final id = json['id'] as String? ?? _uuid.v4();
    final now = DateTime.now().toUtc();

    // Validate priority range (1-5)
    final priority = (json['priority'] as int? ?? 3).clamp(1, 5);

    // Parse due_date safely (type-check before cast)
    DateTime? dueDate;
    final dueDateValue = json['due_date'];
    if (dueDateValue is String) {
      dueDate = DateTime.tryParse(dueDateValue);
    }

    final todo = Todo(
      id: id,
      title: title,
      description: json['description'] as String?,
      completed: json['completed'] as bool? ?? false,
      priority: priority,
      dueDate: dueDate,
      updatedAt: now,
    );

    final created = repository.create(todo);

    return Response(
      statusCode: 201,
      body: jsonEncode(created.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response(
      statusCode: 400,
      body: jsonEncode({'error': 'Invalid request body'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
