import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart';

class _MockDb extends Mock implements SyncDatabaseMixin {}

UpsertOp _upsert(String id) => UpsertOp(
      opId: 'op-$id',
      kind: 'items',
      id: id,
      localTimestamp: DateTime.utc(2024, 1, 1),
      payloadJson: const {'k': 'v'},
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_upsert('fallback'));
    registerFallbackValue(<String>{});
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime.utc(2024));
    registerFallbackValue(<String, String>{});
  });

  group('OutboxService', () {
    late _MockDb db;
    late OutboxService service;

    setUp(() {
      db = _MockDb();
      service = OutboxService(db);
    });

    group('enqueue', () {
      test('delegates to db.enqueue', () async {
        final op = _upsert('1');
        when(() => db.enqueue(any())).thenAnswer((_) async {});

        await service.enqueue(op);

        verify(() => db.enqueue(op)).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.enqueue(any())).thenThrow(Exception('boom'));

        expect(
          () => service.enqueue(_upsert('1')),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('take', () {
      test('forwards limit, kinds and maxTryCountExclusive', () async {
        final ops = [_upsert('1'), _upsert('2')];
        when(
          () => db.takeOutbox(
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
            maxTryCountExclusive: any(named: 'maxTryCountExclusive'),
          ),
        ).thenAnswer((_) async => ops);

        final result = await service.take(
          limit: 50,
          kinds: {'items'},
          maxTryCountExclusive: 5,
        );

        expect(result, hasLength(2));
        verify(
          () => db.takeOutbox(
            limit: 50,
            kinds: {'items'},
            maxTryCountExclusive: 5,
          ),
        ).called(1);
      });

      test('defaults limit to 100 and leaves filters null', () async {
        when(
          () => db.takeOutbox(
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
            maxTryCountExclusive: any(named: 'maxTryCountExclusive'),
          ),
        ).thenAnswer((_) async => <Op>[]);

        await service.take();

        verify(
          () => db.takeOutbox(
            limit: 100,
            kinds: null,
            maxTryCountExclusive: null,
          ),
        ).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(
          () => db.takeOutbox(
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
            maxTryCountExclusive: any(named: 'maxTryCountExclusive'),
          ),
        ).thenThrow(Exception('db fail'));

        expect(
          () => service.take(),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('ack', () {
      test('is a no-op for empty input (does not touch db)', () async {
        await service.ack(<String>[]);

        verifyNever(() => db.ackOutbox(any()));
      });

      test('delegates non-empty ids to db.ackOutbox', () async {
        when(() => db.ackOutbox(any())).thenAnswer((_) async {});

        await service.ack(['a', 'b']);

        verify(() => db.ackOutbox(['a', 'b'])).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.ackOutbox(any())).thenThrow(Exception('boom'));

        expect(
          () => service.ack(['a']),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('purgeOlderThan', () {
      test('returns deleted row count from db', () async {
        final threshold = DateTime.utc(2024, 6, 1);
        when(() => db.purgeOutboxOlderThan(any())).thenAnswer((_) async => 7);

        final n = await service.purgeOlderThan(threshold);

        expect(n, 7);
        verify(() => db.purgeOutboxOlderThan(threshold)).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.purgeOutboxOlderThan(any())).thenThrow(Exception('x'));

        expect(
          () => service.purgeOlderThan(DateTime.utc(2024)),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('hasOperations', () {
      test('returns true when at least one op pending', () async {
        when(
          () => db.takeOutbox(
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
            maxTryCountExclusive: any(named: 'maxTryCountExclusive'),
          ),
        ).thenAnswer((_) async => [_upsert('1')]);

        final has = await service.hasOperations(kinds: {'items'});

        expect(has, isTrue);
        verify(
          () => db.takeOutbox(
            limit: 1,
            kinds: {'items'},
            maxTryCountExclusive: null,
          ),
        ).called(1);
      });

      test('returns false when outbox empty', () async {
        when(
          () => db.takeOutbox(
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
            maxTryCountExclusive: any(named: 'maxTryCountExclusive'),
          ),
        ).thenAnswer((_) async => <Op>[]);

        expect(await service.hasOperations(), isFalse);
      });
    });

    group('watchPendingCount / watchHasOperations', () {
      test('watchPendingCount forwards to db.watchOutboxCount', () async {
        final controller = StreamController<int>();
        when(
          () => db.watchOutboxCount(
            kinds: any(named: 'kinds'),
            maxTryCountExclusive: any(named: 'maxTryCountExclusive'),
          ),
        ).thenAnswer((_) => controller.stream);

        final stream = service.watchPendingCount(
          kinds: {'items'},
          maxTryCountExclusive: 3,
        );

        final received = <int>[];
        final sub = stream.listen(received.add);
        controller
          ..add(0)
          ..add(2);
        await Future<void>.delayed(Duration.zero);

        expect(received, [0, 2]);
        verify(
          () => db.watchOutboxCount(
            kinds: {'items'},
            maxTryCountExclusive: 3,
          ),
        ).called(1);

        await sub.cancel();
        await controller.close();
      });

      test('watchHasOperations maps counts to boolean', () async {
        final controller = StreamController<int>();
        when(
          () => db.watchOutboxCount(
            kinds: any(named: 'kinds'),
            maxTryCountExclusive: any(named: 'maxTryCountExclusive'),
          ),
        ).thenAnswer((_) => controller.stream);

        final received = <bool>[];
        final sub = service.watchHasOperations().listen(received.add);

        controller
          ..add(0)
          ..add(1)
          ..add(5)
          ..add(0);
        await Future<void>.delayed(Duration.zero);

        expect(received, [false, true, true, false]);

        await sub.cancel();
        await controller.close();
      });
    });

    group('incrementTryCount', () {
      test('delegates to db.incrementOutboxTryCount', () async {
        when(() => db.incrementOutboxTryCount(any()))
            .thenAnswer((_) async {});

        await service.incrementTryCount(['a', 'b']);

        verify(() => db.incrementOutboxTryCount(['a', 'b'])).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.incrementOutboxTryCount(any()))
            .thenThrow(Exception('boom'));

        expect(
          () => service.incrementTryCount(['a']),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('recordFailures', () {
      test('forwards errors map and triedAt', () async {
        final triedAt = DateTime.utc(2024, 3, 1);
        when(
          () => db.recordOutboxFailures(
            any(),
            triedAt: any(named: 'triedAt'),
          ),
        ).thenAnswer((_) async {});

        await service.recordFailures(
          {'a': 'err-a', 'b': 'err-b'},
          triedAt: triedAt,
        );

        verify(
          () => db.recordOutboxFailures(
            {'a': 'err-a', 'b': 'err-b'},
            triedAt: triedAt,
          ),
        ).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(
          () => db.recordOutboxFailures(any(), triedAt: any(named: 'triedAt')),
        ).thenThrow(Exception('boom'));

        expect(
          () => service.recordFailures({'a': 'e'}),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('resetTryCount', () {
      test('delegates to db.resetOutboxTryCount', () async {
        when(() => db.resetOutboxTryCount(any())).thenAnswer((_) async {});

        await service.resetTryCount(['a']);

        verify(() => db.resetOutboxTryCount(['a'])).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(() => db.resetOutboxTryCount(any()))
            .thenThrow(Exception('boom'));

        expect(
          () => service.resetTryCount(['a']),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('getStuck', () {
      test('forwards minTryCount, limit and kinds', () async {
        final ops = [_upsert('1')];
        when(
          () => db.getStuckOutbox(
            minTryCount: any(named: 'minTryCount'),
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
          ),
        ).thenAnswer((_) async => ops);

        final result = await service.getStuck(
          minTryCount: 3,
          limit: 50,
          kinds: {'items'},
        );

        expect(result, hasLength(1));
        verify(
          () => db.getStuckOutbox(
            minTryCount: 3,
            limit: 50,
            kinds: {'items'},
          ),
        ).called(1);
      });

      test('defaults limit to 100', () async {
        when(
          () => db.getStuckOutbox(
            minTryCount: any(named: 'minTryCount'),
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
          ),
        ).thenAnswer((_) async => <Op>[]);

        await service.getStuck(minTryCount: 5);

        verify(
          () => db.getStuckOutbox(
            minTryCount: 5,
            limit: 100,
            kinds: null,
          ),
        ).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(
          () => db.getStuckOutbox(
            minTryCount: any(named: 'minTryCount'),
            limit: any(named: 'limit'),
            kinds: any(named: 'kinds'),
          ),
        ).thenThrow(Exception('boom'));

        expect(
          () => service.getStuck(minTryCount: 5),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('countStuck', () {
      test('returns count from db', () async {
        when(
          () => db.countStuckOutbox(
            minTryCount: any(named: 'minTryCount'),
            kinds: any(named: 'kinds'),
          ),
        ).thenAnswer((_) async => 4);

        final n = await service.countStuck(
          minTryCount: 5,
          kinds: {'items'},
        );

        expect(n, 4);
        verify(
          () => db.countStuckOutbox(minTryCount: 5, kinds: {'items'}),
        ).called(1);
      });

      test('wraps db error in DatabaseException', () async {
        when(
          () => db.countStuckOutbox(
            minTryCount: any(named: 'minTryCount'),
            kinds: any(named: 'kinds'),
          ),
        ).thenThrow(Exception('boom'));

        expect(
          () => service.countStuck(minTryCount: 5),
          throwsA(isA<DatabaseException>()),
        );
      });
    });
  });
}
