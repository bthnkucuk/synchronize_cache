import 'package:drift_helpers/drift_helpers.dart';
import 'package:test/test.dart';

void main() {
  const c = IntListConverter();

  group('IntListConverter', () {
    test('fromSql empty', () {
      expect(c.fromSql(''), equals(<int>[]));
    });

    test('fromSql valid', () {
      expect(c.fromSql('[1,2,3]'), equals([1, 2, 3]));
    });

    test('fromSql invalid json yields empty', () {
      expect(c.fromSql('bad'), equals(<int>[]));
    });

    test('fromSql non-list decoded yields empty', () {
      expect(c.fromSql('{}'), equals(<int>[]));
    });

    test('toSql encodes', () {
      expect(c.toSql([1, 2]), equals('[1,2]'));
    });

    test('fromJson', () {
      expect(c.fromJson(null), equals(<int>[]));
      expect(c.fromJson([1, 2.0]), equals([1, 2]));
      expect(c.fromJson('x'), equals(<int>[]));
    });

    test('toJson passes through', () {
      final list = [1, 2];
      expect(c.toJson(list), same(list));
    });
  });
}
