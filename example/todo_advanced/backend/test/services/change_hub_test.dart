import 'dart:convert';

import 'package:test/test.dart';
import 'package:todo_advanced_backend/models/note.dart';
import 'package:todo_advanced_backend/models/todo.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/change_hub.dart';

void main() {
  late ChangeHub hub;

  setUp(() => hub = ChangeHub());

  /// A connected client, as the `/ws` route registers it.
  List<String> connect() {
    final frames = <String>[];
    hub.add(frames.add);
    return frames;
  }

  Map<String, dynamic> decode(String frame) =>
      jsonDecode(frame) as Map<String, dynamic>;

  group('ChangeHub', () {
    test('hello counts the client that is connecting', () {
      expect(decode(hub.helloFrame()), {'type': 'hello', 'clients': 0});

      hub.add((_) {});
      expect(decode(hub.helloFrame()), {'type': 'hello', 'clients': 1});

      hub.add((_) {});
      expect(decode(hub.helloFrame()), {'type': 'hello', 'clients': 2});
    });

    test('a change reaches every connected client', () {
      final a = connect();
      final b = connect();

      hub.recordChanged(
        kind: 'todos',
        id: 'todo-1',
        at: DateTime.utc(2026, 9, 19, 12, 30, 15, 250),
      );

      for (final frames in [a, b]) {
        expect(frames, hasLength(1));
        expect(decode(frames.single), {
          'type': 'changed',
          'kind': 'todos',
          'id': 'todo-1',
          'at': '2026-09-19T12:30:15.250Z',
        });
      }
    });

    test('the timestamp is always UTC with a Z', () {
      final frames = connect();

      hub.recordChanged(
        kind: 'notes',
        id: 'note-1',
        at: DateTime.utc(2026, 9, 19, 12).toLocal(),
      );

      expect(decode(frames.single)['at'], '2026-09-19T12:00:00.000Z');
    });

    test('a removed client hears nothing more', () {
      final frames = <String>[];
      final token = hub.add(frames.add);

      hub
        ..remove(token)
        ..recordChanged(kind: 'todos', id: 'todo-1', at: DateTime.utc(2026));

      expect(frames, isEmpty);
      expect(hub.clientCount, 0);
      // Removing twice is what a socket that errors and then closes does.
      expect(() => hub.remove(token), returnsNormally);
    });

    test('one dead socket does not stop the others', () {
      final alive = <String>[];
      hub
        ..add((_) => throw StateError('socket closed'))
        ..add(alive.add);

      hub.recordChanged(kind: 'todos', id: 'todo-1', at: DateTime.utc(2026));

      expect(alive, hasLength(1));
      // The broken one was dropped, so it is not tried again.
      expect(hub.clientCount, 1);
    });
  });

  group('repositories wired to the hub', () {
    test('every write to either kind wakes the clients', () {
      final frames = <String>[];
      hub.add(frames.add);

      final todos = TodoRepository(onChanged: hub.recordChanged);
      final notes = NoteRepository(onChanged: hub.recordChanged);

      todos.create(
        Todo(id: 'todo-1', title: 'Created', updatedAt: DateTime.utc(2026)),
      );
      todos.update(
        'todo-1',
        Todo(id: 'todo-1', title: 'Edited', updatedAt: DateTime.utc(2026, 2)),
        forceUpdate: true,
      );
      todos.delete('todo-1', forceDelete: true);
      notes.create(
        Note(id: 'note-1', title: 'Created', updatedAt: DateTime.utc(2026)),
      );

      expect(frames.map((f) => (decode(f)['kind'], decode(f)['id'])).toList(), [
        ('todos', 'todo-1'),
        ('todos', 'todo-1'),
        ('todos', 'todo-1'),
        ('notes', 'note-1'),
      ]);
    });

    test('a write that changed nothing is not announced', () {
      final frames = <String>[];
      hub.add(frames.add);
      final todos = TodoRepository(onChanged: hub.recordChanged);

      todos.create(
        Todo(id: 'todo-1', title: 'Created', updatedAt: DateTime.utc(2026)),
      );
      frames.clear();

      // A rejected conflict and a delete of something that is not there
      // leave the data alone, so nobody needs to be woken.
      todos.update(
        'todo-1',
        Todo(id: 'todo-1', title: 'Stale', updatedAt: DateTime.utc(2026, 3)),
        baseUpdatedAt: DateTime.utc(2020),
      );
      todos.delete('missing');

      expect(frames, isEmpty);
    });

    test('a repository without a hub simply does not announce', () {
      expect(
        () => TodoRepository().create(
          Todo(id: 'todo-1', title: 'Created', updatedAt: DateTime.utc(2026)),
        ),
        returnsNormally,
      );
    });
  });
}
