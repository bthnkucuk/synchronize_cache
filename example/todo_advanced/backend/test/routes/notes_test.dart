import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:todo_advanced_backend/models/note.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

import '../../routes/notes/index.dart' as notes_index;
import '../../routes/notes/[id].dart' as notes_id;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late NoteRepository repository;
  late SimulationService simulationService;
  late _MockRequestContext context;

  setUp(() {
    repository = NoteRepository();
    simulationService = SimulationService(TodoRepository(), repository);
    context = _MockRequestContext();
    when(() => context.read<NoteRepository>()).thenReturn(repository);
    when(() => context.read<SimulationService>()).thenReturn(simulationService);
  });

  tearDown(() {
    repository.clear();
  });

  group('POST /notes', () {
    test('creates a note with generated id', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/notes'),
          body: jsonEncode({'title': 'Groceries'}),
        ),
      );

      final response = await notes_index.onRequest(context);

      expect(response.statusCode, HttpStatus.created);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['id'], isNotEmpty);
      expect(body['title'], 'Groceries');
      expect(body['body'], isNull);
      expect(body['pinned'], false);
      expect(body['updated_at'], isNotNull);
    });

    test('keeps body and pinned, and a client-provided id', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/notes'),
          body: jsonEncode({
            'id': 'note-1',
            'title': 'Groceries',
            'body': 'Milk, bread',
            'pinned': true,
          }),
        ),
      );

      final response = await notes_index.onRequest(context);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['id'], 'note-1');
      expect(body['body'], 'Milk, bread');
      expect(body['pinned'], true);
    });

    test('rejects a missing title', () async {
      when(() => context.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/notes'),
          body: jsonEncode({'body': 'No title'}),
        ),
      );

      final response = await notes_index.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], contains('title is required'));
    });
  });

  group('GET /notes', () {
    test('returns notes in (updated_at, id) order', () async {
      final now = DateTime.now().toUtc();
      repository
        ..create(
          Note(
            id: 'b',
            title: 'Second',
            updatedAt: now.add(const Duration(seconds: 1)),
          ),
        )
        ..create(Note(id: 'a', title: 'First', updatedAt: now));

      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/notes')));

      final response = await notes_index.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((n) => n['id']), ['a', 'b']);
    });

    test('includes tombstones, unless includeDeleted=false', () async {
      final now = DateTime.now().toUtc();
      repository
        ..create(Note(id: 'alive', title: 'Alive', updatedAt: now))
        ..create(Note(id: 'gone', title: 'Gone', updatedAt: now))
        ..delete('gone');

      Future<List<Map<String, dynamic>>> items(String query) async {
        when(() => context.request)
            .thenReturn(Request.get(Uri.parse('http://localhost/notes$query')));
        final response = await notes_index.onRequest(context);
        final body = jsonDecode(await response.body()) as Map<String, dynamic>;
        return (body['items'] as List).cast<Map<String, dynamic>>();
      }

      for (final query in ['?includeDeleted=true', '']) {
        final all = await items(query);
        expect(all.map((n) => n['id']).toSet(), {'alive', 'gone'});
        expect(
          all.singleWhere((n) => n['id'] == 'gone')['deleted_at'],
          isNotNull,
        );
      }

      expect((await items('?includeDeleted=false')).map((n) => n['id']), [
        'alive',
      ]);
    });

    test('pages with limit and pageToken', () async {
      final now = DateTime.now().toUtc();
      for (var i = 0; i < 3; i++) {
        repository.create(
          Note(
            id: 'note-$i',
            title: 'Note $i',
            updatedAt: now.add(Duration(seconds: i)),
          ),
        );
      }

      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/notes?limit=2')));
      final first = await notes_index.onRequest(context);
      final firstBody = jsonDecode(await first.body()) as Map<String, dynamic>;

      expect(firstBody['items'], hasLength(2));
      final token = firstBody['nextPageToken'] as String;
      expect(token, 'note-1');
      expect(first.headers['X-Next-Page-Token'], token);

      when(() => context.request).thenReturn(
        Request.get(
          Uri.parse('http://localhost/notes?limit=2&pageToken=$token'),
        ),
      );
      final second = await notes_index.onRequest(context);
      final secondBody =
          jsonDecode(await second.body()) as Map<String, dynamic>;

      expect(secondBody['items'], hasLength(1));
      expect(secondBody.containsKey('nextPageToken'), isFalse);
    });

    test('an empty page armed for notes applies to GET /notes', () async {
      repository.create(
        Note(id: 'note-1', title: 'First', updatedAt: DateTime.now().toUtc()),
      );
      simulationService.answerNextListsWithEmptyPage(kind: 'notes');

      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/notes')));
      final empty = await notes_index.onRequest(context);
      final emptyBody = jsonDecode(await empty.body()) as Map<String, dynamic>;

      expect(emptyBody['items'], isEmpty);
      expect(emptyBody['nextPageToken'], isNotNull);
    });
  });

  group('GET /notes/:id', () {
    test('returns the note', () async {
      repository.create(
        Note(id: 'note-1', title: 'Test', updatedAt: DateTime.now().toUtc()),
      );

      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/notes/note-1')));

      final response = await notes_id.onRequest(context, 'note-1');

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['title'], 'Test');
    });

    test('returns 404 for a non-existent note', () async {
      when(() => context.request)
          .thenReturn(Request.get(Uri.parse('http://localhost/notes/nope')));

      final response = await notes_id.onRequest(context, 'nope');

      expect(response.statusCode, HttpStatus.notFound);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'Note not found');
    });
  });

  group('PUT /notes/:id', () {
    test('upserts a note the server has never seen', () async {
      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/notes/note-1'),
          body: jsonEncode({'title': 'Created by a push'}),
          headers: {},
        ),
      );

      final response = await notes_id.onRequest(context, 'note-1');

      expect(response.statusCode, HttpStatus.ok);
      expect(repository.get('note-1')!.title, 'Created by a push');
    });

    test('returns 409 with the current record on a version mismatch', () async {
      final now = DateTime.now().toUtc();
      repository.create(Note(id: 'note-1', title: 'Original', updatedAt: now));

      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/notes/note-1'),
          body: jsonEncode({
            'title': 'Updated',
            '_baseUpdatedAt': now
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          }),
          headers: {},
        ),
      );

      final response = await notes_id.onRequest(context, 'note-1');

      expect(response.statusCode, HttpStatus.conflict);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['error'], 'conflict');
      expect(body['current']['title'], 'Original');
    });

    test('X-Force-Update skips the version check', () async {
      final now = DateTime.now().toUtc();
      repository.create(Note(id: 'note-1', title: 'Original', updatedAt: now));

      when(() => context.request).thenReturn(
        Request.put(
          Uri.parse('http://localhost/notes/note-1'),
          body: jsonEncode({
            'title': 'Force Updated',
            '_baseUpdatedAt': now
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          }),
          headers: {'x-force-update': 'true'},
        ),
      );

      final response = await notes_id.onRequest(context, 'note-1');

      expect(response.statusCode, HttpStatus.ok);

      final body = jsonDecode(await response.body()) as Map<String, dynamic>;
      expect(body['title'], 'Force Updated');
    });

    test('respects the idempotency key', () async {
      repository.create(
        Note(
          id: 'note-1',
          title: 'Original',
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      for (final title in ['First Update', 'Second Update']) {
        when(() => context.request).thenReturn(
          Request.put(
            Uri.parse('http://localhost/notes/note-1'),
            body: jsonEncode({'title': title}),
            headers: {'x-idempotency-key': 'idem-key-1'},
          ),
        );
        expect(
          (await notes_id.onRequest(context, 'note-1')).statusCode,
          HttpStatus.ok,
        );
      }

      expect(repository.get('note-1')!.title, 'First Update');
    });
  });

  group('DELETE /notes/:id', () {
    test('soft deletes the note', () async {
      repository.create(
        Note(id: 'note-1', title: 'Test', updatedAt: DateTime.now().toUtc()),
      );

      when(() => context.request).thenReturn(
        Request.delete(Uri.parse('http://localhost/notes/note-1'), headers: {}),
      );

      final response = await notes_id.onRequest(context, 'note-1');

      expect(response.statusCode, HttpStatus.noContent);
      expect(repository.get('note-1')!.deletedAt, isNotNull);
    });

    test('returns 404 for a non-existent note', () async {
      when(() => context.request).thenReturn(
        Request.delete(Uri.parse('http://localhost/notes/nope'), headers: {}),
      );

      expect(
        (await notes_id.onRequest(context, 'nope')).statusCode,
        HttpStatus.notFound,
      );
    });

    test('a stale ?_baseUpdatedAt is a conflict here too', () async {
      final now = DateTime.utc(2026, 9, 19, 18, 17, 8, 281);
      repository.create(
        Note(id: 'note-1', title: 'Edited elsewhere', updatedAt: now),
      );

      when(() => context.request).thenReturn(
        Request.delete(
          Uri.parse(
            'http://localhost/notes/note-1'
            '?_baseUpdatedAt=${Uri.encodeQueryComponent(now.subtract(const Duration(hours: 1)).toIso8601String())}',
          ),
          headers: {},
        ),
      );

      final response = await notes_id.onRequest(context, 'note-1');

      expect(response.statusCode, HttpStatus.conflict);
      expect(repository.get('note-1')!.deletedAt, isNull);
    });
  });

  test('an unsupported method is rejected', () async {
    when(
      () => context.request,
    ).thenReturn(Request('PATCH', Uri.parse('http://localhost/notes/note-1')));

    expect((await notes_id.onRequest(context, 'note-1')).statusCode, 405);

    when(() => context.request)
        .thenReturn(Request('PATCH', Uri.parse('http://localhost/notes')));

    expect((await notes_index.onRequest(context)).statusCode, 405);
  });
}
