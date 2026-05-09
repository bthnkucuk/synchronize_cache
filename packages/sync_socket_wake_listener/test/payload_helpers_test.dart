import 'package:flutter_test/flutter_test.dart';
import 'package:sync_socket_wake_listener/src/payload_helpers.dart';

void main() {
  group('serverManagedFields', () {
    test('contains all expected server-managed field names', () {
      expect(
        serverManagedFields,
        containsAll(<String>['id', 'bundle_id', 'user_id', 'created_at', 'updated_at', 'deleted_at']),
      );
      expect(serverManagedFields.length, equals(6));
    });
  });

  group('stripServerManagedFields', () {
    test('removes server-managed keys from json', () {
      final input = {
        'id': 'abc-123',
        'bundle_id': 'app.tupandas.ainote',
        'user_id': 'uid-1',
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-06-01T00:00:00Z',
        'deleted_at': null,
        'title': 'My Project',
        'is_favorite': false,
      };

      final result = stripServerManagedFields(input);

      expect(result, isNot(contains('id')));
      expect(result, isNot(contains('bundle_id')));
      expect(result, isNot(contains('user_id')));
      expect(result, isNot(contains('created_at')));
      expect(result, isNot(contains('updated_at')));
      expect(result, isNot(contains('deleted_at')));

      expect(result['title'], equals('My Project'));
      expect(result['is_favorite'], isFalse);
    });

    test('returns empty map when all keys are server-managed', () {
      final input = {
        'id': 'x',
        'bundle_id': 'y',
        'user_id': 'z',
        'created_at': 'a',
        'updated_at': 'b',
        'deleted_at': null,
      };
      expect(stripServerManagedFields(input), isEmpty);
    });

    test('returns copy; does not mutate original', () {
      final input = <String, dynamic>{'id': '1', 'title': 'foo'};
      final result = stripServerManagedFields(input);
      expect(input.containsKey('id'), isTrue);
      expect(result.containsKey('id'), isFalse);
    });

    test('passes through non-server-managed keys unchanged', () {
      final input = <String, dynamic>{
        'title': 'hello',
        'tag_ids': ['a', 'b'],
        'is_favorite': true,
        'extra': null,
      };
      final result = stripServerManagedFields(input);
      expect(result, equals(input));
    });
  });
}
