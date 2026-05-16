import 'package:drift_helpers/drift_helpers.dart';
import 'package:test/test.dart';

void main() {
  const converter = JsonConverter();

  group('JsonConverter', () {
    group('fromSql', () {
      test('returns null for null string', () {
        expect(converter.fromSql(null), isNull);
      });

      test('returns null for empty string', () {
        expect(converter.fromSql(''), isNull);
      });

      test('returns map for valid JSON string', () {
        final result = converter.fromSql('{"key": "value", "number": 123}');
        expect(result, equals({'key': 'value', 'number': 123}));
      });

      test('returns null for invalid JSON string (catch block)', () {
        expect(converter.fromSql('invalid json'), isNull);
      });

      test('returns null for non-map JSON (e.g. List)', () {
        expect(converter.fromSql('[1, 2, 3]'), isNull);
      });
    });

    group('toSql', () {
      test('returns "{}" for null value', () {
        expect(converter.toSql(null), equals('{}'));
      });

      test('returns JSON string for valid map', () {
        expect(converter.toSql({'key': 'value'}), equals('{"key":"value"}'));
      });
    });

    group('fromJson', () {
      test('returns null for null', () {
        expect(converter.fromJson(null), isNull);
      });

      test('returns map for map input', () {
        expect(converter.fromJson({'key': 'value'}), equals({'key': 'value'}));
      });

      test('returns null for non-map input', () {
        expect(converter.fromJson('string'), isNull);
      });
    });

    group('toJson', () {
      test('returns value as is', () {
        final map = {'key': 'value'};
        expect(converter.toJson(map), equals(map));
      });
    });
  });
}
