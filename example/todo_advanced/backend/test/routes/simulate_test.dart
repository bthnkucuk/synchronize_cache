import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:todo_advanced_backend/models/note.dart';
import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

import '../../routes/simulate/bare_conflict.dart' as simulate_bare_conflict;
import '../../routes/simulate/complete.dart' as simulate_complete;
import '../../routes/simulate/edit_note.dart' as simulate_edit_note;
import '../../routes/simulate/empty_page.dart' as simulate_empty_page;
import '../../routes/simulate/fail_writes.dart' as simulate_fail_writes;
import '../../routes/simulate/prioritize.dart' as simulate_prioritize;
import '../../routes/simulate/reminder.dart' as simulate_reminder;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late TodoRepository repository;
  late NoteRepository noteRepository;
  late SimulationService simulationService;
  late _MockRequestContext context;

  setUp(() {
    repository = TodoRepository();
    noteRepository = NoteRepository();
    simulationService = SimulationService(repository, noteRepository);
    context = _MockRequestContext();
    when(() => context.read<SimulationService>()).thenReturn(simulationService);
  });

  tearDown(() {
    repository.clear();
    noteRepository.clear();
  });

  group('POST /simulate/reminder', () {
    test('adds reminder to existing todo', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Original', updatedAt: now));

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/reminder'),
          body: jsonEncode({'id': 'todo-1', 'text': 'Remember to check this!'}),
        ),
      );

      final response = await simulate_reminder.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['message'], 'Reminder added');
      expect(body['todo']['description'], contains('Remember to check this!'));
    });

    test('returns 404 for non-existent todo', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/reminder'),
          body: jsonEncode({'id': 'non-existent', 'text': 'Some reminder'}),
        ),
      );

      final response = await simulate_reminder.onRequest(context);

      expect(response.statusCode, HttpStatus.notFound);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'Todo not found');
    });

    test('returns 400 when missing required fields', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/reminder'),
          body: jsonEncode({'id': 'todo-1'}),
        ),
      );

      final response = await simulate_reminder.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('Missing required fields'));
    });

    test('returns 405 for non-POST methods', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/simulate/reminder')),
      );

      final response = await simulate_reminder.onRequest(context);

      expect(response.statusCode, 405);
    });
  });

  group('POST /simulate/complete', () {
    test('auto-completes overdue todos', () async {
      final now = DateTime.now().toUtc();
      final yesterday = now.subtract(const Duration(days: 1));

      repository.create(
        Todo(
          id: 'todo-1',
          title: 'Overdue todo',
          dueDate: yesterday,
          completed: false,
          updatedAt: now,
        ),
      );
      repository.create(
        Todo(
          id: 'todo-2',
          title: 'Not overdue',
          dueDate: now.add(const Duration(days: 1)),
          completed: false,
          updatedAt: now,
        ),
      );
      repository.create(
        Todo(
          id: 'todo-3',
          title: 'Already completed',
          dueDate: yesterday,
          completed: true,
          updatedAt: now,
        ),
      );

      when(() => context.request).thenReturn(
        Request.post(Uri.parse('http://localhost/simulate/complete')),
      );

      final response = await simulate_complete.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['message'], contains('1'));
      expect(body['todos'], hasLength(1));
      expect(body['todos'][0]['id'], 'todo-1');
      expect(body['todos'][0]['completed'], true);
    });

    test('returns empty list when no overdue todos', () async {
      final now = DateTime.now().toUtc();

      repository.create(
        Todo(
          id: 'todo-1',
          title: 'Future todo',
          dueDate: now.add(const Duration(days: 1)),
          completed: false,
          updatedAt: now,
        ),
      );

      when(() => context.request).thenReturn(
        Request.post(Uri.parse('http://localhost/simulate/complete')),
      );

      final response = await simulate_complete.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['todos'], isEmpty);
    });

    test('returns 405 for non-POST methods', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/simulate/complete')),
      );

      final response = await simulate_complete.onRequest(context);

      expect(response.statusCode, 405);
    });
  });

  group('POST /simulate/prioritize', () {
    test('changes priority of existing todo', () async {
      final now = DateTime.now().toUtc();
      repository.create(
        Todo(id: 'todo-1', title: 'Test', priority: 3, updatedAt: now),
      );

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/prioritize'),
          body: jsonEncode({'id': 'todo-1', 'priority': 1}),
        ),
      );

      final response = await simulate_prioritize.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['message'], 'Priority changed');
      expect(body['todo']['priority'], 1);
    });

    test('returns 404 for non-existent todo', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/prioritize'),
          body: jsonEncode({'id': 'non-existent', 'priority': 1}),
        ),
      );

      final response = await simulate_prioritize.onRequest(context);

      expect(response.statusCode, HttpStatus.notFound);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'Todo not found');
    });

    test('returns 400 when priority is out of range', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Test', updatedAt: now));

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/prioritize'),
          body: jsonEncode({'id': 'todo-1', 'priority': 10}),
        ),
      );

      final response = await simulate_prioritize.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('Priority must be between 1 and 5'));
    });

    test('returns 400 when missing required fields', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/prioritize'),
          body: jsonEncode({'id': 'todo-1'}),
        ),
      );

      final response = await simulate_prioritize.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('Missing required fields'));
    });

    test('returns 405 for non-POST methods', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/simulate/prioritize')),
      );

      final response = await simulate_prioritize.onRequest(context);

      expect(response.statusCode, 405);
    });
  });

  group('POST /simulate/bare_conflict', () {
    test('arms exactly the requested number of writes', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/bare_conflict'),
          body: jsonEncode({'requests': 2}),
        ),
      );

      final response = await simulate_bare_conflict.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      expect(simulationService.takeBareConflict(), isTrue);
      expect(simulationService.takeBareConflict(), isTrue);
      expect(simulationService.takeBareConflict(), isFalse);
    });

    test('defaults to one write and rejects nonsense', () async {
      when(() => context.request).thenReturn(
        Request.post(Uri.parse('http://localhost/simulate/bare_conflict')),
      );
      expect(
        (await simulate_bare_conflict.onRequest(context)).statusCode,
        HttpStatus.ok,
      );
      expect(simulationService.takeBareConflict(), isTrue);
      expect(simulationService.takeBareConflict(), isFalse);

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/bare_conflict'),
          body: jsonEncode({'requests': 0}),
        ),
      );
      expect(
        (await simulate_bare_conflict.onRequest(context)).statusCode,
        HttpStatus.badRequest,
      );
    });
  });

  group('POST /simulate/fail_writes', () {
    test(
      'arms the status for exactly the requested number of writes',
      () async {
        when(() => context.request).thenReturn(
          Request.post(
            Uri.parse('http://localhost/simulate/fail_writes'),
            body: jsonEncode({'status': 401, 'requests': 2}),
          ),
        );

        final response = await simulate_fail_writes.onRequest(context);

        expect(response.statusCode, HttpStatus.ok);
        expect(simulationService.takeWriteFailure(), 401);
        expect(simulationService.takeWriteFailure(), 401);
        expect(simulationService.takeWriteFailure(), isNull);
      },
    );

    test('rejects a status that is not a failure', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/fail_writes'),
          body: jsonEncode({'status': 200}),
        ),
      );

      final response = await simulate_fail_writes.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(simulationService.takeWriteFailure(), isNull);
    });

    test('an armed id fails only that record, and only it uses up a '
        'slot', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/fail_writes'),
          body: jsonEncode({'status': 422, 'requests': 2, 'id': 'poisoned'}),
        ),
      );

      final response = await simulate_fail_writes.onRequest(context);
      expect(response.statusCode, HttpStatus.ok);

      // Other records keep flowing, and do not eat the armed slots.
      expect(simulationService.takeWriteFailure('healthy'), isNull);
      expect(simulationService.takeWriteFailure(), isNull);

      expect(simulationService.takeWriteFailure('poisoned'), 422);
      expect(simulationService.takeWriteFailure('poisoned'), 422);
      expect(simulationService.takeWriteFailure('poisoned'), isNull);
    });

    test('arming without an id goes back to failing every write', () async {
      simulationService.failNextWrites(
        status: 422,
        count: 1,
        entityId: 'poisoned',
      );

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/fail_writes'),
          body: jsonEncode({'status': 503, 'requests': 1}),
        ),
      );
      await simulate_fail_writes.onRequest(context);

      expect(simulationService.takeWriteFailure('anything'), 503);
    });
  });

  group('POST /simulate/empty_page', () {
    test('arms exactly the requested number of list requests', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/empty_page'),
          body: jsonEncode({'pages': 1}),
        ),
      );

      final response = await simulate_empty_page.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      expect(simulationService.takeEmptyPage(), isTrue);
      expect(simulationService.takeEmptyPage(), isFalse);
    });

    test('an armed kind is not consumed by the other kind', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/empty_page'),
          body: jsonEncode({'pages': 1, 'kind': 'notes'}),
        ),
      );

      expect(
        (await simulate_empty_page.onRequest(context)).statusCode,
        HttpStatus.ok,
      );
      expect(simulationService.takeEmptyPage('todos'), isFalse);
      expect(simulationService.takeEmptyPage('notes'), isTrue);
      expect(simulationService.takeEmptyPage('notes'), isFalse);
    });

    test('returns 405 for non-POST methods', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/simulate/empty_page')),
      );

      expect((await simulate_empty_page.onRequest(context)).statusCode, 405);
    });
  });

  group('POST /simulate/edit_note', () {
    test('changes only the fields that were sent', () async {
      noteRepository.create(
        Note(
          id: 'note-1',
          title: 'Original title',
          body: 'Original body',
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/edit_note'),
          body: jsonEncode({'id': 'note-1', 'body': 'Edited elsewhere'}),
        ),
      );

      final response = await simulate_edit_note.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['message'], 'Note edited');
      expect(body['note']['body'], 'Edited elsewhere');
      expect(body['note']['title'], 'Original title');
    });

    test('bumps the version so the next pull sees it', () async {
      final before = DateTime.utc(2024);
      noteRepository.create(
        Note(id: 'note-1', title: 'Original', updatedAt: before),
      );

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/edit_note'),
          body: jsonEncode({'id': 'note-1', 'title': 'Edited elsewhere'}),
        ),
      );

      await simulate_edit_note.onRequest(context);

      expect(noteRepository.get('note-1')!.updatedAt.isAfter(before), isTrue);
    });

    test('returns 404 for a non-existent note', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/edit_note'),
          body: jsonEncode({'id': 'nope', 'title': 'Edited'}),
        ),
      );

      final response = await simulate_edit_note.onRequest(context);

      expect(response.statusCode, HttpStatus.notFound);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'Note not found');
    });

    test('returns 404 for a deleted note', () async {
      noteRepository
        ..create(
          Note(id: 'note-1', title: 'Gone', updatedAt: DateTime.utc(2024)),
        )
        ..delete('note-1');

      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/edit_note'),
          body: jsonEncode({'id': 'note-1', 'title': 'Edited'}),
        ),
      );

      expect(
        (await simulate_edit_note.onRequest(context)).statusCode,
        HttpStatus.notFound,
      );
    });

    test('returns 400 when nothing would change', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/edit_note'),
          body: jsonEncode({'id': 'note-1'}),
        ),
      );

      final response = await simulate_edit_note.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('at least one of'));
    });

    test('returns 400 when the id is missing', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/simulate/edit_note'),
          body: jsonEncode({'title': 'Edited'}),
        ),
      );

      final response = await simulate_edit_note.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('Missing required field'));
    });

    test('returns 405 for non-POST methods', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/simulate/edit_note')),
      );

      expect((await simulate_edit_note.onRequest(context)).statusCode, 405);
    });
  });
}
