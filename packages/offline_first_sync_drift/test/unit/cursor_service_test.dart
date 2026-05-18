import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

class _MockDb extends Mock implements SyncDatabaseMixin {}

class _FakeCursor extends Fake implements Cursor {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeCursor());
  });

  group('CursorService', () {
    late _MockDb db;
    late CursorService service;

    setUp(() {
      db = _MockDb();
      service = CursorService(db);
    });

    group('get', () {
      test('returns cursor from db', () async {
        final cursor = Cursor(ts: DateTime.utc(2024, 1, 1), lastId: 'id-1');
        when(() => db.getCursor('items')).thenAnswer((_) async => cursor);

        final result = await service.get('items');

        expect(result, same(cursor));
        verify(() => db.getCursor('items')).called(1);
      });

      test('returns null when db returns null', () async {
        when(() => db.getCursor(any())).thenAnswer((_) async => null);

        final result = await service.get('items');

        expect(result, isNull);
      });

      test('wraps db error in DatabaseException', () async {
        when(
          () => db.getCursor(any()),
        ).thenThrow(StateError('boom'));

        expect(
          () => service.get('items'),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('set', () {
      test('delegates to db.setCursor', () async {
        final cursor = Cursor(ts: DateTime.utc(2024, 6, 1), lastId: 'x');
        when(
          () => db.setCursor(any(), any()),
        ).thenAnswer((_) async {});

        await service.set('items', cursor);

        verify(() => db.setCursor('items', cursor)).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(
          () => db.setCursor(any(), any()),
        ).thenThrow(Exception('disk full'));

        expect(
          () => service.set(
            'items',
            Cursor(ts: DateTime.utc(2024), lastId: ''),
          ),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('reset', () {
      test('writes epoch cursor with empty lastId', () async {
        Cursor? captured;
        when(() => db.setCursor(any(), any())).thenAnswer((invocation) async {
          captured = invocation.positionalArguments[1] as Cursor;
        });

        await service.reset('items');

        expect(captured, isNotNull);
        expect(captured!.ts, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
        expect(captured!.lastId, isEmpty);
        verify(() => db.setCursor('items', any())).called(1);
      });

      test('propagates DatabaseException from set', () async {
        when(
          () => db.setCursor(any(), any()),
        ).thenThrow(Exception('fail'));

        expect(
          () => service.reset('items'),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('resetAll', () {
      test('delegates to db.resetAllCursors', () async {
        when(() => db.resetAllCursors(any())).thenAnswer((_) async {});

        await service.resetAll({'a', 'b'});

        verify(() => db.resetAllCursors({'a', 'b'})).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.resetAllCursors(any())).thenThrow(Exception('boom'));

        expect(
          () => service.resetAll({'a'}),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('getLastFullResync', () {
      test('returns null when no cursor stored', () async {
        when(() => db.getCursor(CursorKinds.fullResync))
            .thenAnswer((_) async => null);

        final ts = await service.getLastFullResync();

        expect(ts, isNull);
      });

      test('returns cursor timestamp when present', () async {
        final ts = DateTime.utc(2025, 3, 5);
        when(() => db.getCursor(CursorKinds.fullResync))
            .thenAnswer((_) async => Cursor(ts: ts, lastId: ''));

        final result = await service.getLastFullResync();

        expect(result, equals(ts));
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.getCursor(any())).thenThrow(Exception('crash'));

        expect(
          () => service.getLastFullResync(),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('setLastFullResync', () {
      test('writes UTC cursor under full-resync kind', () async {
        Cursor? captured;
        String? capturedKind;
        when(() => db.setCursor(any(), any())).thenAnswer((invocation) async {
          capturedKind = invocation.positionalArguments[0] as String;
          captured = invocation.positionalArguments[1] as Cursor;
        });

        final localTs = DateTime(2024, 1, 1, 12);
        await service.setLastFullResync(localTs);

        expect(capturedKind, CursorKinds.fullResync);
        expect(captured, isNotNull);
        expect(captured!.ts.isUtc, isTrue);
        expect(captured!.ts, equals(localTs.toUtc()));
        expect(captured!.lastId, isEmpty);
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.setCursor(any(), any())).thenThrow(Exception('boom'));

        expect(
          () => service.setLastFullResync(DateTime.utc(2024)),
          throwsA(isA<DatabaseException>()),
        );
      });
    });
  });
}
