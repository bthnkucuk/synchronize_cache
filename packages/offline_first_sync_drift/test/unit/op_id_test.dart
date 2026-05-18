import 'package:offline_first_sync_drift/src/op_id.dart';
import 'package:test/test.dart';

void main() {
  group('OpId.v4', () {
    test('produces a non-empty string', () {
      final id = OpId.v4();
      expect(id, isNotEmpty);
    });

    test('produces a 36-character string (32 hex + 4 dashes)', () {
      final id = OpId.v4();
      expect(id.length, equals(36));
    });

    test('matches RFC 4122 UUID v4 textual layout (8-4-4-4-12)', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      final id = OpId.v4();
      expect(pattern.hasMatch(id), isTrue, reason: 'id was: $id');
    });

    test('uses lowercase hex characters only', () {
      final id = OpId.v4();
      expect(id, equals(id.toLowerCase()));
    });

    test('places dashes at positions 8, 13, 18, 23', () {
      final id = OpId.v4();
      expect(id[8], equals('-'));
      expect(id[13], equals('-'));
      expect(id[18], equals('-'));
      expect(id[23], equals('-'));
    });

    test('encodes version 4 nibble at position 14', () {
      final id = OpId.v4();
      expect(id[14], equals('4'));
    });

    test('encodes RFC 4122 variant (10xx) at position 19', () {
      final id = OpId.v4();
      // Position 19 must be one of 8, 9, a, b.
      expect(
        ['8', '9', 'a', 'b'].contains(id[19]),
        isTrue,
        reason: 'variant nibble was: ${id[19]} in $id',
      );
    });

    test('two consecutive calls produce different ids', () {
      final a = OpId.v4();
      final b = OpId.v4();
      expect(a, isNot(equals(b)));
    });

    test('a thousand calls produce no collisions', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(OpId.v4());
      }
      expect(ids.length, equals(1000));
    });

    test('all generated ids match the v4 pattern across many calls', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (var i = 0; i < 200; i++) {
        final id = OpId.v4();
        expect(pattern.hasMatch(id), isTrue, reason: 'failed for: $id');
      }
    });

    test('contains exactly 4 dashes', () {
      final id = OpId.v4();
      expect(id.split('-').length, equals(5));
    });

    test('non-dash segments contain only hex characters', () {
      final hexOnly = RegExp(r'^[0-9a-f]+$');
      final segments = OpId.v4().split('-');
      for (final s in segments) {
        expect(hexOnly.hasMatch(s), isTrue, reason: 'segment: $s');
      }
    });
  });
}
