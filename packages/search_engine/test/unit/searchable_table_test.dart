import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:test/test.dart';
import 'package:search_engine/src/models/global_search.dart';
import 'package:search_engine/src/models/pending_search_item.dart';
import 'package:search_engine/src/models/searchable_table.dart';

class _Row {
  const _Row({
    required this.id,
    required this.title,
    this.deleted = false,
  });

  final String id;
  final String title;
  final bool deleted;
}

void main() {
  group('searchableTable factory', () {
    test('exposes the configured kind and watches via the supplied callback',
        () async {
      final stream = Stream<List<_Row>>.value([
        const _Row(id: '1', title: 't'),
      ]);

      final binding = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => stream,
        idOf: (row) => row.id,
        toJson: (row) => {'id': row.id, 'title': row.title},
      );

      expect(binding.kind, equals('rows'));
      expect(binding.idOf(const _Row(id: '42', title: 'x')), equals('42'));
      expect(
        binding.toJson(const _Row(id: '1', title: 't')),
        equals({'id': '1', 'title': 't'}),
      );

      final emitted = await binding.watch(_FakeDb(), 'user').first;
      expect(emitted, hasLength(1));
      expect(emitted.first.id, equals('1'));
    });

    test('isDeleted defaults to false; honours the override when supplied', () {
      final defaulted = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
      );
      expect(
        defaulted.isDeleted(const _Row(id: '1', title: 't', deleted: true)),
        isFalse,
      );

      final tombstoned = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
        isDeleted: (r) => r.deleted,
      );
      expect(
        tombstoned.isDeleted(const _Row(id: '1', title: 't', deleted: true)),
        isTrue,
      );
      expect(
        tombstoned.isDeleted(const _Row(id: '1', title: 't')),
        isFalse,
      );
    });

    test('toGlobalSearch defaults to title/description/content from JSON', () async {
      final binding = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {
          'title': 'Title',
          'description': 'Desc',
          'content': 'Content',
        },
      );

      final result = await binding.toGlobalSearch(
        const PendingSearchItem(
          userId: 'u',
          kind: 'rows',
          id: '1',
          data: {
            'title': 'Title',
            'description': 'Desc',
            'content': 'Content',
          },
        ),
      );

      expect(result, isA<GlobalSearch>());
      expect(result.originalId, equals('1'));
      expect(result.userId, equals('u'));
      expect(result.kind, equals('rows'));
      expect(result.title, equals('Title'));
      expect(result.description, equals('Desc'));
      expect(result.content, equals('Content'));
    });

    test('toGlobalSearch default falls back to empty strings on missing fields',
        () async {
      final binding = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
      );

      final result = await binding.toGlobalSearch(
        const PendingSearchItem(
          userId: 'u',
          kind: 'rows',
          id: '1',
          data: {},
        ),
      );

      expect(result.title, isEmpty);
      expect(result.description, isEmpty);
      expect(result.content, isEmpty);
    });

    test('custom toGlobalSearch override is invoked', () async {
      final binding = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
        toGlobalSearch: (item) async => GlobalSearch(
          originalId: 'override-${item.id}',
          userId: item.userId,
          kind: item.kind,
          title: 'overridden',
          description: '',
          content: '',
        ),
      );

      final result = await binding.toGlobalSearch(
        const PendingSearchItem(
          userId: 'u',
          kind: 'rows',
          id: '7',
          data: {},
        ),
      );
      expect(result.originalId, equals('override-7'));
      expect(result.title, equals('overridden'));
    });

    test('updatedAtOf throws by default and returns the override otherwise', () {
      final base = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
      );
      expect(
        () => base.updatedAtOf(const _Row(id: '1', title: 't')),
        throwsA(isA<UnsupportedError>()),
      );

      final ts = DateTime.utc(2026, 1, 1);
      final overridden = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
        updatedAtOf: (r) => ts,
      );
      expect(
        overridden.updatedAtOf(const _Row(id: '1', title: 't')),
        equals(ts),
      );
    });

    test('readSince throws by default and returns the override otherwise',
        () async {
      final base = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
      );
      expect(
        () => base.readSince(_FakeDb(), 'u', DateTime.utc(2026), null, 10),
        throwsA(isA<UnsupportedError>()),
      );

      final overridden = searchableTable<GeneratedDatabase, _Row>(
        kind: 'rows',
        watch: (_, __) => const Stream.empty(),
        idOf: (r) => r.id,
        toJson: (r) => {},
        readSince: (db, userId, since, lastId, limit) async => [
          _Row(id: 'after-$lastId-limit-$limit', title: 'x'),
        ],
      );

      final out = await overridden.readSince(
        _FakeDb(),
        'u',
        DateTime.utc(2026),
        'last',
        25,
      );
      expect(out, hasLength(1));
      expect(out.first.id, equals('after-last-limit-25'));
    });
  });
}

class _FakeDb implements GeneratedDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
