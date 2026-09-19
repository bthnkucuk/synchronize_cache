import 'package:flutter_test/flutter_test.dart';
import 'package:search_engine/search_engine.dart';
import 'package:todo_advanced_frontend/database/database.dart';
import 'package:todo_advanced_frontend/repositories/note_repository.dart';
import 'package:todo_advanced_frontend/repositories/todo_repository.dart';
import 'package:todo_advanced_frontend/search/app_search.dart';
import 'package:todo_advanced_frontend/sync/note_sync.dart';
import 'package:todo_advanced_frontend/sync/todo_sync.dart';

import '../helpers/test_database.dart';

/// Index → query → delete, over both kinds, with Turkish folding.
void main() {
  late AppDatabase db;
  late AppSearch search;
  late TodoRepository todos;
  late NoteRepository notes;

  setUp(() async {
    db = createTestDatabase();
    search = AppSearch(db);
    todos = TodoRepository(db, todoSyncTable(db));
    notes = NoteRepository(db, noteSyncTable(db));
    await search.start();
  });

  tearDown(() async {
    await search.stop();
    await db.close();
  });

  /// Polls until [query] returns something, or gives up.
  ///
  /// The indexer is debounced and runs off drift's table-update stream, so
  /// "eventually" is the honest contract here.
  Future<List<GlobalSearch>> hits(
    String query, {
    Set<String> kinds = const {},
    int atLeast = 1,
    bool expectEmpty = false,
  }) async {
    for (var attempt = 0; attempt < 80; attempt++) {
      final found = await search.watch(query, kinds: kinds).first;
      if (expectEmpty ? found.isEmpty : found.length >= atLeast) return found;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return search.watch(query, kinds: kinds).first;
  }

  test('a todo becomes searchable by title and description', () async {
    await todos.create(title: 'Buy milk', description: 'from the corner shop');

    expect((await hits('milk')).single.kind, 'todos');
    expect((await hits('corner')).single.kind, 'todos');
  });

  test('a note becomes searchable by title and body', () async {
    await notes.create(title: 'Groceries', body: 'bread and butter');

    expect((await hits('Groceries')).single.kind, 'notes');
    expect((await hits('butter')).single.kind, 'notes');
  });

  test('one query reaches both kinds, and the filter narrows it', () async {
    await todos.create(title: 'Reservation for dinner');
    await notes.create(title: 'Reservation code');

    final all = await hits('reservation', atLeast: 2);
    expect(all.map((h) => h.kind).toSet(), {'todos', 'notes'});

    final onlyNotes = await hits('reservation', kinds: {'notes'});
    expect(onlyNotes.map((h) => h.kind).toSet(), {'notes'});
  });

  test('Turkish letters fold both ways', () async {
    await notes.create(title: 'Işık Raporu', body: 'çalışma');

    for (final query in ['ışık', 'isik', 'IŞIK', 'Isik']) {
      final found = await hits(query);
      expect(
        found.single.title,
        'Işık Raporu',
        reason: '"$query" should find "Işık Raporu"',
      );
    }
    expect((await hits('calisma')).single.title, 'Işık Raporu');
  });

  test('a deleted row disappears from the results', () async {
    final note = await notes.create(title: 'Temporary note');
    expect(await hits('Temporary'), isNotEmpty);

    await notes.delete(note);

    expect(await hits('Temporary', expectEmpty: true), isEmpty);
  });

  test('a row written the way a pull writes it becomes searchable', () async {
    // No outbox, no repository — exactly what `PullService` does when another
    // device's row arrives.
    await db
        .into(db.notes)
        .insertOnConflictUpdate(
          Note(
            id: 'from-another-device',
            title: 'Arrived by pull',
            body: 'nobody typed this here',
            updatedAt: DateTime.now().toUtc(),
          ).toInsertable(),
        );

    expect((await hits('Arrived')).single.originalId, 'from-another-device');
  });

  test('the index count grows with what is in it', () async {
    expect(await search.watchIndexedCount().first, 0);

    await todos.create(title: 'Counted todo');
    await hits('Counted');

    expect(await search.watchIndexedCount().first, 1);
  });

  test('a query shorter than the trigram minimum matches nothing', () async {
    await todos.create(title: 'abcdef');
    await hits('abcdef');

    expect(await search.watch('ab').first, isEmpty);
  });

  group('highlightSpans', () {
    test('splits the marked runs out of a highlighted field', () {
      final spans = highlightSpans(
        'Buy ${highlightStart}milk$highlightEnd today',
      );

      expect(spans, [('Buy ', false), ('milk', true), (' today', false)]);
    });

    test('text without markers comes back in one piece', () {
      expect(highlightSpans('plain'), [('plain', false)]);
    });
  });

  group('foldTurkish', () {
    test('folds the letters the trigram tokenizer cannot', () {
      expect(foldTurkish('IŞIK'), 'isik');
      expect(foldTurkish('ışık'), 'isik');
      expect(foldTurkish('İstanbul'), 'istanbul');
      expect(foldTurkish('ÇÖĞÜŞ'), 'cogus');
    });
  });
}
