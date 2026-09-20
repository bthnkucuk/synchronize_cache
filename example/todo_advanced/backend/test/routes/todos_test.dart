import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

import '../../routes/todos/index.dart' as todos_index;
import '../../routes/todos/[id].dart' as todos_id;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late TodoRepository repository;
  late SimulationService simulationService;
  late _MockRequestContext context;

  setUp(() {
    repository = TodoRepository();
    simulationService = SimulationService(repository, NoteRepository());
    context = _MockRequestContext();
    when(() => context.read<TodoRepository>()).thenReturn(repository);
    when(() => context.read<SimulationService>()).thenReturn(simulationService);
  });

  tearDown(() {
    repository.clear();
  });

  group('POST /todos', () {
    test('creates a todo with generated id', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/todos'),
          body: jsonEncode({'title': 'Test Todo'}),
        ),
      );

      final response = await todos_index.onRequest(context);

      expect(response.statusCode, HttpStatus.created);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['id'], isNotEmpty);
      expect(body['title'], 'Test Todo');
      expect(body['completed'], false);
      expect(body['priority'], 3);
    });

    test('creates a todo with client-provided id', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/todos'),
          body: jsonEncode({'id': 'custom-id', 'title': 'Test Todo'}),
        ),
      );

      final response = await todos_index.onRequest(context);

      expect(response.statusCode, HttpStatus.created);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['id'], 'custom-id');
    });
  });

  group('GET /todos', () {
    test('returns empty list when no todos', () async {
      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/todos')));

      final response = await todos_index.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['items'], isEmpty);
    });

    test('returns list of todos', () async {
      repository.create(
        Todo(id: 'todo-1', title: 'First', updatedAt: DateTime.now().toUtc()),
      );
      repository.create(
        Todo(id: 'todo-2', title: 'Second', updatedAt: DateTime.now().toUtc()),
      );

      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/todos')));

      final response = await todos_index.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['items'], hasLength(2));
    });

    test('includes tombstones, unless includeDeleted=false', () async {
      final now = DateTime.now().toUtc();
      repository
        ..create(Todo(id: 'alive', title: 'Alive', updatedAt: now))
        ..create(Todo(id: 'gone', title: 'Gone', updatedAt: now))
        ..delete('gone');

      Future<List<Map<String, dynamic>>> items(String query) async {
        when(() => context.request)
            .thenReturn(Request.get(Uri.parse('http://localhost/todos$query')));
        final response = await todos_index.onRequest(context);
        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        return (body['items'] as List).cast<Map<String, dynamic>>();
      }

      // What RestTransport sends, and what a client that says nothing gets.
      for (final query in ['?includeDeleted=true', '']) {
        final all = await items(query);
        expect(all.map((t) => t['id']).toSet(), {'alive', 'gone'});
        final tombstone = all.singleWhere((t) => t['id'] == 'gone');
        expect(tombstone['deleted_at'], isNotNull);
      }

      final alive = await items('?includeDeleted=false');
      expect(alive.map((t) => t['id']), ['alive']);
    });

    test('a poisoned list carries one unreadable record in front of the real '
        'ones, once', () async {
      repository.create(
        Todo(id: 'todo-1', title: 'Real', updatedAt: DateTime.now().toUtc()),
      );
      simulationService.poisonNextLists(kind: 'todos');
      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/todos')));

      Future<List<Map<String, dynamic>>> list() async {
        final response = await todos_index.onRequest(context);
        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        return (body['items'] as List).cast<Map<String, dynamic>>();
      }

      final poisoned = await list();
      expect(poisoned, hasLength(2));
      expect(poisoned.first['id'], startsWith('!poisoned-'));
      expect(poisoned.first['title'], isNull);
      expect(poisoned.first['updated_at'], poisoned.last['updated_at']);
      expect(poisoned.last['id'], 'todo-1');

      expect(await list(), hasLength(1));
    });

    test('armed list failures let some requests through first', () async {
      simulationService.failListsAfter(after: 1, count: 1, status: 503);
      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/todos')));

      final statuses = [
        for (var i = 0; i < 3; i++)
          (await todos_index.onRequest(context)).statusCode,
      ];

      expect(statuses, [200, 503, 200]);
    });

    test('an armed empty page has no items, names a next page, and the '
        'request for that page starts from the top', () async {
      repository.create(
        Todo(id: 'todo-1', title: 'First', updatedAt: DateTime.now().toUtc()),
      );
      simulationService.answerNextListsWithEmptyPage();

      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/todos')));
      final empty = await todos_index.onRequest(context);
      final emptyBody = jsonDecode(await empty.body()) as Map<String, dynamic>;

      expect(emptyBody['items'], isEmpty);
      final token = emptyBody['nextPageToken'] as String;
      expect(empty.headers['X-Next-Page-Token'], token);

      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/todos?pageToken=$token')),
      );
      final next = await todos_index.onRequest(context);
      final nextBody = jsonDecode(await next.body()) as Map<String, dynamic>;

      expect(nextBody['items'], hasLength(1));
      expect(nextBody.containsKey('nextPageToken'), isFalse);
    });
  });

  group('GET /todos/:id', () {
    test('returns todo by id', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Test', updatedAt: now));

      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/todos/todo-1')));

      final response = await todos_id.onRequest(context, 'todo-1');

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['id'], 'todo-1');
      expect(body['title'], 'Test');
    });

    test('returns 404 for non-existent todo', () async {
      when(() => context.request).thenReturn(
        Request.get(Uri.parse('http://localhost/todos/non-existent')),
      );

      final response = await todos_id.onRequest(context, 'non-existent');

      expect(response.statusCode, HttpStatus.notFound);
    });
  });

  group('PUT /todos/:id', () {
    test('updates todo without conflict check', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Original', updatedAt: now));

      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/todos/todo-1'),
          body: jsonEncode({'title': 'Updated'}),
          headers: {},
        ),
      );

      final response = await todos_id.onRequest(context, 'todo-1');

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['title'], 'Updated');
    });

    test('returns 409 conflict when base_updated_at mismatch', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Original', updatedAt: now));

      final oldTimestamp = now.subtract(const Duration(hours: 1));

      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/todos/todo-1'),
          body: jsonEncode({
            'title': 'Updated',
            '_baseUpdatedAt': oldTimestamp.toIso8601String(),
          }),
          headers: {},
        ),
      );

      final response = await todos_id.onRequest(context, 'todo-1');

      expect(response.statusCode, HttpStatus.conflict);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'conflict');
      expect(body['current'], isNotNull);
      expect(body['current']['title'], 'Original');
    });

    test('a poisoned conflict reports a record nobody can read — for the '
        'record it was armed for, as often as it was armed', () async {
      final now = DateTime.now().toUtc();
      repository
        ..create(Todo(id: 'todo-1', title: 'Original', updatedAt: now))
        ..create(Todo(id: 'todo-2', title: 'Other', updatedAt: now));
      simulationService.poisonNextConflicts(entityId: 'todo-1');

      Future<Map<String, dynamic>> conflictOf(String id) async {
        when(() => context.request).thenReturn(
          Request.put(
            Uri.parse('http://localhost/todos/$id'),
            body: jsonEncode({
              'title': 'Updated',
              '_baseUpdatedAt': now
                  .subtract(const Duration(hours: 1))
                  .toIso8601String(),
            }),
            headers: {},
          ),
        );
        final response = await todos_id.onRequest(context, id);
        expect(response.statusCode, HttpStatus.conflict);
        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        return body['current'] as Map<String, dynamic>;
      }

      // Another record's conflict is untouched and does not use it up.
      expect((await conflictOf('todo-2'))['title'], 'Other');

      final poisoned = await conflictOf('todo-1');
      expect(poisoned['id'], 'todo-1');
      expect(poisoned['title'], isNull);
      expect(poisoned['completed'], isNull);
      expect(poisoned['updated_at'], isNotNull);

      expect((await conflictOf('todo-1'))['title'], 'Original');
    });

    test('updates with X-Force-Update header ignoring conflict', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Original', updatedAt: now));

      final oldTimestamp = now.subtract(const Duration(hours: 1));

      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/todos/todo-1'),
          body: jsonEncode({
            'title': 'Force Updated',
            '_baseUpdatedAt': oldTimestamp.toIso8601String(),
          }),
          headers: {'x-force-update': 'true'},
        ),
      );

      final response = await todos_id.onRequest(context, 'todo-1');

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['title'], 'Force Updated');
    });

    test('respects idempotency key', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Original', updatedAt: now));

      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/todos/todo-1'),
          body: jsonEncode({'title': 'First Update'}),
          headers: {'x-idempotency-key': 'idem-key-1'},
        ),
      );

      final response1 = await todos_id.onRequest(context, 'todo-1');
      expect(response1.statusCode, HttpStatus.ok);

      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/todos/todo-1'),
          body: jsonEncode({'title': 'Second Update'}),
          headers: {'x-idempotency-key': 'idem-key-1'},
        ),
      );

      final response2 = await todos_id.onRequest(context, 'todo-1');
      expect(response2.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response2.body()) as Map<String, dynamic>;
      expect(body['title'], 'First Update');
    });
  });

  group('DELETE /todos/:id', () {
    test('soft deletes todo', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Test', updatedAt: now));

      when(() => context.request).thenReturn(
        Request.delete(Uri.parse('http://localhost/todos/todo-1'), headers: {}),
      );

      final response = await todos_id.onRequest(context, 'todo-1');

      expect(response.statusCode, HttpStatus.noContent);

      final todo = repository.get('todo-1');
      expect(todo!.deletedAt, isNotNull);
    });

    test('returns 404 for non-existent todo', () async {
      when(() => context.request).thenReturn(
        Request.delete(
          Uri.parse('http://localhost/todos/non-existent'),
          headers: {},
        ),
      );

      final response = await todos_id.onRequest(context, 'non-existent');

      expect(response.statusCode, HttpStatus.notFound);
    });

    // What RestTransport actually sends: a DELETE has no body, so the version
    // travels in the query string.
    group('with ?_baseUpdatedAt', () {
      test('deletes when the version still matches', () async {
        final now = DateTime.utc(2026, 9, 19, 18, 17, 8, 281);
        repository.create(Todo(id: 'todo-1', title: 'Test', updatedAt: now));

        when(() => context.request).thenReturn(
          Request.delete(
            Uri.parse(
              'http://localhost/todos/todo-1'
              '?_baseUpdatedAt=${Uri.encodeQueryComponent(now.toIso8601String())}',
            ),
            headers: {},
          ),
        );

        final response = await todos_id.onRequest(context, 'todo-1');

        expect(response.statusCode, HttpStatus.noContent);
        expect(repository.get('todo-1')!.deletedAt, isNotNull);
      });

      test('returns 409 with the current record on a stale version', () async {
        final now = DateTime.utc(2026, 9, 19, 18, 17, 8, 281);
        repository.create(
          Todo(id: 'todo-1', title: 'Edited elsewhere', updatedAt: now),
        );
        final stale = now.subtract(const Duration(hours: 1));

        when(() => context.request).thenReturn(
          Request.delete(
            Uri.parse(
              'http://localhost/todos/todo-1'
              '?_baseUpdatedAt=${Uri.encodeQueryComponent(stale.toIso8601String())}',
            ),
            headers: {},
          ),
        );

        final response = await todos_id.onRequest(context, 'todo-1');

        expect(response.statusCode, HttpStatus.conflict);

        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        expect(body['error'], 'conflict');
        expect(body['current']['title'], 'Edited elsewhere');
        // The record must survive a rejected delete.
        expect(repository.get('todo-1')!.deletedAt, isNull);
      });

      test('X-Force-Delete wins over a stale version', () async {
        final now = DateTime.utc(2026, 9, 19, 18, 17, 8, 281);
        repository.create(Todo(id: 'todo-1', title: 'Test', updatedAt: now));
        final stale = now.subtract(const Duration(hours: 1));

        when(() => context.request).thenReturn(
          Request.delete(
            Uri.parse(
              'http://localhost/todos/todo-1'
              '?_baseUpdatedAt=${Uri.encodeQueryComponent(stale.toIso8601String())}',
            ),
            headers: {'x-force-delete': 'true'},
          ),
        );

        expect(
          (await todos_id.onRequest(context, 'todo-1')).statusCode,
          HttpStatus.noContent,
        );
      });
    });

    test('returns 409 conflict with X-Base-Updated-At mismatch', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Test', updatedAt: now));

      final oldTimestamp = now.subtract(const Duration(hours: 1));

      when(() => context.request).thenReturn(
        Request.delete(
          Uri.parse('http://localhost/todos/todo-1'),
          headers: {'x-base-updated-at': oldTimestamp.toIso8601String()},
        ),
      );

      final response = await todos_id.onRequest(context, 'todo-1');

      expect(response.statusCode, HttpStatus.conflict);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'conflict');
      expect(body['current'], isNotNull);
    });

    test('deletes with X-Force-Delete header ignoring conflict', () async {
      final now = DateTime.now().toUtc();
      repository.create(Todo(id: 'todo-1', title: 'Test', updatedAt: now));

      final oldTimestamp = now.subtract(const Duration(hours: 1));

      when(() => context.request).thenReturn(
        Request.delete(
          Uri.parse('http://localhost/todos/todo-1'),
          headers: {
            'x-base-updated-at': oldTimestamp.toIso8601String(),
            'x-force-delete': 'true',
          },
        ),
      );

      final response = await todos_id.onRequest(context, 'todo-1');

      expect(response.statusCode, HttpStatus.noContent);
    });
  });
}
