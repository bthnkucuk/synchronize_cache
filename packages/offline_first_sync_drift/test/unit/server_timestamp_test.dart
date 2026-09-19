import 'package:offline_first_sync_drift/src/server_timestamp.dart';
import 'package:test/test.dart';

void main() {
  group('parseServerTimestamp', () {
    final expected = DateTime.utc(2024, 1, 1, 10, 0, 0, 123, 456);

    test('reads a zone-less ISO string as UTC, in every device time zone', () {
      final parsed = parseServerTimestamp('2024-01-01T10:00:00.123456');
      expect(parsed.isUtc, isTrue);
      expect(parsed, equals(expected));
    });

    test('keeps the instant of a Z-suffixed string', () {
      expect(parseServerTimestamp('2024-01-01T10:00:00.123456Z'), expected);
    });

    test('applies an explicit offset', () {
      expect(
        parseServerTimestamp('2024-01-01T13:00:00.123456+03:00'),
        equals(expected),
      );
    });

    test('converts a local DateTime by its own zone', () {
      final local = expected.toLocal();
      final parsed = parseServerTimestamp(local);
      expect(parsed.isUtc, isTrue);
      expect(parsed.isAtSameMomentAs(expected), isTrue);
    });

    test('returns a UTC DateTime unchanged', () {
      expect(parseServerTimestamp(expected), same(expected));
    });

    test('throws FormatException for an unparseable value', () {
      expect(() => parseServerTimestamp('yesterday'), throwsFormatException);
    });
  });
}
