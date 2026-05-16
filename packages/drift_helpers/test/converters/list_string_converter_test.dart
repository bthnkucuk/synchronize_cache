import 'package:drift_helpers/drift_helpers.dart';
import 'package:test/test.dart';

void main() {
  const converter = StringListConverter();

  group('StringListConverter', () {
    group('fromSql', () {
      test('returns empty list for empty string', () {
        expect(converter.fromSql(''), equals(<String>[]));
      });

      test('returns list of strings for valid JSON array', () {
        expect(converter.fromSql('["a", "b"]'), equals(['a', 'b']));
      });

      test('returns empty list for invalid JSON (catch block)', () {
        expect(converter.fromSql('invalid'), equals(<String>[]));
      });

      test('returns empty list for non-list JSON', () {
        expect(converter.fromSql('{"key": "value"}'), equals(<String>[]));
      });
    });

    group('toSql', () {
      test('returns JSON array string for list', () {
        expect(converter.toSql(['a', 'b']), equals('["a","b"]'));
      });
    });

    group('fromJson', () {
      test('returns empty list for null', () {
        expect(converter.fromJson(null), equals(<String>[]));
      });

      test('returns list of strings for list input', () {
        expect(converter.fromJson(['a', 'b']), equals(['a', 'b']));
      });

      test('returns wrapped list for single item (string)', () {
        expect(converter.fromJson('a'), equals(['a']));
      });
    });

    group('toJson', () {
      test('returns value as is', () {
        final list = ['a', 'b'];
        expect(converter.toJson(list), equals(list));
      });
    });

    test('jsonConverter helper roundtrips', () {
      final c = StringListConverter.jsonConverter;
      expect(c.fromJson(['a', 'b']), equals(['a', 'b']));
      expect(c.toJson(['x']), equals(['x']));
    });
  });
}
