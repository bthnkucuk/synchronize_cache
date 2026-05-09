import 'package:test/test.dart';
import 'package:search_engine/src/models/pending_search_item.dart';

void main() {
  group('PendingSearchItem', () {
    test('default deleted is false', () {
      const item = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {'a': 1},
      );
      expect(item.deleted, isFalse);
      expect(item.userId, equals('u'));
      expect(item.kind, equals('k'));
      expect(item.id, equals('i'));
      expect(item.data, equals({'a': 1}));
    });

    test('explicit deleted=true is preserved', () {
      const item = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {},
        deleted: true,
      );
      expect(item.deleted, isTrue);
    });

    test('equality is value based via Equatable props', () {
      const a = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {'x': 'y'},
      );
      const b = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {'x': 'y'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing data makes the rows unequal', () {
      const a = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {'x': 1},
      );
      const b = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {'x': 2},
      );
      expect(a, isNot(equals(b)));
    });

    test('differing deleted flag makes the rows unequal', () {
      const a = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {},
      );
      const b = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {},
        deleted: true,
      );
      expect(a, isNot(equals(b)));
    });

    test('props expose every field', () {
      const item = PendingSearchItem(
        userId: 'u',
        kind: 'k',
        id: 'i',
        data: {'x': 1},
        deleted: true,
      );
      expect(item.props, equals(['u', 'k', 'i', true, {'x': 1}]));
    });
  });
}
