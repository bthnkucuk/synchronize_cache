import 'dart:convert';

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

  late _MockQueueStore mockQueue;
  late _MockSearchTransport mockTransport;
  late SearchEngine searchEngine;

  PendingSearchItem makeItem({String id = '1', String kind = 'dummy', bool deleted = false}) =>
      PendingSearchItem(userId: 'test-user', kind: kind, id: id, deleted: deleted, data: const {'text': 'hello'});

  GlobalSearch parseDummy(PendingSearchItem item) => GlobalSearch(
    originalId: item.id,
    userId: item.userId,
    kind: item.kind,
    title: 'Title ${item.id}',
    description: 'Desc',
    content: 'Content',
  );

  SearchableTable<GeneratedDatabase, Map<String, dynamic>> dummyBinding(
    String kind,
    GlobalSearch Function(PendingSearchItem) parse,
  ) => searchableTable<GeneratedDatabase, Map<String, dynamic>>(
        kind: kind,
        watch: (_, __) => const Stream.empty(),
        idOf: (row) => row['id'] as String,
        toJson: (row) => row,
        toGlobalSearch: parse,
      );

  setUp(() {
    mockQueue = _MockQueueStore();
    mockTransport = _MockSearchTransport();

    when(() => mockQueue.upsertPendingUserItems(any())).thenAnswer((_) async {});
    when(
      () => mockQueue.deletePendingUserItem(
        id: any(named: 'id'),
        kind: any(named: 'kind'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockTransport.upsert(any())).thenAnswer((_) async {});
    when(
      () => mockTransport.delete(
        originalId: any(named: 'originalId'),
        kind: any(named: 'kind'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});

    searchEngine = SearchEngine(
      transport: mockTransport,
      database: mockQueue,
      tables: [dummyBinding('dummy', parseDummy)],
      jsonDecoder: (_) async => {'id': 'decoded'},
    );
  });

  group('SearchEngine.addSearchItems', () {
    test('queues items without indexing when processNow is false', () async {
      final item = makeItem();

      await searchEngine.addSearchItems([item]);

      verify(() => mockQueue.upsertPendingUserItems([item])).called(1);
      verifyNever(() => mockTransport.upsert(any()));
    });

    test('indexes items immediately when processNow is true', () async {
      final item = makeItem();

      await searchEngine.addSearchItems([item], processNow: true);

      verify(() => mockQueue.upsertPendingUserItems([item])).called(1);
      verify(
        () => mockTransport.upsert(
          any(that: isA<GlobalSearch>().having((g) => g.originalId, 'originalId', '1')),
        ),
      ).called(1);
      verify(() => mockQueue.deletePendingUserItem(id: '1', kind: 'dummy')).called(1);
    });

    test('processes deletes via transport.delete instead of transport.upsert', () async {
      final item = makeItem(deleted: true);

      await searchEngine.addSearchItems([item], processNow: true);

      verify(
        () => mockTransport.delete(originalId: '1', kind: 'dummy', userId: 'test-user'),
      ).called(1);
      verifyNever(() => mockTransport.upsert(any()));
      verify(() => mockQueue.deletePendingUserItem(id: '1', kind: 'dummy')).called(1);
    });

    test('drops queue entry when no binding matches the kind', () async {
      final item = makeItem(kind: 'unregistered');

      await searchEngine.addSearchItems([item], processNow: true);

      verifyNever(() => mockTransport.upsert(any()));
      verify(() => mockQueue.deletePendingUserItem(id: '1', kind: 'unregistered')).called(1);
    });
  });

  group('SearchEngine.processPendingItems', () {
    test('drains the queue for the given user id', () async {
      final item = makeItem();

      when(
        () => mockQueue.getPendingUserItems(
          userId: any(named: 'userId'),
          jsonDecoder: any(named: 'jsonDecoder'),
          limit: any(named: 'limit'),
          maxTryCount: any(named: 'maxTryCount'),
        ),
      ).thenAnswer((_) async => [item]);

      await searchEngine.processPendingItems(userId: 'test-user');

      verify(
        () => mockQueue.getPendingUserItems(
          userId: 'test-user',
          jsonDecoder: any(named: 'jsonDecoder'),
          limit: 5000,
          maxTryCount: any(named: 'maxTryCount'),
        ),
      ).called(1);
      verify(
        () => mockTransport.upsert(
          any(that: isA<GlobalSearch>().having((g) => g.originalId, 'originalId', '1')),
        ),
      ).called(1);
      verify(() => mockQueue.deletePendingUserItem(id: '1', kind: 'dummy')).called(1);
    });

    test('swallows errors thrown from a binding parser', () async {
      final broken = SearchEngine(
        transport: mockTransport,
        database: mockQueue,
        tables: [dummyBinding('bad', (_) => throw Exception('parse'))],
        jsonDecoder: (data) async => jsonDecode(data) as Map<String, dynamic>,
      );

      final item = makeItem(kind: 'bad');

      await broken.addSearchItems([item], processNow: true);

      verify(() => mockQueue.upsertPendingUserItems([item])).called(1);
      verifyNever(() => mockTransport.upsert(any()));
    });
  });
}
