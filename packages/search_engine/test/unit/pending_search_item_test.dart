import 'dart:convert';

import 'package:test/test.dart';
import 'package:search_engine/src/models/pending_search_item.dart';

/// Builds a fresh, non-const instance. Identical `const` instances are
/// canonicalized by Dart, which would let `==` pass on identity alone and
/// hide a broken value-equality implementation.
PendingSearchItem _item({
  String userId = 'u',
  String kind = 'k',
  String id = 'i',
  bool deleted = false,
  Map<String, dynamic>? data,
}) => PendingSearchItem(
  userId: userId,
  kind: kind,
  id: id,
  deleted: deleted,
  data: data ?? <String, dynamic>{'x': 'y'},
);

Map<String, dynamic> _json(String source) =>
    jsonDecode(source) as Map<String, dynamic>;

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

    test('equality is value based, not identity based', () {
      final a = _item();
      final b = _item();
      expect(identical(a, b), isFalse, reason: 'test must not be vacuous');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('every field participates in equality', () {
      final base = _item();
      final variants = <String, PendingSearchItem>{
        'userId': _item(userId: 'other'),
        'kind': _item(kind: 'other'),
        'id': _item(id: 'other'),
        'deleted': _item(deleted: true),
        'data': _item(data: <String, dynamic>{'x': 'other'}),
      };
      for (final MapEntry(key: field, value: variant) in variants.entries) {
        expect(variant, isNot(equals(base)), reason: '$field must matter');
      }
    });

    group('data is compared deeply, as decoded JSON', () {
      test('nested maps and lists are equal by content', () {
        const source = '{"a": {"b": [1, {"c": null}, "s"]}, "n": 1.5}';
        final a = _item(data: _json(source));
        final b = _item(data: _json(source));
        expect(identical(a.data, b.data), isFalse);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('a difference deep inside a nested list is detected', () {
        final a = _item(data: _json('{"a": {"b": [1, {"c": 1}]}}'));
        final b = _item(data: _json('{"a": {"b": [1, {"c": 2}]}}'));
        expect(a, isNot(equals(b)));
      });

      test('map key order does not matter', () {
        final a = _item(data: _json('{"x": 1, "y": 2}'));
        final b = _item(data: _json('{"y": 2, "x": 1}'));
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('list order does matter', () {
        final a = _item(data: _json('{"l": [1, 2]}'));
        final b = _item(data: _json('{"l": [2, 1]}'));
        expect(a, isNot(equals(b)));
      });

      test('a missing key differs from an explicit null value', () {
        final a = _item(data: _json('{"x": 1, "y": null}'));
        final b = _item(data: _json('{"x": 1, "z": null}'));
        expect(a, isNot(equals(b)));
      });

      test('maps of different length are unequal', () {
        final a = _item(data: _json('{"x": 1}'));
        final b = _item(data: _json('{"x": 1, "y": 2}'));
        expect(a, isNot(equals(b)));
        expect(b, isNot(equals(a)));
      });

      test('numerically equal int and double compare equal', () {
        // JSON round-trips can turn `1` into `1.0`; `1 == 1.0` in Dart.
        final a = _item(data: _json('{"n": 1}'));
        final b = _item(data: _json('{"n": 1.0}'));
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('a const map equals an equivalent decoded map', () {
        final a = _item(data: const {'x': 1});
        final b = _item(data: _json('{"x": 1}'));
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    test('works as a Set element / Map key', () {
      final set = {_item(), _item(), _item(id: 'other')};
      expect(set, hasLength(2));
    });

    test('is never equal to an unrelated object', () {
      expect(_item(), isNot(equals('u')));
    });

    test('toString lists the fields', () {
      final text = _item(deleted: true).toString();
      expect(text, startsWith('PendingSearchItem('));
      expect(text, contains('userId: u'));
      expect(text, contains('deleted: true'));
    });
  });
}
