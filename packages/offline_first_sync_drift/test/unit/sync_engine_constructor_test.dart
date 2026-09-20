// What the SyncEngine constructor promises, whatever form it is written in.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

/// A drift database that forgot `with SyncDatabaseMixin`.
class _PlainDatabase extends GeneratedDatabase {
  _PlainDatabase() : super(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

void main() {
  late TestDatabase db;

  setUp(() => db = TestDatabase());
  tearDown(() => db.close());

  SyncableTable<TestItem> table(String kind) => SyncableTable<TestItem>(
    kind: kind,
    table: db.testItems,
    fromJson: TestItem.fromJson,
    toJson: (e) => e.toJson(),
    toInsertable: (e) => e.toInsertable(),
    getId: (e) => e.id,
    getUpdatedAt: (e) => e.updatedAt,
  );

  test('a database without SyncDatabaseMixin is refused with an explanation, '
      'not with a cast error', () async {
    final plain = _PlainDatabase();
    addTearDown(plain.close);

    expect(
      () => SyncEngine<_PlainDatabase>(
        db: plain,
        transport: MockTransport(),
        tables: const [],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('SyncDatabaseMixin'),
        ),
      ),
    );
  });

  test('an empty kind is refused', () {
    expect(
      () => SyncEngine<TestDatabase>(
        db: db,
        transport: MockTransport(),
        tables: [table('  ')],
      ),
      throwsArgumentError,
    );
  });

  test('two tables with the same kind are refused', () {
    expect(
      () => SyncEngine<TestDatabase>(
        db: db,
        transport: MockTransport(),
        tables: [table('items'), table(' items ')],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Duplicate table kind'),
        ),
      ),
    );
  });

  test('an engine without tables syncs to nothing — every time', () async {
    final engine = SyncEngine<TestDatabase>(
      db: db,
      transport: MockTransport(),
      tables: const [],
    );
    addTearDown(engine.dispose);

    await engine.sync(); // the initial full resync
    // The ordinary path merges the per-kind results; with none it used to
    // fail with "Bad state: No element".
    final run = await engine.syncRun();

    expect(run.stats.pushed, 0);
    expect(run.stuckOpsCount, 0);
  });

  test('config defaults to SyncConfig(), and the services are there', () async {
    final engine = SyncEngine<TestDatabase>(
      db: db,
      transport: MockTransport(),
      tables: [table('test_item')],
    );
    addTearDown(engine.dispose);

    expect(engine.outbox, isA<OutboxService>());
    expect(engine.cursors, isA<CursorService>());
    expect(identical(engine.outbox, engine.outbox), isTrue);
    final stats = await engine.sync();
    expect(stats.errors, 0);
  });
}
