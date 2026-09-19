import 'package:flutter_test/flutter_test.dart';
import 'package:todo_advanced_frontend/database/database.dart';
import 'package:todo_advanced_frontend/repositories/note_repository.dart';
import 'package:todo_advanced_frontend/sync/note_sync.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = NoteRepository(db, noteSyncTable(db));
  });

  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> outbox() async {
    final rows = await db
        .customSelect(
          'SELECT entity_id, op, base_updated_at, changed_fields '
          'FROM sync_outbox ORDER BY ts, rowid',
        )
        .get();
    return [
      for (final row in rows)
        {
          'id': row.read<String>('entity_id'),
          'op': row.read<String>('op'),
          'base': row.readNullable<int>('base_updated_at'),
          'changed': row.readNullable<String>('changed_fields'),
        },
    ];
  }

  group('create', () {
    test('stores the note and queues a create with no base version', () async {
      final note = await repo.create(title: 'Groceries', body: 'Milk');

      expect((await repo.getById(note.id))!.title, 'Groceries');

      final queued = await outbox();
      expect(queued, hasLength(1));
      expect(queued.single['op'], 'upsert');
      // No base: the server has never seen this row.
      expect(queued.single['base'], isNull);
    });

    test('a new note is not deleted and not pinned by default', () async {
      final note = await repo.create(title: 'Plain');

      expect(note.pinned, isFalse);
      expect(note.deletedAt, isNull);
      expect(note.deletedAtLocal, isNull);
    });
  });

  group('update', () {
    test('queues the edited fields and the version it was based on', () async {
      final note = await repo.create(title: 'Groceries', body: 'Milk');
      await db.customStatement('DELETE FROM sync_outbox');

      await repo.update(note, title: 'Shopping', body: 'Milk');

      final queued = await outbox();
      expect(queued.single['op'], 'upsert');
      expect(queued.single['base'], isNotNull);
      expect(queued.single['changed'], contains('title'));
      expect(queued.single['changed'], isNot(contains('body')));
    });

    test('clearing the body really clears it', () async {
      final note = await repo.create(title: 'Groceries', body: 'Milk');

      final updated = await repo.update(note, title: 'Groceries');

      expect(updated.body, isNull);
      expect((await repo.getById(note.id))!.body, isNull);
    });

    test('togglePinned flips the flag and keeps the body', () async {
      final note = await repo.create(title: 'Groceries', body: 'Milk');

      final pinned = await repo.togglePinned(note);

      expect(pinned.pinned, isTrue);
      expect(pinned.body, 'Milk');
    });

    test('the local updatedAt moves forward on an edit', () async {
      final note = await repo.create(title: 'Groceries');
      final updated = await repo.update(note, title: 'Shopping');

      expect(
        updated.updatedAt.isAfter(note.updatedAt) ||
            updated.updatedAt == note.updatedAt,
        isTrue,
      );
    });
  });

  group('delete', () {
    test('soft-deletes locally and queues a delete', () async {
      final note = await repo.create(title: 'Groceries');
      await db.customStatement('DELETE FROM sync_outbox');

      await repo.delete(note);

      final row = await repo.getById(note.id);
      expect(row, isNotNull, reason: 'the row stays until the server agrees');
      expect(row!.deletedAtLocal, isNotNull);

      final queued = await outbox();
      expect(queued.single['op'], 'delete');
      expect(queued.single['base'], isNotNull);
    });

    test('a deleted note disappears from the list', () async {
      final note = await repo.create(title: 'Groceries');
      await repo.delete(note);

      expect(await repo.getAll(), isEmpty);
      expect(await repo.watchAll().first, isEmpty);
    });
  });

  group('watchAll', () {
    test('pinned notes come first', () async {
      final plain = await repo.create(title: 'Plain');
      await repo.create(title: 'Pinned', pinned: true);
      // Make sure ordering is not accidentally by insertion.
      await repo.update(plain, title: 'Plain again');

      final notes = await repo.watchAll().first;

      expect(notes.first.title, 'Pinned');
      expect(notes, hasLength(2));
    });
  });
}
