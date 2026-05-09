// Edge cases for payload_helpers that go beyond the happy path covered by
// the top-level payload_helpers_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_socket_wake_listener/src/payload_helpers.dart';

void main() {
  group('stripServerManagedFields edge cases', () {
    test('returns empty map for empty input', () {
      expect(stripServerManagedFields(const {}), isEmpty);
    });

    test('preserves nested maps verbatim (only strips top-level keys)', () {
      final input = <String, dynamic>{
        'id': 'top-level-id',
        'metadata': {
          // Nested keys with the same names should NOT be stripped.
          'id': 'nested-id',
          'user_id': 'nested-user',
          'value': 1,
        },
        'title': 'Project',
      };

      final result = stripServerManagedFields(input);

      expect(result.containsKey('id'), isFalse);
      expect(result['title'], equals('Project'));
      expect(result['metadata'], isA<Map<String, dynamic>>());
      final metadata = result['metadata'] as Map<String, dynamic>;
      expect(metadata['id'], equals('nested-id'));
      expect(metadata['user_id'], equals('nested-user'));
      expect(metadata['value'], equals(1));
    });

    test('preserves keys with similar names but exact-match semantics', () {
      // Only the exact strings in serverManagedFields are stripped.
      final input = <String, dynamic>{
        'id': 'stripped',
        'ids': 'kept',
        'user_id': 'stripped',
        'user_ids': 'kept',
        'updated_at': 'stripped',
        'updated': 'kept',
      };

      final result = stripServerManagedFields(input);

      expect(result, equals({
        'ids': 'kept',
        'user_ids': 'kept',
        'updated': 'kept',
      }));
    });

    test('preserves explicit null values for non-managed keys', () {
      final input = <String, dynamic>{
        'updated_at': '2024-01-01',
        'optional_note': null,
      };
      final result = stripServerManagedFields(input);

      expect(result.containsKey('updated_at'), isFalse);
      expect(result.containsKey('optional_note'), isTrue);
      expect(result['optional_note'], isNull);
    });

    test('handles list values without recursing into them', () {
      final input = <String, dynamic>{
        'id': 'stripped',
        'tag_ids': ['a', 'b'],
        // Keys nested inside a list are not stripped — caller's responsibility.
        'history': [
          {'id': 'nested-id', 'value': 1},
        ],
      };

      final result = stripServerManagedFields(input);

      expect(result.containsKey('id'), isFalse);
      expect(result['tag_ids'], equals(['a', 'b']));
      final historyEntry = (result['history'] as List).first as Map;
      expect(historyEntry['id'], equals('nested-id'));
    });

    test('output contains only non-server-managed keys (set check)', () {
      final input = <String, dynamic>{
        for (final field in serverManagedFields) field: 'x',
        'title': 't',
        'description': 'd',
      };

      final result = stripServerManagedFields(input);

      expect(result.keys.toSet(), equals({'title', 'description'}));
    });

    test('repeated calls are stable (idempotent)', () {
      final input = <String, dynamic>{
        'id': 'x',
        'title': 't',
      };
      final once = stripServerManagedFields(input);
      final twice = stripServerManagedFields(once);
      expect(twice, equals(once));
    });
  });

  group('serverManagedFields integrity', () {
    test('is unmodifiable / treated as constant', () {
      expect(
        () => (serverManagedFields as dynamic).add('new_field'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('contains only snake_case names matching server contract', () {
      for (final field in serverManagedFields) {
        expect(
          RegExp(r'^[a-z_]+$').hasMatch(field),
          isTrue,
          reason: 'field "$field" should be snake_case',
        );
      }
    });
  });
}
