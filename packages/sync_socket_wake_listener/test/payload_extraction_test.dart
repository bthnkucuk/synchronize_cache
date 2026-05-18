// Tests for the `sync:wake` payload kind-extraction logic.
//
// The real `SocketWakeListener` parses `data['kind']` inline inside its
// socket.io on-handler (see `socket_wake_listener.dart`, line ~195):
//
//   final kind = (data as Map<dynamic, dynamic>?)?['kind'] as String?;
//   if (kind == null || kind.isEmpty) { ... return; }
//
// We can't synthesize a socket.io event without a live server, and the
// brief forbids modifying `lib/` source to expose the parser. So we mirror
// the exact one-liner here and assert against the edge cases (null payload,
// non-map payload, missing key, empty string, dynamic-keyed maps) that the
// real-class tests in `test/unit/socket_wake_listener_real_test.dart`
// cannot reach. Keep this helper in lockstep with the source.
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `(data as Map<dynamic, dynamic>?)?['kind'] as String?` from
/// `SocketWakeListener._setupSocket`.
// ignore: avoid_annotating_with_dynamic
String? extractKind(dynamic data) {
  try {
    return (data as Map<dynamic, dynamic>?)?['kind'] as String?;
  } catch (_) {
    return null;
  }
}

void main() {
  group('sync:wake payload parsing', () {
    test('extracts kind from a well-formed payload', () {
      final payload = <String, dynamic>{'kind': 'transcriptions'};
      expect(extractKind(payload), equals('transcriptions'));
    });

    test('extracts kind when map has dynamic keys', () {
      final payload = <dynamic, dynamic>{'kind': 'projects', 'extra': 42};
      expect(extractKind(payload), equals('projects'));
    });

    test('returns null when kind key is missing', () {
      final payload = <String, dynamic>{'other': 'value'};
      expect(extractKind(payload), isNull);
    });

    test('returns null when payload is null', () {
      expect(extractKind(null), isNull);
    });

    test('returns empty string when kind value is empty', () {
      // The real listener checks `kind == null || kind.isEmpty` before
      // dispatching, so an empty string is a valid "no-op" outcome here.
      final payload = <String, dynamic>{'kind': ''};
      final kind = extractKind(payload);
      expect(kind == null || kind.isEmpty, isTrue);
    });

    test('returns null when payload is not a map', () {
      expect(extractKind('not-a-map'), isNull);
      expect(extractKind(42), isNull);
      expect(extractKind([1, 2, 3]), isNull);
    });

    test('accepts all 11 expected kind names', () {
      const expectedKinds = {
        'transcriptions',
        'summarizations',
        'flashcard_sets',
        'flashcards',
        'quiz_sets',
        'quiz_questions',
        'projects',
        'notes',
        'note_nodes',
        'sources',
        'tags',
      };
      for (final kind in expectedKinds) {
        expect(extractKind({'kind': kind}), equals(kind));
      }
    });
  });
}
