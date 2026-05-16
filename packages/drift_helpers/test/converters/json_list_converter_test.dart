import 'package:drift_helpers/drift_helpers.dart';
import 'package:test/test.dart';

void main() {
  const c = JsonListConverter();

  group('JsonListConverter', () {
    test('fromSql null and empty', () {
      expect(c.fromSql(null), isNull);
      expect(c.fromSql(''), isNull);
    });

    test('fromSql valid list of maps', () {
      expect(
        c.fromSql('[{"a":1},{"b":2}]'),
        equals([
          {'a': 1},
          {'b': 2},
        ]),
      );
    });

    test('fromSql invalid json returns null', () {
      expect(c.fromSql('not-json'), isNull);
    });

    test('fromSql non-list json returns null', () {
      expect(c.fromSql('{}'), isNull);
    });

    test('toSql null and value', () {
      expect(c.toSql(null), isNull);
      expect(
        c.toSql([
          {'x': 1},
        ]),
        equals('[{"x":1}]'),
      );
    });

    test('fromJson branches', () {
      expect(c.fromJson(null), isNull);
      expect(
        c.fromJson([
          {'a': 1},
        ]),
        equals([
          {'a': 1},
        ]),
      );
      expect(c.fromJson('x'), isNull);
    });

    test('toJson passes through', () {
      final list = <Map<String, dynamic>>[
        {'a': 1},
      ];
      expect(c.toJson(list), same(list));
    });
  });
}
