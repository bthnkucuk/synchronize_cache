import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/search_highlight_config.dart';
import 'package:search_engine/src/search_database.dart';
import 'package:search_engine/src/transport/drift_fts_search_transport.dart';

class _MockDb extends Mock implements SearchDatabaseMixin {}

class _FakeGlobalSearch extends Fake implements GlobalSearch {}

class _FakeHighlight extends Fake implements SearchHighlightConfig {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeGlobalSearch());
    registerFallbackValue(_FakeHighlight());
  });

  late _MockDb db;
  late DriftFtsSearchTransport transport;

  const item = GlobalSearch(
    originalId: 'o',
    userId: 'u',
    kind: 'k',
    title: 't',
    description: 'd',
    content: 'c',
  );

  setUp(() {
    db = _MockDb();
    transport = DriftFtsSearchTransport(db);
  });

  test('upsert delegates to SearchDatabaseMixin.upsertSearchItem', () async {
    when(() => db.upsertSearchItem(any())).thenAnswer((_) async {});

    await transport.upsert(item);

    verify(() => db.upsertSearchItem(item)).called(1);
  });

  test('delete forwards the (originalId, kind, userId) triple', () async {
    when(
      () => db.deleteSearchItem(
        originalId: any(named: 'originalId'),
        kind: any(named: 'kind'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});

    await transport.delete(originalId: 'o', kind: 'k', userId: 'u');

    verify(
      () => db.deleteSearchItem(originalId: 'o', kind: 'k', userId: 'u'),
    ).called(1);
  });

  test('search forwards every parameter to searchGlobal', () async {
    when(
      () => db.searchGlobal(
        userId: any(named: 'userId'),
        query: any(named: 'query'),
        kinds: any(named: 'kinds'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
        highlight: any(named: 'highlight'),
      ),
    ).thenAnswer((_) async => const [item]);

    const cfg = SearchHighlightConfig.none;
    final results = await transport.search(
      userId: 'u',
      query: 'q',
      kinds: const {'k1', 'k2'},
      offset: 5,
      limit: 25,
      highlight: cfg,
    );

    expect(results, equals([item]));
    verify(
      () => db.searchGlobal(
        userId: 'u',
        query: 'q',
        kinds: {'k1', 'k2'},
        offset: 5,
        limit: 25,
        highlight: cfg,
      ),
    ).called(1);
  });

  test('search uses the same defaults as the database method', () async {
    when(
      () => db.searchGlobal(
        userId: any(named: 'userId'),
        query: any(named: 'query'),
        kinds: any(named: 'kinds'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
        highlight: any(named: 'highlight'),
      ),
    ).thenAnswer((_) async => const []);

    await transport.search(userId: 'u', query: 'q');

    final captured = verify(
      () => db.searchGlobal(
        userId: 'u',
        query: 'q',
        kinds: captureAny(named: 'kinds'),
        offset: captureAny(named: 'offset'),
        limit: captureAny(named: 'limit'),
        highlight: captureAny(named: 'highlight'),
      ),
    ).captured;

    expect(captured[0], equals(<String>{}));
    expect(captured[1], equals(0));
    expect(captured[2], equals(50));
    expect(captured[3], isA<SearchHighlightConfig>());
  });

  test('watchSearch forwards every parameter to watchSearchGlobal', () async {
    when(
      () => db.watchSearchGlobal(
        userId: any(named: 'userId'),
        query: any(named: 'query'),
        kinds: any(named: 'kinds'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
        highlight: any(named: 'highlight'),
      ),
    ).thenAnswer((_) => Stream.value(const [item]));

    final stream = transport.watchSearch(
      userId: 'u',
      query: 'q',
      kinds: const {'k1'},
      offset: 1,
      limit: 2,
    );

    expect(await stream.first, equals([item]));
    verify(
      () => db.watchSearchGlobal(
        userId: 'u',
        query: 'q',
        kinds: {'k1'},
        offset: 1,
        limit: 2,
        highlight: any(named: 'highlight'),
      ),
    ).called(1);
  });
}
