// The sync tables are changed with raw SQL. `customStatement` runs the SQL but
// tells drift nothing, so stream queries on those tables were never re-run:
// after a successful sync `watchOutboxCount()` — and an app's own `watch()`
// on the outbox, e.g. for a per-item "synced / not sent yet" label — kept
// their old value until the app restarted.
import 'dart:async';
import 'dart:io';

import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

const _kind = 'test_item';

UpsertOp _op(String id) => UpsertOp(
  opId: 'op-$id',
  kind: _kind,
  id: id,
  localTimestamp: DateTime.utc(2026),
  payloadJson: {'id': id, 'name': 'x'},
);

/// The latest value of a stream once the database has been quiet for a moment.
class _Latest<T> {
  _Latest(Stream<T> stream) {
    _sub = stream.listen((value) => last = value);
  }

  late final StreamSubscription<T> _sub;
  T? last;

  Future<T?> settled() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return last;
  }

  Future<void> cancel() => _sub.cancel();
}

/// Accepts every op.
class _Server implements TransportAdapter {
  @override
  Future<BatchPushResult> push(List<Op> ops) async => BatchPushResult(
    results: [
      for (final op in ops)
        OpPushResult(opId: op.opId, result: const PushSuccess()),
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
  Future<PushResult> forcePush(Op op) async => const PushSuccess();

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

void main() {
  late TestDatabase db;

  setUp(() => db = TestDatabase());
  tearDown(() => db.close());

  group('watchOutboxCount', () {
    late _Latest<int> pending;

    setUp(() => pending = _Latest(db.watchOutboxCount()));
    tearDown(() => pending.cancel());

    test('goes down when ops are acknowledged', () async {
      await db.enqueue(_op('a'));
      await db.enqueue(_op('b'));
      expect(await pending.settled(), 2);

      await db.ackOutbox(['op-a']);

      expect(await pending.settled(), 1);
    });

    test('goes down when old ops are purged', () async {
      await db.enqueue(_op('a'));
      expect(await pending.settled(), 1);

      await db.purgeOutboxOlderThan(DateTime.utc(2030));

      expect(await pending.settled(), 0);
    });

    test('is back at 0 after a sync pushed everything', () async {
      final engine = SyncEngine<TestDatabase>(
        db: db,
        transport: _Server(),
        tables: [
          SyncableTable<TestItem>(
            kind: _kind,
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (e) => e.toJson(),
            toInsertable: (e) => e.toInsertable(),
            getId: (e) => e.id,
            getUpdatedAt: (e) => e.updatedAt,
          ),
        ],
      );
      addTearDown(engine.dispose);
      await db.enqueue(_op('a'));
      await db.enqueue(_op('b'));
      expect(await pending.settled(), 2);

      await engine.sync();

      expect(await pending.settled(), 0);
    });
  });

  group('watchStuckOutboxCount', () {
    late _Latest<int> stuck;

    setUp(() => stuck = _Latest(db.watchStuckOutboxCount(minTryCount: 2)));
    tearDown(() => stuck.cancel());

    test('follows the try count up and down', () async {
      await db.enqueue(_op('a'));
      expect(await stuck.settled(), 0);

      await db.incrementOutboxTryCount(['op-a']);
      await db.incrementOutboxTryCount(['op-a']);
      expect(await stuck.settled(), 1);

      await db.resetOutboxTryCount(['op-a']);
      expect(await stuck.settled(), 0);
    });

    test('follows recordOutboxFailures', () async {
      await db.enqueue(_op('a'));
      await db.recordOutboxFailures({'op-a': 'HTTP error 422'});
      await db.recordOutboxFailures({'op-a': 'HTTP error 422'});

      expect(await stuck.settled(), 1);
    });
  });

  test('a watch() on the outbox table itself sees acknowledgements — what a '
      'per-item sync label is built on', () async {
    final queued = _Latest(
      db.select(db.syncOutbox).watch().map((rows) => rows.length),
    );
    addTearDown(queued.cancel);
    await db.enqueue(_op('a'));
    expect(await queued.settled(), 1);

    await db.ackOutbox(['op-a']);

    expect(await queued.settled(), 0);
  });

  test('outbox meta watchers see metadata being removed', () async {
    final meta = _Latest(
      db.select(db.syncOutboxMeta).watch().map((rows) => rows.length),
    );
    addTearDown(meta.cancel);
    await db.enqueue(_op('a'));
    await db.recordOutboxFailures({'op-a': 'boom'});
    expect(await meta.settled(), 1);

    await db.deleteOutboxMeta(['op-a']);

    expect(await meta.settled(), 0);
  });

  test('cursor watchers see a reset', () async {
    final cursors = _Latest(
      db.select(db.syncCursors).watch().map((rows) => rows.length),
    );
    addTearDown(cursors.cancel);
    await db.setCursor(_kind, Cursor(ts: DateTime.utc(2026), lastId: 'a'));
    expect(await cursors.settled(), 1);

    await db.resetAllCursors({_kind});

    expect(await cursors.settled(), 0);
  });

  test('clearSyncableTables empties what the app is watching', () async {
    final items = _Latest(
      db.select(db.testItems).watch().map((rows) => rows.length),
    );
    addTearDown(items.cancel);
    await db
        .into(db.testItems)
        .insert(
          TestItem(
            id: 'a',
            updatedAt: DateTime.utc(2026),
            name: 'shown in a list',
          ).toInsertable(),
        );
    expect(await items.settled(), 1);

    await db.clearSyncableTables(['test_items']);

    expect(await items.settled(), 0);
  });

  test('no write in lib/ goes through customStatement', () {
    // The root cause, guarded at the source: `customStatement` reports no
    // table, so anything written with it is invisible to stream queries.
    // Writes use `customUpdate(updates: …)` / drift's typed API; only DDL
    // (creating the outbox indexes) may stay a plain statement.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('.drift.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in 'customStatement('.allMatches(source)) {
        final end = (match.start + 240).clamp(0, source.length);
        final call = source.substring(match.start, end);
        if (RegExp(r'\b(INSERT|UPDATE|DELETE)\b').hasMatch(call)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test(
    'clearSyncableTables still clears a table drift does not know',
    () async {
      await db.customStatement('CREATE TABLE side_table (id TEXT)');
      await db.customStatement("INSERT INTO side_table VALUES ('x')");

      await db.clearSyncableTables(['side_table']);

      final rows = await db.customSelect('SELECT * FROM side_table').get();
      expect(rows, isEmpty);
    },
  );
}
