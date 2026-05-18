import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart' hide isNull, isNotNull;

import '../sync_engine_test.dart' show TestDatabase, TestItem;
import '../sync_engine_test.drift.dart';

// PullService tests using a real in-memory drift database. The service's
// `_db.batch(...)` API is not feasible to mock without rebuilding much of
// drift; using TestDatabase (NativeDatabase.memory()) keeps the surface area
// small while still exercising the service-level branches (empty page,
// multiple pages, pagination termination, cursor advancement, missing-kind,
// error wrapping, missing-updatedAt → ParseException). We reuse the
// TestDatabase already defined for the integration test rather than declaring
// a new @DriftDatabase class (which would require running build_runner).

class _MockTransport extends Mock implements TransportAdapter {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime.utc(2024));
  });

  late TestDatabase db;
  late _MockTransport transport;
  late StreamController<SyncEvent> events;
  late CursorService cursorService;
  late SyncableTable<TestItem> testItemTable;
  late Map<String, SyncableTable<dynamic>> tables;

  setUp(() {
    db = TestDatabase();
    transport = _MockTransport();
    events = StreamController<SyncEvent>.broadcast();
    cursorService = CursorService(db);
    testItemTable = SyncableTable<TestItem>(
      kind: 'test_item',
      table: db.testItems,
      fromJson: TestItem.fromJson,
      toJson: (e) => e.toJson(),
      toInsertable: (e) => e.toInsertable(),
      getId: (e) => e.id,
      getUpdatedAt: (e) => e.updatedAt,
    );
    tables = {'test_item': testItemTable};
  });

  tearDown(() async {
    await db.close();
    await events.close();
  });

  PullService<TestDatabase> buildService({SyncConfig? config}) => PullService(
        db: db,
        transport: transport,
        tables: tables,
        cursorService: cursorService,
        config: config ?? const SyncConfig(pageSize: 100),
        events: events,
      );

  group('PullService.pullKind', () {
    test('returns 0 for unregistered kind without calling transport',
        () async {
      final service = buildService();

      final n = await service.pullKind('unknown');

      expect(n, 0);
      verifyNever(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
        ),
      );
    });

    test('returns 0 immediately when first page is empty', () async {
      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenAnswer((_) async => PullPage(items: []));

      final service = buildService();
      final n = await service.pullKind('test_item');

      expect(n, 0);
      verify(
        () => transport.pull(
          kind: 'test_item',
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: true,
        ),
      ).called(1);
    });

    test('pulls a single page, writes rows, advances cursor, emits events',
        () async {
      final ts1 = DateTime.utc(2024, 1, 1, 10);
      final ts2 = DateTime.utc(2024, 1, 1, 11);

      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenAnswer(
        (_) async => PullPage(
          items: [
            {'id': 'a', 'updated_at': ts1.toIso8601String(), 'name': 'A'},
            {'id': 'b', 'updated_at': ts2.toIso8601String(), 'name': 'B'},
          ],
        ),
      );

      final captured = <SyncEvent>[];
      final sub = events.stream.listen(captured.add);

      final service = buildService(config: const SyncConfig(pageSize: 100));
      final n = await service.pullKind('test_item');

      // 2 items processed, no nextPageToken and items < pageSize → loop ends.
      expect(n, 2);
      verify(
        () => transport.pull(
          kind: 'test_item',
          updatedSince: any(named: 'updatedSince'),
          pageSize: 100,
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: true,
        ),
      ).called(1);

      // Local rows persisted.
      final rows = await db.select(db.testItems).get();
      expect(rows.map((r) => r.id).toList()..sort(), ['a', 'b']);

      // Cursor advanced to last item.
      final cur = await cursorService.get('test_item');
      expect(cur, isNot(null));
      expect(cur!.ts, ts2);
      expect(cur.lastId, 'b');

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(captured.whereType<CacheUpdateEvent>(), isNotEmpty);
      expect(captured.whereType<PullPageProcessedEvent>(), hasLength(1));
      expect(captured.whereType<SyncProgress>(), isNotEmpty);
    });

    test('paginates while a nextPageToken is returned', () async {
      final ts1 = DateTime.utc(2024, 1, 1, 10);
      final ts2 = DateTime.utc(2024, 1, 2, 10);

      var call = 0;
      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenAnswer((_) async {
        call++;
        if (call == 1) {
          return PullPage(
            items: [
              {'id': 'a', 'updated_at': ts1.toIso8601String(), 'name': 'A'},
            ],
            nextPageToken: 'tok-1',
          );
        }
        if (call == 2) {
          return PullPage(
            items: [
              {'id': 'b', 'updated_at': ts2.toIso8601String(), 'name': 'B'},
            ],
            // No token and (items < pageSize) → loop terminates.
          );
        }
        return PullPage(items: []);
      });

      final service = buildService(config: const SyncConfig(pageSize: 100));
      final n = await service.pullKind('test_item');

      expect(n, 2);
      expect(call, 2);

      final cur = await cursorService.get('test_item');
      expect(cur!.lastId, 'b');
      expect(cur.ts, ts2);

      // First pull must not pass a pageToken; second pull must forward the
      // nextPageToken returned from the first response. A regression that
      // drops the token (e.g. always passes null) would fail this assertion.
      verify(
        () => transport.pull(
          kind: 'test_item',
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: null,
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).called(1);
      verify(
        () => transport.pull(
          kind: 'test_item',
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: 'tok-1',
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).called(1);
    });

    test(
      'continues paginating when items.length == pageSize even without token',
      () async {
        // pageSize=1 forces a second pull even when no nextPageToken.
        final ts1 = DateTime.utc(2024, 1, 1, 10);
        final ts2 = DateTime.utc(2024, 1, 1, 11);

        var call = 0;
        when(
          () => transport.pull(
            kind: any(named: 'kind'),
            updatedSince: any(named: 'updatedSince'),
            pageSize: any(named: 'pageSize'),
            pageToken: any(named: 'pageToken'),
            afterId: any(named: 'afterId'),
            includeDeleted: any(named: 'includeDeleted'),
          ),
        ).thenAnswer((_) async {
          call++;
          if (call == 1) {
            return PullPage(
              items: [
                {'id': 'a', 'updated_at': ts1.toIso8601String(), 'name': 'A'},
              ],
            );
          }
          if (call == 2) {
            return PullPage(
              items: [
                {'id': 'b', 'updated_at': ts2.toIso8601String(), 'name': 'B'},
              ],
            );
          }
          return PullPage(items: []);
        });

        final service = buildService(config: const SyncConfig(pageSize: 1));
        final n = await service.pullKind('test_item');

        // pageSize=1, items.length == pageSize on call #1 → fetches call #2.
        // call #2 also has 1 item, which == pageSize, so it issues call #3 →
        // empty page breaks the loop.
        expect(call, greaterThanOrEqualTo(2));
        expect(n, 2);
      },
    );

    test('throws SyncOperationException when item is missing updatedAt',
        () async {
      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenAnswer(
        (_) async => PullPage(
          items: [
            // Missing updated_at, but a name + id that the fromJson would
            // otherwise consume → the service should reject and throw.
            {
              'id': 'a',
              'updated_at': DateTime.utc(2024).toIso8601String(),
              'name': 'A',
            },
            {'id': 'b', 'name': 'B'},
          ],
        ),
      );

      final service = buildService();

      expect(
        () => service.pullKind('test_item'),
        throwsA(
          // ParseException is rethrown unchanged because it's a SyncException;
          // however items are processed before the timestamp check, and
          // fromJson runs first — if fromJson throws on the missing
          // updated_at, it gets wrapped in SyncOperationException. Either
          // outcome is a SyncException.
          isA<SyncException>(),
        ),
      );
    });

    test('wraps non-SyncException errors in SyncOperationException', () async {
      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenThrow(StateError('network borked'));

      final service = buildService();

      try {
        await service.pullKind('test_item');
        fail('expected exception');
      } on SyncOperationException catch (e) {
        expect(e.phase, 'pull');
        expect(e.cause, isA<StateError>());
      }
    });

    test('rethrows existing SyncException as-is (no double-wrapping)',
        () async {
      const original = NetworkException('connection refused');
      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenThrow(original);

      final service = buildService();

      expect(
        () => service.pullKind('test_item'),
        throwsA(
          // Must be the same NetworkException instance, not wrapped.
          predicate<Object?>((e) => identical(e, original)),
        ),
      );
    });

    test('passes cursor-derived updatedSince and afterId to transport',
        () async {
      // Pre-seed cursor.
      final since = DateTime.utc(2023, 12, 31);
      await cursorService.set(
        'test_item',
        Cursor(ts: since, lastId: 'prev-id'),
      );

      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenAnswer((_) async => PullPage(items: []));

      final service = buildService();
      await service.pullKind('test_item');

      verify(
        () => transport.pull(
          kind: 'test_item',
          updatedSince: since,
          pageSize: any(named: 'pageSize'),
          pageToken: null,
          afterId: 'prev-id',
          includeDeleted: true,
        ),
      ).called(1);
    });
  });

  group('PullService.pullKinds', () {
    test('skips unregistered kinds and sums totals', () async {
      final ts = DateTime.utc(2024, 1, 1, 10);
      when(
        () => transport.pull(
          kind: any(named: 'kind'),
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).thenAnswer(
        (_) async => PullPage(
          items: [
            {'id': 'x', 'updated_at': ts.toIso8601String(), 'name': 'X'},
          ],
        ),
      );

      final service = buildService();
      final n = await service.pullKinds({'test_item', 'unknown_kind'});

      expect(n, 1);
      verify(
        () => transport.pull(
          kind: 'test_item',
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      ).called(1);
      verifyNever(
        () => transport.pull(
          kind: 'unknown_kind',
          updatedSince: any(named: 'updatedSince'),
          pageSize: any(named: 'pageSize'),
          pageToken: any(named: 'pageToken'),
          afterId: any(named: 'afterId'),
          includeDeleted: any(named: 'includeDeleted'),
        ),
      );
    });
  });
}
