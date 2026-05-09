import 'dart:async';

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/pending_search_item.dart';
import 'package:search_engine/src/models/searchable_table.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/search_engine.dart';
import 'package:search_engine/src/transport/search_transport.dart';

class _MockQueueStore extends Mock implements SearchDatabaseMixin {}

class _MockSearchTransport extends Mock implements SearchTransport {}

class _FakePendingSearchItemList extends Fake implements List<PendingSearchItem> {}

class _FakeGlobalSearch extends Fake implements GlobalSearch {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakePendingSearchItemList());
    registerFallbackValue(_FakeGlobalSearch());
  });

  late _MockQueueStore queue;
  late _MockSearchTransport transport;

  PendingSearchItem makeItem({
    String id = '1',
    String kind = 'dummy',
    bool deleted = false,
    Map<String, dynamic> data = const {'title': 'şehir'},
    String userId = 'u',
  }) =>
      PendingSearchItem(
        userId: userId,
        kind: kind,
        id: id,
        deleted: deleted,
        data: data,
      );

  GlobalSearch parseDummy(PendingSearchItem item) => GlobalSearch(
        originalId: item.id,
        userId: item.userId,
        kind: item.kind,
        title: (item.data['title'] as String?) ?? '',
        description: '',
        content: '',
      );

  SearchableTable<GeneratedDatabase, Map<String, dynamic>> dummyBinding(
    String kind, {
    FutureOr<GlobalSearch> Function(PendingSearchItem)? parse,
  }) =>
      searchableTable<GeneratedDatabase, Map<String, dynamic>>(
        kind: kind,
        watch: (_, __) => const Stream.empty(),
        idOf: (row) => row['id'] as String,
        toJson: (row) => row,
        toGlobalSearch: parse ?? parseDummy,
      );

  String stripDiacritics(String s) =>
      s.replaceAll('ş', 's').replaceAll('Ş', 's').toLowerCase();

  setUp(() {
    queue = _MockQueueStore();
    transport = _MockSearchTransport();

    when(() => queue.upsertPendingUserItems(any())).thenAnswer((_) async {});
    when(
      () => queue.deletePendingUserItem(
        id: any(named: 'id'),
        kind: any(named: 'kind'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => queue.incrementPendingTryCount(
        id: any(named: 'id'),
        kind: any(named: 'kind'),
      ),
    ).thenAnswer((_) async {});
    when(() => transport.upsert(any())).thenAnswer((_) async {});
    when(
      () => transport.delete(
        originalId: any(named: 'originalId'),
        kind: any(named: 'kind'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});
  });

  group('SearchEngine getters', () {
    test('expose injected transport, database, and normalizer', () {
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
        normalizer: stripDiacritics,
      );
      expect(engine.transport, same(transport));
      expect(engine.database, same(queue));
      expect(engine.normalizer, equals(stripDiacritics));
    });

    test('normalizer is null when no normalizer is provided', () {
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
      );
      expect(engine.normalizer, isNull);
    });

    test('maxPendingTries defaults to 5 and accepts overrides', () {
      final defaulted = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
      );
      expect(defaulted.maxPendingTries, equals(5));

      final overridden = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
        maxPendingTries: 9,
      );
      expect(overridden.maxPendingTries, equals(9));
    });

    test('tableForKind returns the registered binding or null', () {
      final binding = dummyBinding('a');
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: [binding],
      );
      expect(engine.tableForKind('a'), same(binding));
      expect(engine.tableForKind('missing'), isNull);
    });
  });

  group('SearchEngine.indexNow / removeNow', () {
    test('indexNow normalizes through the engine normalizer', () async {
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
        normalizer: stripDiacritics,
      );

      const item = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 'Şehir',
        description: 'D',
        content: 'C',
      );

      await engine.indexNow(item);

      final captured = verify(() => transport.upsert(captureAny())).captured;
      final pushed = captured.single as GlobalSearch;
      expect(pushed.title, equals('Şehir'));
      expect(pushed.titleNormalized, equals('sehir'));
      expect(pushed.descriptionNormalized, equals('d'));
      expect(pushed.contentNormalized, equals('c'));
    });

    test('indexNow without a normalizer pushes the row unchanged', () async {
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
      );

      const item = GlobalSearch(
        originalId: 'o',
        userId: 'u',
        kind: 'k',
        title: 't',
        description: 'd',
        content: 'c',
      );

      await engine.indexNow(item);

      verify(() => transport.upsert(item)).called(1);
    });

    test('removeNow forwards the triple to the transport', () async {
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
      );

      await engine.removeNow(originalId: 'o', kind: 'k', userId: 'u');

      verify(
        () => transport.delete(originalId: 'o', kind: 'k', userId: 'u'),
      ).called(1);
    });
  });

  group('SearchEngine error handling', () {
    test('parser failure increments tryCount and notifies the error handler',
        () async {
      Object? caughtException;
      Object? caughtMessage;

      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: [
          dummyBinding('boom', parse: (_) => throw StateError('parse failed')),
        ],
        errorHandler: (e, [st, msg]) {
          caughtException = e;
          caughtMessage = msg;
        },
      );

      await engine.addSearchItems([makeItem(kind: 'boom')], processNow: true);

      expect(caughtException, isA<StateError>());
      expect(caughtMessage, contains('SearchEngine._processSearchItem'));
      verify(
        () => queue.incrementPendingTryCount(id: '1', kind: 'boom'),
      ).called(1);
      verifyNever(
        () => queue.deletePendingUserItem(id: '1', kind: 'boom'),
      );
    });

    test(
        'tryCount increment failure is swallowed (best-effort) without crashing',
        () async {
      when(
        () => queue.incrementPendingTryCount(
          id: any(named: 'id'),
          kind: any(named: 'kind'),
        ),
      ).thenThrow(StateError('db went away'));

      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: [
          dummyBinding('boom', parse: (_) => throw StateError('parse failed')),
        ],
      );

      await expectLater(
        engine.addSearchItems([makeItem(kind: 'boom')], processNow: true),
        completes,
      );
    });

    test(
        'processPendingItems delegates queue load failure to the error handler',
        () async {
      Object? caught;
      Object? caughtMsg;

      when(
        () => queue.getPendingUserItems(
          userId: any(named: 'userId'),
          jsonDecoder: any(named: 'jsonDecoder'),
          limit: any(named: 'limit'),
          maxTryCount: any(named: 'maxTryCount'),
        ),
      ).thenThrow(StateError('queue read failed'));

      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
        errorHandler: (e, [st, msg]) {
          caught = e;
          caughtMsg = msg;
        },
      );

      await engine.processPendingItems(userId: 'u');

      expect(caught, isA<StateError>());
      expect(caughtMsg, contains('SearchEngine.processPendingItems'));
    });

    test('processPendingItems forwards maxPendingTries to the queue', () async {
      when(
        () => queue.getPendingUserItems(
          userId: any(named: 'userId'),
          jsonDecoder: any(named: 'jsonDecoder'),
          limit: any(named: 'limit'),
          maxTryCount: any(named: 'maxTryCount'),
        ),
      ).thenAnswer((_) async => const []);

      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
        maxPendingTries: 9,
      );

      await engine.processPendingItems(userId: 'u', batchSize: 11);

      verify(
        () => queue.getPendingUserItems(
          userId: 'u',
          jsonDecoder: any(named: 'jsonDecoder'),
          limit: 11,
          maxTryCount: 9,
        ),
      ).called(1);
    });
  });

  group('SearchEngine.addSearchItems normalizer + processNow', () {
    test(
        'processNow=true normalizes outbound rows through the injected normalizer',
        () async {
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: [dummyBinding('dummy')],
        normalizer: stripDiacritics,
      );

      await engine.addSearchItems([makeItem()], processNow: true);

      final captured = verify(() => transport.upsert(captureAny())).captured;
      final pushed = captured.single as GlobalSearch;
      expect(pushed.title, equals('şehir'));
      expect(pushed.titleNormalized, equals('sehir'));
    });

    test('addSearchItems with empty list still calls upsertPendingUserItems',
        () async {
      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
      );

      await engine.addSearchItems(const []);

      verify(() => queue.upsertPendingUserItems(const [])).called(1);
      verifyNever(() => transport.upsert(any()));
    });
  });

  group('SearchEngine concurrency', () {
    test(
        'parallel processPendingItems calls are serialized by the internal lock',
        () async {
      var inflight = 0;
      var observedPeak = 0;

      when(
        () => queue.getPendingUserItems(
          userId: any(named: 'userId'),
          jsonDecoder: any(named: 'jsonDecoder'),
          limit: any(named: 'limit'),
          maxTryCount: any(named: 'maxTryCount'),
        ),
      ).thenAnswer((_) async {
        inflight++;
        observedPeak = inflight > observedPeak ? inflight : observedPeak;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        inflight--;
        return const [];
      });

      final engine = SearchEngine(
        transport: transport,
        database: queue,
        tables: const [],
      );

      await Future.wait([
        engine.processPendingItems(userId: 'u'),
        engine.processPendingItems(userId: 'u'),
        engine.processPendingItems(userId: 'u'),
      ]);

      expect(observedPeak, equals(1),
          reason: 'lock should ensure no overlap between drains');
    });
  });
}
