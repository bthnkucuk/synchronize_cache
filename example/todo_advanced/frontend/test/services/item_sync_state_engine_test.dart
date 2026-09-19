// The chip on a card must follow a REAL sync without the store being rebuilt.
//
// `item_sync_state_test.dart` checks the state machine with hand-made queue
// rows. That was not enough: the library used to acknowledge pushed
// operations with raw SQL that drift's stream queries never heard about, so
// in the running app a chip stayed "Only on this device" after a successful
// sync until the page was reloaded — while every unit test was green. These
// tests drive the store through the engine instead.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart'
    hide SyncOutboxCompanion;
import 'package:todo_advanced_frontend/database/database.dart';
import 'package:todo_advanced_frontend/services/item_sync_state.dart';
import 'package:todo_advanced_frontend/sync/note_sync.dart';
import 'package:todo_advanced_frontend/sync/todo_sync.dart';

import '../helpers/test_database.dart';

/// A server that answers every op with whatever [answer] says.
class _Server implements TransportAdapter {
  PushResult Function(Op op)? answer;
  var _clock = DateTime.utc(2026, 9, 20, 12);

  PushResult _accept(Op op) => switch (op) {
    UpsertOp() => PushSuccess(
      serverData: {
        ...op.payloadJson,
        'updated_at': (_clock = _clock.add(
          const Duration(seconds: 1),
        )).toIso8601String(),
      },
    ),
    DeleteOp() => const PushSuccess(),
  };

  @override
  Future<BatchPushResult> push(List<Op> ops) async => BatchPushResult(
    results: [
      for (final op in ops)
        OpPushResult(opId: op.opId, result: (answer ?? _accept)(op)),
    ],
  );

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async => const PullPage(items: []);

  @override
  Future<PushResult> forcePush(Op op) async => _accept(op);

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

void main() {
  late AppDatabase db;
  late _Server server;
  late SyncEngine<AppDatabase> engine;
  late ItemSyncStateStore store;
  const config = SyncConfig();

  setUp(() {
    db = createTestDatabase();
    server = _Server();
    engine = SyncEngine<AppDatabase>(
      db: db,
      transport: server,
      tables: [todoSyncTable(db), noteSyncTable(db)],
      config: config,
    );
    // Started once; never recreated or re-subscribed below.
    store = ItemSyncStateStore(db: db, maxTryCount: config.maxOutboxTryCount)
      ..start();
  });

  tearDown(() async {
    store.dispose();
    engine.dispose();
    await db.close();
  });

  /// Waits until the store reports [expected] for the item, or fails with
  /// what it reported instead.
  Future<void> expectStatus(
    String kind,
    String id,
    ItemSyncStatus expected,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (store.stateFor(kind, id).status != expected) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'the chip of $kind/$id stayed '
          '"${store.stateFor(kind, id).status.name}", expected '
          '"${expected.name}"',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Todo todo(String id, {String title = 'Pay the bill', DateTime? at}) => Todo(
    id: id,
    title: title,
    updatedAt: at ?? DateTime.utc(2026, 9, 20, 10),
  );

  test('a created todo goes from "Only on this device" to "Synced" by '
      'syncing — no restart, no new subscription', () async {
    final writer = SyncWriter<AppDatabase>(db).forTable(todoSyncTable(db));
    await writer.insertAndEnqueue(todo('t1'));
    await expectStatus('todos', 't1', ItemSyncStatus.onlyOnThisDevice);

    final stats = await engine.sync();

    expect(stats.pushed, 1);
    await expectStatus('todos', 't1', ItemSyncStatus.synced);
  });

  test('the same for a note', () async {
    final writer = SyncWriter<AppDatabase>(db).forTable(noteSyncTable(db));
    await writer.insertAndEnqueue(
      Note(
        id: 'n1',
        title: 'Groceries',
        body: 'Milk',
        updatedAt: DateTime.utc(2026, 9, 20, 10),
      ),
    );
    await expectStatus('notes', 'n1', ItemSyncStatus.onlyOnThisDevice);

    await engine.sync();

    await expectStatus('notes', 'n1', ItemSyncStatus.synced);
  });

  test('an edit goes from "Changes not sent yet" to "Synced"', () async {
    final writer = SyncWriter<AppDatabase>(db).forTable(todoSyncTable(db));
    await writer.insertAndEnqueue(todo('t1'));
    await engine.sync();
    await expectStatus('todos', 't1', ItemSyncStatus.synced);
    final synced = await (db.select(
      db.todos,
    )..where((t) => t.id.equals('t1'))).getSingle();

    await writer.replaceAndEnqueue(
      todo('t1', title: 'Pay the bill today', at: DateTime.utc(2026, 9, 21)),
      baseUpdatedAt: synced.updatedAt,
      changedFields: {'title'},
    );
    await expectStatus('todos', 't1', ItemSyncStatus.changesNotSent);

    await engine.sync();

    await expectStatus('todos', 't1', ItemSyncStatus.synced);
  });

  test('a rejected item becomes "Stuck" after the retry budget, and '
      '"Retry" puts it back in the queue', () async {
    final writer = SyncWriter<AppDatabase>(db).forTable(todoSyncTable(db));
    await writer.insertAndEnqueue(todo('poison'));
    server.answer = (_) => PushError(TransportException.httpError(422));

    for (var i = 0; i < config.maxOutboxTryCount; i++) {
      await engine.sync();
    }
    await expectStatus('todos', 'poison', ItemSyncStatus.stuck);

    await engine.retryStuckOperations();
    await expectStatus('todos', 'poison', ItemSyncStatus.onlyOnThisDevice);

    server.answer = null;
    await engine.sync();
    await expectStatus('todos', 'poison', ItemSyncStatus.synced);
  });

  test('an outage never makes an item stuck', () async {
    final writer = SyncWriter<AppDatabase>(db).forTable(todoSyncTable(db));
    await writer.insertAndEnqueue(todo('t1'));
    server.answer = (_) => const PushError(NetworkException('no route'));

    for (var i = 0; i < config.maxOutboxTryCount + 2; i++) {
      await engine.sync();
    }
    // Without the live failure feed of SyncService the persisted last error
    // is what the store has to go on.
    await expectStatus('todos', 't1', ItemSyncStatus.waitingToRetry);

    server.answer = null;
    await engine.sync();
    await expectStatus('todos', 't1', ItemSyncStatus.synced);
  });
}
