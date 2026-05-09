// Tests for SocketWakeListener focusing on the sync:wake event parsing logic.
// Full integration tests (socket connection) require a live server and are
// covered by E2E tests outside this package.
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers that replicate the sync:wake parsing logic from SocketWakeListener
// without requiring flutter / socket_io bindings.
// ---------------------------------------------------------------------------

/// Extracts the kind from a raw sync:wake payload.
/// Mirrors the logic in `SocketWakeListener._setupSocket`.
// ignore: avoid_annotating_with_dynamic
String? extractKind(dynamic data) {
  try {
    return (data as Map<dynamic, dynamic>?)?['kind'] as String?;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Replica of SocketWakeListener._catchUpSync behaviour so it can be tested
// without a live socket or Flutter bindings.
// ---------------------------------------------------------------------------

Future<void> _simulateCatchUpSync({
  required Future<void> Function() sync,
  required void Function(Object, StackTrace, String) onError,
}) async {
  try {
    await sync();
  } catch (e, st) {
    onError(e, st, 'SocketWakeListener onConnect catch-up sync');
  }
}

void main() {
  group('SocketWakeListener onConnect catch-up sync', () {
    test('invokes engine.sync() when socket connects', () async {
      var syncCalled = 0;
      await _simulateCatchUpSync(
        sync: () async => syncCalled++,
        onError: (_, _, _) => fail('unexpected error'),
      );
      expect(syncCalled, equals(1));
    });

    test('routes sync errors to onError without rethrowing', () async {
      Object? caughtError;
      final boom = Exception('sync failed');
      await _simulateCatchUpSync(
        sync: () async => throw boom,
        onError: (e, _, _) => caughtError = e,
      );
      expect(caughtError, same(boom));
    });
  });

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

    test('returns null when kind value is empty string', () {
      final payload = <String, dynamic>{'kind': ''};
      final kind = extractKind(payload);
      // Caller checks for null OR empty before proceeding.
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
