import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_advanced_frontend/database/database.dart';

const _dateTimeColumns = [
  'updated_at',
  'deleted_at',
  'deleted_at_local',
  'due_date',
];

/// Everything schema version 3 added. A replica of an older database must not
/// contain any of it, or `onUpgrade` would try to create what is there.
const _addedInV3 = {
  'notes',
  'app_settings',
  'pending_search_items',
  'search_lookup',
  'search_index_cursors',
  'idx_pending_search_items_user_id',
  'idx_search_lookup_user_kind',
};

/// The schema as version 2 created it: today's, minus what v3 added.
Future<List<String>> _schemaV2() async {
  final current = AppDatabase(NativeDatabase.memory());
  final rows = await current
      .customSelect('SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL')
      .get();
  await current.close();

  return [
    for (final row in rows)
      if (!_addedInV3.contains(row.read<String>('name')) &&
          // The FTS5 table and the shadow tables SQLite creates for it.
          !row.read<String>('name').startsWith('global_search'))
        row.read<String>('sql'),
  ];
}

/// The schema as version 1 created it: v2's, except that the DateTime columns
/// of `todos` were INTEGER unix seconds.
Future<List<String>> _schemaV1() async {
  return [
    for (final sql in await _schemaV2())
      if (sql.contains('CREATE TABLE IF NOT EXISTS "todos"') ||
          sql.contains('CREATE TABLE "todos"'))
        _dateTimeColumns.fold(
          sql,
          (statement, column) => statement.replaceFirst(
            RegExp('"$column" TEXT'),
            '"$column" INTEGER',
          ),
        )
      else
        sql,
  ];
}

/// Opens a database on top of [statements], pretending it was written by
/// schema version [userVersion].
AppDatabase _databaseFrom(
  List<String> statements,
  int userVersion, {
  void Function(dynamic raw)? seed,
}) {
  return AppDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        statements.forEach(raw.execute);
        seed?.call(raw);
        raw.execute('PRAGMA user_version = $userVersion');
      },
    ),
  );
}

void main() {
  test(
    'v1 → v3 converts unix-second DateTime columns to ISO-8601 text',
    () async {
      final statements = await _schemaV1();
      expect(
        statements.where((sql) => sql.contains('"updated_at" INTEGER')),
        hasLength(1),
        reason: 'the v1 replica must really use INTEGER DateTime columns',
      );

      final updatedAt = DateTime.utc(2026, 9, 19, 18, 17, 8);
      final dueDate = DateTime.utc(2026, 10, 1, 9, 30);

      final db = _databaseFrom(
        statements,
        1,
        seed: (raw) => raw.execute(
          'INSERT INTO todos '
          '(id, title, description, completed, priority, due_date, '
          'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            'todo-1',
            'Written by v1',
            null,
            0,
            2,
            dueDate.millisecondsSinceEpoch ~/ 1000,
            updatedAt.millisecondsSinceEpoch ~/ 1000,
          ],
        ),
      );
      addTearDown(db.close);

      final todo = await db.select(db.todos).getSingle();

      expect(todo.title, 'Written by v1');
      expect(todo.updatedAt.isAtSameMomentAs(updatedAt), isTrue);
      expect(todo.dueDate!.isAtSameMomentAs(dueDate), isTrue);
      expect(todo.deletedAt, isNull);

      final stored = await db
          .customSelect('SELECT typeof(updated_at) AS t, updated_at FROM todos')
          .getSingle();
      expect(stored.read<String>('t'), 'text');
      expect(stored.read<String>('updated_at'), '2026-09-19T18:17:08.000Z');
    },
  );

  test('a DateTime written by v2 keeps its milliseconds', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final precise = DateTime.utc(2026, 9, 19, 18, 17, 8, 281);

    await db
        .into(db.todos)
        .insert(
          Todo(id: 'todo-1', title: 'T', updatedAt: precise).toInsertable(),
        );

    final todo = await db.select(db.todos).getSingle();
    expect(todo.updatedAt, precise);
  });

  group('v2 → v3', () {
    // Every browser that already ran this app holds a v2 database. If this
    // upgrade throws, the app does not start for them at all.
    test(
      'creates notes, settings and the whole search index in place',
      () async {
        final statements = await _schemaV2();
        expect(
          statements.where((sql) => sql.contains('"notes"')),
          isEmpty,
          reason: 'the v2 replica must not already contain v3 tables',
        );

        final updatedAt = DateTime.utc(2026, 9, 19, 18, 17, 8, 281);
        final db = _databaseFrom(
          statements,
          2,
          seed: (raw) => raw.execute(
            'INSERT INTO todos (id, title, completed, priority, updated_at) '
            'VALUES (?, ?, ?, ?, ?)',
            ['todo-1', 'Written by v2', 0, 2, updatedAt.toIso8601String()],
          ),
        );
        addTearDown(db.close);

        // The old data survives untouched.
        final todo = await db.select(db.todos).getSingle();
        expect(todo.title, 'Written by v2');
        expect(todo.updatedAt, updatedAt);

        // The new tables are usable.
        await db
            .into(db.notes)
            .insert(
              Note(
                id: 'note-1',
                title: 'Written after the upgrade',
                updatedAt: updatedAt,
              ).toInsertable(),
            );
        expect(
          (await db.select(db.notes).getSingle()).title,
          'Written after the upgrade',
        );

        await db
            .into(db.appSettings)
            .insert(AppSettingsCompanion.insert(key: 'k', value: 'v'));
        expect((await db.select(db.appSettings).getSingle()).value, 'v');

        expect(await db.select(db.pendingSearchItems).get(), isEmpty);
        expect(await db.select(db.searchLookup).get(), isEmpty);
        expect(await db.select(db.searchIndexCursors).get(), isEmpty);

        // The FTS5 virtual table, which a plain createTable cannot make.
        final fts = await db
            .customSelect('SELECT count(*) AS c FROM global_search')
            .getSingle();
        expect(fts.read<int>('c'), 0);
      },
    );

    test('leaves the database at the current schema version', () async {
      final db = _databaseFrom(await _schemaV2(), 2);
      addTearDown(db.close);

      // Force the migration to run.
      await db.select(db.todos).get();

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), db.schemaVersion);
      expect(db.schemaVersion, 3);
    });
  });
}
