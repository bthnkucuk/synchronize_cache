import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_advanced_frontend/database/database.dart';

const _dateTimeColumns = [
  'updated_at',
  'deleted_at',
  'deleted_at_local',
  'due_date',
];

/// The schema as version 1 created it: identical to today's, except that the
/// DateTime columns of `todos` were INTEGER unix seconds.
Future<List<String>> _schemaV1() async {
  final current = AppDatabase(NativeDatabase.memory());
  final rows = await current
      .customSelect('SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL')
      .get();
  await current.close();

  return [
    for (final row in rows)
      if (row.read<String>('name') == 'todos')
        _dateTimeColumns.fold(
          row.read<String>('sql'),
          (sql, column) =>
              sql.replaceFirst(RegExp('"$column" TEXT'), '"$column" INTEGER'),
        )
      else
        row.read<String>('sql'),
  ];
}

void main() {
  test(
    'v1 → v2 converts unix-second DateTime columns to ISO-8601 text',
    () async {
      final statements = await _schemaV1();
      expect(
        statements.where((sql) => sql.contains('"updated_at" INTEGER')),
        hasLength(1),
        reason: 'the v1 replica must really use INTEGER DateTime columns',
      );

      final updatedAt = DateTime.utc(2026, 9, 19, 18, 17, 8);
      final dueDate = DateTime.utc(2026, 10, 1, 9, 30);

      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            statements.forEach(raw.execute);
            raw
              ..execute(
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
              )
              ..execute('PRAGMA user_version = 1');
          },
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
}
