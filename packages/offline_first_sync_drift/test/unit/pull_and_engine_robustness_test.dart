// Things a server or a bad connection must not be able to do to a client:
//  * one row the app cannot read stopped a whole kind from syncing, forever;
//  * an interrupted full resync started over from zero, every time;
//  * a push-only sync pulled every table when the periodic resync was due;
//  * dropping a stuck op left its effect in the local row, which then looked
//    synced while it differed from the server;
//  * one conflict that could not be resolved failed the whole sync of that
//    kind, every time, and lost the resolutions made before it;
//  * a full resync sent operations a second time while a push of theirs was
//    still under way.
import 'dart:async';

import 'package:drift/drift.dart' show Insertable, Value;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

import '../fixtures/test_database.dart';

const _kind = 'test_item';

Map<String, Object?> _row(String id, int second, {Object? name = 'ok'}) => {
  'id': id,
  'name': name,
  'updated_at': DateTime.utc(2026, 5, 1, 12, 0, second).toIso8601String(),
};

/// Serves [rows] with keyset paging, the way docs/backend-transport.md asks.
class _Server implements TransportAdapter {
  List<Map<String, Object?>> rows = [];
  final List<DateTime> pulledSince = [];

  /// 1-based numbers of the pull requests that fail like a dropped connection.
  final Set<int> failingPulls = {};
  var _pullCalls = 0;

  /// Replaces the keyset paging below when a test needs a page no honest
  /// server would produce.
  PullPage Function(DateTime since, String? afterId)? pullOverride;

  PushResult Function(Op op) answer = (_) => const PushSuccess();
  FetchResult Function(String id) onFetch = (_) => const FetchNotFound();
  final List<String> fetched = [];

  /// Runs while a `fetch` is on its way, before it answers.
  Future<void> Function(String id)? duringFetch;

  /// Every `push` call, as the op ids it carried.
  final List<List<String>> pushes = [];

  /// When set, `push` does not answer before this completes.
  Completer<void>? pushGate;
  var pushStarted = Completer<void>();
  var pushesInFlight = 0;
  var maxPushesInFlight = 0;

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    pulledSince.add(updatedSince);
    if (failingPulls.contains(++_pullCalls)) {
      throw const NetworkException('connection lost');
    }
    final override = pullOverride;
    if (override != null) return override(updatedSince.toUtc(), afterId);
    final since = updatedSince.toUtc();
    final matching = rows.where((row) {
      final at = DateTime.parse(row['updated_at']! as String);
      return at.isAfter(since) ||
          (at.isAtSameMomentAs(since) &&
              (row['id']! as String).compareTo(afterId ?? '') > 0);
    }).toList();
    return PullPage(items: matching.take(pageSize).toList());
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    pushes.add([for (final op in ops) op.opId]);
    pushesInFlight++;
    if (pushesInFlight > maxPushesInFlight) {
      maxPushesInFlight = pushesInFlight;
    }
    if (!pushStarted.isCompleted) pushStarted.complete();
    try {
      await pushGate?.future;
      return BatchPushResult(
        results: [
          for (final op in ops) OpPushResult(opId: op.opId, result: answer(op)),
        ],
      );
    } finally {
      pushesInFlight--;
    }
  }

  @override
  Future<PushResult> forcePush(Op op) async => const PushSuccess();

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async {
    fetched.add(id);
    await duringFetch?.call(id);
    return onFetch(id);
  }

  @override
  Future<bool> health() async => true;
}

void main() {
  late TestDatabase db;
  late _Server server;
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  setUp(() {
    db = TestDatabase();
    server = _Server();
  });

  tearDown(() => db.close());

  SyncEngine<TestDatabase> engine({
    SyncConfig config = const SyncConfig(),
    Insertable<TestItem> Function(TestItem)? toInsertable,
  }) {
    final engine = SyncEngine<TestDatabase>(
      db: db,
      transport: server,
      tables: [
        SyncableTable<TestItem>(
          kind: _kind,
          table: db.testItems,
          fromJson: TestItem.fromJson,
          toJson: (e) => e.toJson(),
          toInsertable: toInsertable ?? (e) => e.toInsertable(),
          getId: (e) => e.id,
          getUpdatedAt: (e) => e.updatedAt,
        ),
      ],
      config: config,
    );
    addTearDown(engine.dispose);
    return engine;
  }

  Future<List<String>> localIds() async =>
      [for (final item in await db.select(db.testItems).get()) item.id]..sort();

  group('a pulled row the app cannot store', () {
    test('is skipped and reported; the rows around it arrive and the cursor '
        'moves past it', () async {
      // `name` is required: TestItem.fromJson throws for `b`.
      server.rows = [_row('a', 1), _row('b', 2, name: null), _row('c', 3)];
      final e = engine();
      final errors = <SyncErrorEvent>[];
      final sub = e.events
          .where((ev) => ev is SyncErrorEvent)
          .cast<SyncErrorEvent>()
          .listen(errors.add);
      addTearDown(sub.cancel);

      await e.sync();
      await pumpEventQueue();

      expect(await localIds(), ['a', 'c']);
      expect((await db.getCursor(_kind))!.lastId, 'c');
      expect(
        errors.single.error,
        isA<ParseException>().having(
          (x) => x.message,
          'message',
          contains('b'),
        ),
      );

      // The next sync is not stuck on it, and does not ask for it again.
      server.pulledSince.clear();
      await e.sync();
      expect(server.pulledSince.single, DateTime.utc(2026, 5, 1, 12, 0, 3));
    });

    test(
      'that the DATABASE rejects does not take the page down either',
      () async {
        server.rows = [_row('a', 1), _row('b', 2), _row('c', 3)];
        // `b` comes out of the app's mapper without its required columns.
        final e = engine(
          toInsertable: (item) => item.id == 'b'
              ? TestItemsCompanion(id: Value(item.id))
              : item.toInsertable(),
        );

        await e.sync();

        expect(await localIds(), ['a', 'c']);
        expect((await db.getCursor(_kind))!.lastId, 'c');
      },
    );

    test(
      'that is not even a JSON object does not take the page down',
      () async {
        // What RestTransport hands over for `"items": [{…}, null, {…}]`: a lazy
        // cast that throws when the bad element is reached.
        server.pullOverride = (since, _) => since == epoch
            ? PullPage(
                items: <Object?>[
                  _row('a', 1),
                  null,
                  _row('c', 3),
                ].cast<Map<String, Object?>>(),
              )
            : const PullPage(items: []);
        final e = engine();
        final errors = <SyncErrorEvent>[];
        final sub = e.events
            .where((ev) => ev is SyncErrorEvent)
            .cast<SyncErrorEvent>()
            .listen(errors.add);
        addTearDown(sub.cancel);

        await e.sync();
        await pumpEventQueue();

        expect(await localIds(), ['a', 'c']);
        expect((await db.getCursor(_kind))!.lastId, 'c');
        expect(errors.single.error, isA<ParseException>());
      },
    );

    test('as the LAST row of a page, with no version to move the cursor to: '
        'the cursor stops at the row before it', () async {
      final bad = <String, Object?>{'id': 'b', 'name': null};
      server.pullOverride = (since, _) => since == epoch
          ? PullPage(items: [_row('a', 1), bad])
          : PullPage(items: [bad]);
      final e = engine();

      await e.sync();

      expect(await localIds(), ['a']);
      expect((await db.getCursor(_kind))!.lastId, 'a');

      // Later syncs are not stuck on it either, and new rows still arrive.
      await e.sync();
      server.pullOverride = (_, _) => PullPage(items: [bad, _row('c', 3)]);
      await e.sync();
      expect(await localIds(), ['a', 'c']);
    });

    test('whose version is not a timestamp at all is skipped the same '
        'way', () async {
      final bad = <String, Object?>{
        'id': 'b',
        'name': 'x',
        'updated_at': 'yesterday',
      };
      server.pullOverride = (since, _) => since == epoch
          ? PullPage(items: [_row('a', 1), bad])
          : const PullPage(items: []);
      final e = engine();

      await e.sync();

      expect(await localIds(), ['a']);
      expect((await db.getCursor(_kind))!.lastId, 'a');
    });

    test('a full page of such rows does not make the pull spin', () async {
      final bad = <String, Object?>{'id': 'b', 'name': null};
      var pulls = 0;
      server.pullOverride = (_, _) {
        pulls++;
        return PullPage(items: [bad, bad]);
      };
      final e = engine(config: const SyncConfig(pageSize: 2));

      await e.sync().timeout(const Duration(seconds: 5));

      expect(pulls, 1);
    });

    test('still fails the pull with skipInvalidPulledRows: false', () async {
      server.rows = [_row('a', 1), _row('b', 2, name: null)];
      final e = engine(config: const SyncConfig(skipInvalidPulledRows: false));

      await expectLater(e.sync(), throwsA(isA<SyncException>()));
      expect(await db.getCursor(_kind), isNull);
    });
  });

  group('an interrupted full resync', () {
    setUp(() {
      server.rows = [for (var i = 1; i <= 6; i++) _row('r$i', i)];
    });

    test(
      'continues from the cursor it reached instead of starting over',
      () async {
        final e = engine(config: const SyncConfig(pageSize: 2));
        server.failingPulls.add(2); // page 1 arrives, page 2 does not

        await expectLater(e.fullResync(), throwsA(isA<SyncException>()));
        expect(await localIds(), ['r1', 'r2']);

        server.pulledSince.clear();
        await e.sync();

        expect(
          server.pulledSince.first,
          DateTime.utc(2026, 5, 1, 12, 0, 2),
          reason:
              'the first request after the interruption asks for what '
              'follows r2, not for everything since the epoch',
        );
        expect(await localIds(), ['r1', 'r2', 'r3', 'r4', 'r5', 'r6']);

        // Finished: the next sync is an ordinary incremental one.
        server.pulledSince.clear();
        await e.sync();
        expect(server.pulledSince.single, DateTime.utc(2026, 5, 1, 12, 0, 6));
      },
    );

    test('is finished by the next sync even when the last complete one is '
        'recent — the marker does not outlive the work', () async {
      final e = engine(config: const SyncConfig(pageSize: 2));
      await e.sync(); // complete: a full resync is not due for days

      server.failingPulls.add(server.pulledSince.length + 2);
      await expectLater(e.fullResync(), throwsA(isA<SyncException>()));
      expect(await db.getCursor(CursorKinds.fullResyncInProgress), isNotNull);

      await e.sync();

      expect(await localIds(), hasLength(6));
      // Left behind, it would turn the next scheduled full resync into an
      // ordinary incremental pull: that one would "continue" a resync that
      // was finished long ago instead of starting from zero.
      expect(await db.getCursor(CursorKinds.fullResyncInProgress), isNull);
    });

    test('fullResync(clearData: true) is a clean slate on purpose', () async {
      final e = engine(config: const SyncConfig(pageSize: 2));
      server.failingPulls.add(2);
      await expectLater(e.fullResync(), throwsA(isA<SyncException>()));

      server.pulledSince.clear();
      await e.fullResync(clearData: true);

      expect(server.pulledSince.first, epoch);
      expect(await localIds(), hasLength(6));
    });
  });

  group('the periodic full resync', () {
    test('is not set off by a push-only sync', () async {
      server.rows = [_row('a', 1)];
      final e = engine(); // a new database: a full resync is due

      await e.sync(pushKinds: {_kind}, pullKinds: const {});

      expect(server.pulledSince, isEmpty);
      expect(await localIds(), isEmpty);

      await e.sync(); // the first sync that pulls does it
      expect(server.pulledSince.first, epoch);
      expect(await localIds(), ['a']);
    });
  });

  group('dropping a stuck operation', () {
    const config = SyncConfig();

    /// A synced row, edited locally; the server rejects the edit for good.
    Future<SyncEngine<TestDatabase>> stuckEdit() async {
      final e = engine();
      await e.sync();
      await db
          .into(db.testItems)
          .insert(
            TestItemsCompanion.insert(
              id: 'a',
              name: 'the edit the user gave up on',
              updatedAt: DateTime.utc(2026, 5, 3),
            ),
          );
      await db.enqueue(
        UpsertOp(
          opId: 'edit-a',
          kind: _kind,
          id: 'a',
          localTimestamp: DateTime.utc(2026, 5, 3),
          payloadJson: const {
            'id': 'a',
            'name': 'the edit the user gave up on',
          },
          baseUpdatedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      server.answer = (_) => PushError(TransportException.httpError(422));
      for (var i = 0; i < config.maxOutboxTryCount; i++) {
        await e.sync(pullKinds: const {});
      }
      expect(await e.getStuckOperations(), hasLength(1));
      return e;
    }

    test('restores the row from the server', () async {
      final e = await stuckEdit();
      server.onFetch = (_) => FetchSuccess(data: _row('a', 1, name: 'server'));

      await e.dropStuckOperations();

      expect(await db.takeOutbox(limit: 10), isEmpty);
      expect((await db.select(db.testItems).getSingle()).name, 'server');
    });

    test('removes a row the server never had (a discarded creation)', () async {
      final e = await stuckEdit();
      server.onFetch = (_) => const FetchNotFound();

      await e.dropStuckOperations();

      expect(await localIds(), isEmpty);
    });

    test('keeps the op when the server cannot be asked', () async {
      final e = await stuckEdit();
      server.onFetch = (_) =>
          const FetchError(NetworkException('no connection'));

      await e.dropStuckOperations();

      // Dropping it now would leave a row that differs from the server and
      // nothing that says so.
      expect(await e.getStuckOperations(), hasLength(1));
      expect(
        (await db.select(db.testItems).getSingle()).name,
        'the edit the user gave up on',
      );
    });

    test('drops it as asked when the server has a row this app cannot read; '
        'the local row is left alone and the app is told', () async {
      final e = await stuckEdit();
      server.onFetch = (_) => FetchSuccess(data: _row('a', 1, name: null));
      final errors = <SyncErrorEvent>[];
      final sub = e.events
          .where((ev) => ev is SyncErrorEvent)
          .cast<SyncErrorEvent>()
          .listen(errors.add);
      addTearDown(sub.cancel);

      await e.dropStuckOperations();
      await pumpEventQueue();

      expect(await db.takeOutbox(limit: 10), isEmpty);
      expect(
        (await db.select(db.testItems).getSingle()).name,
        'the edit the user gave up on',
      );
      expect(errors.single.error, isA<ParseException>());
    });

    test('one row that cannot be restored does not keep the others', () async {
      final e = await stuckEdit();
      // A second stuck edit, of another row.
      await db
          .into(db.testItems)
          .insert(
            TestItemsCompanion.insert(
              id: 'z',
              name: 'second edit',
              updatedAt: DateTime.utc(2026, 5, 3),
            ),
          );
      await db.enqueue(
        UpsertOp(
          opId: 'edit-z',
          kind: _kind,
          id: 'z',
          localTimestamp: DateTime.utc(2026, 5, 3, 1),
          payloadJson: const {'id': 'z', 'name': 'second edit'},
          baseUpdatedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      for (var i = 0; i < config.maxOutboxTryCount; i++) {
        await e.sync(pullKinds: const {});
      }
      expect(await e.getStuckOperations(), hasLength(2));
      server.onFetch = (id) => id == 'a'
          ? FetchSuccess(data: _row('a', 1, name: 'server'))
          : const FetchError(NetworkException('no connection'));

      await e.dropStuckOperations();

      expect((await e.getStuckOperations()).map((op) => op.opId), ['edit-z']);
      final rows = {
        for (final item in await db.select(db.testItems).get())
          item.id: item.name,
      };
      expect(rows, {'a': 'server', 'z': 'second edit'});
    });

    test(
      'an edit made while the server is being asked keeps the row',
      () async {
        final e = await stuckEdit();
        server
          ..onFetch = ((_) => FetchSuccess(data: _row('a', 1, name: 'server')))
          ..duringFetch = (_) async {
            await db
                .into(db.testItems)
                .insertOnConflictUpdate(
                  TestItemsCompanion.insert(
                    id: 'a',
                    name: 'typed meanwhile',
                    updatedAt: DateTime.utc(2026, 5, 5),
                  ),
                );
            await db.enqueue(
              UpsertOp(
                opId: 'edit-a-3',
                kind: _kind,
                id: 'a',
                localTimestamp: DateTime.utc(2026, 5, 5),
                payloadJson: const {'id': 'a', 'name': 'typed meanwhile'},
                baseUpdatedAt: DateTime.utc(2026, 5, 1),
              ),
            );
          };

        await e.dropStuckOperations();

        expect((await db.takeOutbox(limit: 10)).map((op) => op.opId), [
          'edit-a-3',
        ]);
        expect(
          (await db.select(db.testItems).getSingle()).name,
          'typed meanwhile',
        );
      },
    );

    test('leaves the row to a newer edit that is still queued', () async {
      final e = await stuckEdit();
      await db.enqueue(
        UpsertOp(
          opId: 'edit-a-2',
          kind: _kind,
          id: 'a',
          localTimestamp: DateTime.utc(2026, 5, 4),
          payloadJson: const {'id': 'a', 'name': 'newer'},
          baseUpdatedAt: DateTime.utc(2026, 5, 1),
        ),
      );

      await e.dropStuckOperations();

      expect(server.fetched, isEmpty);
      expect((await db.takeOutbox(limit: 10)).map((op) => op.opId), [
        'edit-a-2',
      ]);
    });
  });

  test(
    'skipConflictingOps: the row becomes what the server reported',
    () async {
      final e = engine(
        config: SyncConfig(
          skipConflictingOps: true,
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (_) async => const DeferResolution(),
        ),
      );
      await e.sync();
      await db
          .into(db.testItems)
          .insert(
            TestItemsCompanion.insert(
              id: 'a',
              name: 'local edit',
              updatedAt: DateTime.utc(2026, 5, 3),
            ),
          );
      await db.enqueue(
        UpsertOp(
          opId: 'edit-a',
          kind: _kind,
          id: 'a',
          localTimestamp: DateTime.utc(2026, 5, 3),
          payloadJson: const {'id': 'a', 'name': 'local edit'},
          baseUpdatedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      server.answer = (_) => PushConflict(
        serverData: _row('a', 9, name: 'theirs'),
        serverTimestamp: DateTime.utc(2026, 5, 1, 12, 0, 9),
      );

      await e.sync(pullKinds: const {});

      expect(await db.takeOutbox(limit: 10), isEmpty);
      expect((await db.select(db.testItems).getSingle()).name, 'theirs');
    },
  );

  group('a conflict that cannot be resolved', () {
    /// Two synced rows, both edited locally; the server reports a conflict
    /// for each. What it says about `b` is not a record this app can read.
    Future<SyncEngine<TestDatabase>> twoConflicts({
      SyncConfig config = const SyncConfig(
        conflictStrategy: ConflictStrategy.serverWins,
      ),
    }) async {
      final e = engine(config: config);
      await e.sync();
      for (final id in ['a', 'b']) {
        await db
            .into(db.testItems)
            .insert(
              TestItemsCompanion.insert(
                id: id,
                name: 'local $id',
                updatedAt: DateTime.utc(2026, 5, 3),
              ),
            );
        await db.enqueue(
          UpsertOp(
            opId: 'edit-$id',
            kind: _kind,
            id: id,
            localTimestamp: DateTime.utc(2026, 5, 3, 0, 0, id == 'a' ? 1 : 2),
            payloadJson: {'id': id, 'name': 'local $id'},
            baseUpdatedAt: DateTime.utc(2026, 5, 1),
          ),
        );
      }
      server.answer = (op) => PushConflict(
        serverData: _row(op.id, 9, name: op.id == 'b' ? null : 'theirs'),
        serverTimestamp: DateTime.utc(2026, 5, 1, 12, 0, 9),
      );
      return e;
    }

    test('does not fail the sync, and does not undo the conflicts that WERE '
        'resolved next to it', () async {
      final e = await twoConflicts();
      final failed = <OperationFailedEvent>[];
      final sub = e.events
          .where((ev) => ev is OperationFailedEvent)
          .cast<OperationFailedEvent>()
          .listen(failed.add);
      addTearDown(sub.cancel);

      final stats = await e.sync(pullKinds: const {});
      await pumpEventQueue();

      expect(stats.conflictsResolved, 1);
      expect(stats.errors, 1);
      // `a` was resolved — its row is the server's and its op is gone. It
      // used to stay queued: the exception for `b` skipped the
      // acknowledgement of everything resolved before it.
      expect((await db.takeOutbox(limit: 10)).map((op) => op.opId), ['edit-b']);
      final rows = {
        for (final item in await db.select(db.testItems).get())
          item.id: item.name,
      };
      expect(rows, {'a': 'theirs', 'b': 'local b'});
      expect(failed.single.opId, 'edit-b');
    });

    test('counts as an attempt: the op ends up stuck instead of failing '
        'every sync of its kind forever', () async {
      const config = SyncConfig(conflictStrategy: ConflictStrategy.serverWins);
      final e = await twoConflicts();

      for (var i = 0; i < config.maxOutboxTryCount; i++) {
        await e.sync(pullKinds: const {});
      }

      expect((await e.getStuckOperations()).map((op) => op.opId), ['edit-b']);
      // Parked: the next sync has nothing to push and nothing to report.
      server.pushes.clear();
      final stats = await e.sync(pullKinds: const {});
      expect(server.pushes, isEmpty);
      expect(stats.errors, 0);
    });

    test('a resolver that throws is asked about ITS conflict again, not '
        'about the ones already answered', () async {
      final asked = <String>[];
      final e = await twoConflicts(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (conflict) async {
            asked.add(conflict.entityId);
            if (conflict.entityId == 'b') throw StateError('dialog closed');
            return const AcceptServer();
          },
        ),
      );
      server.answer = (op) => PushConflict(
        serverData: _row(op.id, 9, name: 'theirs'),
        serverTimestamp: DateTime.utc(2026, 5, 1, 12, 0, 9),
      );

      await e.sync(pullKinds: const {});
      await e.sync(pullKinds: const {});

      expect(asked, ['a', 'b', 'b']);
    });
  });

  group('a full resync', () {
    test('waits for a push that is already under way instead of sending the '
        'same operations a second time', () async {
      final e =
          engine(); // a new database: the first pulling sync is a full one
      await db.enqueue(
        UpsertOp(
          opId: 'create-n',
          kind: _kind,
          id: 'n',
          localTimestamp: DateTime.utc(2026, 5, 3),
          payloadJson: const {'id': 'n', 'name': 'new'},
        ),
      );
      server.pushGate = Completer<void>();

      // The debounced push after a local write…
      final pushOnly = e.sync(pushKinds: {_kind}, pullKinds: const {});
      await server.pushStarted.future;
      // …and the app's first sync, while that request is still out.
      final full = e.sync();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        server.pushes,
        hasLength(1),
        reason: 'the op is on its way; sending it again is a duplicate write',
      );

      server.pushGate!.complete();
      await Future.wait([pushOnly, full]);

      expect(server.maxPushesInFlight, 1);
      expect(server.pushes, [
        ['create-n'],
      ]);
      expect(await db.takeOutbox(limit: 10), isEmpty);
    });
  });

  group('what the engine reports', () {
    test('a failure while pushing is not reported as a pull error', () async {
      final e = engine();
      await db.enqueue(
        UpsertOp(
          opId: 'create-n',
          kind: _kind,
          id: 'n',
          localTimestamp: DateTime.utc(2026, 5, 3),
          payloadJson: const {'id': 'n', 'name': 'new'},
        ),
      );
      server.answer = (_) => throw const NetworkException('connection lost');
      final errors = <SyncErrorEvent>[];
      final sub = e.events
          .where((ev) => ev is SyncErrorEvent)
          .cast<SyncErrorEvent>()
          .listen(errors.add);
      addTearDown(sub.cancel);

      await expectLater(
        e.sync(pullKinds: const {}),
        throwsA(isA<SyncException>()),
      );
      await pumpEventQueue();

      expect(errors.single.phase, SyncPhase.push);
    });

    test('and one while pulling is', () async {
      final e = engine();
      server.failingPulls.add(1);
      final errors = <SyncErrorEvent>[];
      final sub = e.events
          .where((ev) => ev is SyncErrorEvent)
          .cast<SyncErrorEvent>()
          .listen(errors.add);
      addTearDown(sub.cancel);

      await expectLater(e.sync(), throwsA(isA<SyncException>()));
      await pumpEventQueue();

      expect(errors.map((ev) => ev.phase).toSet(), {SyncPhase.pull});
    });
  });

  group('startAuto()', () {
    test('a tick that fails is reported on the events stream, not as an '
        'unhandled asynchronous error', () async {
      final uncaught = <Object>[];
      final reported = <SyncErrorEvent>[];

      await runZonedGuarded(() async {
        final e = engine();
        final sub = e.events
            .where((ev) => ev is SyncErrorEvent)
            .cast<SyncErrorEvent>()
            .listen(reported.add);
        addTearDown(sub.cancel);
        server.failingPulls.addAll([for (var i = 1; i <= 50; i++) i]);

        e.startAuto(interval: const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        e.stopAuto();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (error, _) => uncaught.add(error));

      expect(reported, isNotEmpty);
      expect(uncaught, isEmpty);
    });
  });

  group('dispose()', () {
    test('while a sync is running lets it finish quietly instead of failing '
        'it with "Cannot add new events after calling close"', () async {
      server.rows = [_row('a', 1)];
      final e = engine();
      await e.sync();
      await db.enqueue(
        UpsertOp(
          opId: 'create-n',
          kind: _kind,
          id: 'n',
          localTimestamp: DateTime.utc(2026, 5, 3),
          payloadJson: const {'id': 'n', 'name': 'new'},
        ),
      );
      server.pushGate = Completer<void>();

      final running = e.sync();
      await server.pushStarted.future;
      e.dispose();
      server.pushGate!.complete();

      final stats = await running;
      expect(stats.pushed, 1);
      expect(await db.takeOutbox(limit: 10), isEmpty);
    });

    test('makes a later sync() fail with a message that says why', () async {
      final e = engine()..dispose();

      await expectLater(
        e.sync(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });
  });
}
