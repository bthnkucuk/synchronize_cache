import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:todo_advanced_backend/models/note.dart';
import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';

import '../../routes/reset.dart' as reset;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late TodoRepository todos;
  late NoteRepository notes;
  late _MockRequestContext context;

  setUp(() {
    todos = TodoRepository();
    notes = NoteRepository();
    context = _MockRequestContext();
    when(() => context.read<TodoRepository>()).thenReturn(todos);
    when(() => context.read<NoteRepository>()).thenReturn(notes);
  });

  test('POST /reset clears every kind', () async {
    final now = DateTime.now().toUtc();
    todos.create(Todo(id: 'todo-1', title: 'Todo', updatedAt: now));
    notes.create(Note(id: 'note-1', title: 'Note', updatedAt: now));

    when(() => context.request)
        .thenReturn(Request.post(Uri.parse('http://localhost/reset')));

    final response = reset.onRequest(context);

    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(await response.body()), {'status': 'cleared'});
    expect(todos.list(includeDeleted: true), isEmpty);
    expect(notes.list(includeDeleted: true), isEmpty);
  });

  test('returns 405 for non-POST methods', () {
    when(() => context.request)
        .thenReturn(Request.get(Uri.parse('http://localhost/reset')));

    expect(reset.onRequest(context).statusCode, HttpStatus.methodNotAllowed);
  });
}
