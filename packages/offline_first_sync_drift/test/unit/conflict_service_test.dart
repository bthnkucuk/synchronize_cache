import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:test/test.dart' hide isNull, isNotNull;

import '../sync_engine_test.dart' show TestDatabase, TestItem;
import '../sync_engine_test.drift.dart';

// Behavioral tests for ConflictService that complement
// conflict_service_types_test.dart (which only covers value types).
//
// Strategy: real in-memory drift database (so insertOnConflictUpdate works
// for AcceptServer / AcceptMerged paths) + mocktail TransportAdapter (so we
// can shape forcePush results for AcceptClient/AcceptMerged retry loops).

class _MockTransport extends Mock implements TransportAdapter {}

UpsertOp _upsert({
  String id = 'item-1',
  String kind = 'test_item',
  Map<String, Object?>? payload,
  DateTime? localTimestamp,
  Set<String>? changedFields,
}) =>
    UpsertOp(
      opId: 'op-$id',
      kind: kind,
      id: id,
      localTimestamp: localTimestamp ?? DateTime.utc(2024, 6, 1, 12),
      payloadJson: payload ??
          <String, Object?>{
            'id': id,
            'updated_at': '2024-06-01T12:00:00.000Z',
            'name': 'Local',
          },
      changedFields: changedFields,
    );

DeleteOp _delete({
  String id = 'item-1',
  String kind = 'test_item',
}) =>
    DeleteOp(
      opId: 'op-del-$id',
      kind: kind,
      id: id,
      localTimestamp: DateTime.utc(2024, 6, 1),
    );

PushConflict _conflict({
  Map<String, Object?>? serverData,
  DateTime? serverTimestamp,
}) =>
    PushConflict(
      serverData: serverData ??
          {
            'id': 'item-1',
            'updated_at': '2024-06-02T10:00:00.000Z',
            'name': 'Server',
          },
      serverTimestamp: serverTimestamp ?? DateTime.utc(2024, 6, 2, 10),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_upsert());
  });

  late TestDatabase db;
  late _MockTransport transport;
  late StreamController<SyncEvent> events;
  late SyncableTable<TestItem> testItemTable;
  late Map<String, SyncableTable<dynamic>> tables;

  setUp(() {
    db = TestDatabase();
    transport = _MockTransport();
    events = StreamController<SyncEvent>.broadcast();
    testItemTable = SyncableTable<TestItem>(
      kind: 'test_item',
      table: db.testItems,
      fromJson: TestItem.fromJson,
      toJson: (e) => e.toJson(),
      toInsertable: (e) => e.toInsertable(),
      getId: (e) => e.id,
      getUpdatedAt: (e) => e.updatedAt,
    );
    tables = {'test_item': testItemTable};
  });

  tearDown(() async {
    await db.close();
    await events.close();
  });

  ConflictService<TestDatabase> buildService({
    SyncConfig? config,
    Map<String, TableConflictConfig>? tableConfigs,
  }) =>
      ConflictService<TestDatabase>(
        db: db,
        transport: transport,
        tables: tables,
        config: config ?? const SyncConfig(),
        tableConflictConfigs: tableConfigs ?? const {},
        events: events,
      );

  group('strategy: serverWins', () {
    test('writes server data to local and resolves true', () async {
      final captured = <SyncEvent>[];
      final sub = events.stream.listen(captured.add);
      final service = buildService(
        config: const SyncConfig(conflictStrategy: ConflictStrategy.serverWins),
      );

      final op = _upsert();
      final conflict = _conflict();

      final result = await service.resolve(op, conflict);

      expect(result.resolved, isTrue);
      expect(result.resultData, equals(conflict.serverData));

      // Local row reflects server data.
      final rows = await db.select(db.testItems).get();
      expect(rows, hasLength(1));
      expect(rows.first.name, 'Server');

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(captured.whereType<ConflictDetectedEvent>(), hasLength(1));
      expect(captured.whereType<ConflictResolvedEvent>(), hasLength(1));
      verifyNever(() => transport.forcePush(any()));
    });
  });

  group('strategy: clientWins', () {
    test('force-pushes op and resolves true on success', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => const PushSuccess());

      final service = buildService(
        config: const SyncConfig(conflictStrategy: ConflictStrategy.clientWins),
      );

      final op = _upsert();
      final result = await service.resolve(op, _conflict());

      expect(result.resolved, isTrue);
      expect(result.resultData, equals(op.payloadJson));
      verify(() => transport.forcePush(op)).called(1);
    });

    test('retries up to maxConflictRetries on repeat conflicts', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => _conflict());

      final service = buildService(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
          maxConflictRetries: 3,
          conflictRetryDelay: Duration(milliseconds: 1),
        ),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isFalse);
      expect(result.resultData, equals(null));
      verify(() => transport.forcePush(any())).called(3);
    });

    test('returns unresolved on PushError without retrying', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => const PushError('nope'));

      final service = buildService(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
          maxConflictRetries: 5,
        ),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isFalse);
      verify(() => transport.forcePush(any())).called(1);
    });

    test('returns unresolved on PushNotFound', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => const PushNotFound());

      final service = buildService(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
          maxConflictRetries: 5,
        ),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isFalse);
      verify(() => transport.forcePush(any())).called(1);
    });
  });

  group('strategy: lastWriteWins', () {
    test('accepts client when local timestamp is newer', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => const PushSuccess());

      final service = buildService(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.lastWriteWins,
        ),
      );

      final op = _upsert(localTimestamp: DateTime.utc(2024, 12, 31));
      final conflict = _conflict(serverTimestamp: DateTime.utc(2024, 1, 1));

      final result = await service.resolve(op, conflict);

      expect(result.resolved, isTrue);
      verify(() => transport.forcePush(op)).called(1);
    });

    test('accepts server when server timestamp is newer or equal', () async {
      final service = buildService(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.lastWriteWins,
        ),
      );

      final op = _upsert(localTimestamp: DateTime.utc(2024, 1, 1));
      final conflict = _conflict(serverTimestamp: DateTime.utc(2024, 12, 31));

      final result = await service.resolve(op, conflict);

      expect(result.resolved, isTrue);
      // serverWins path → no forcePush.
      verifyNever(() => transport.forcePush(any()));
      expect(result.resultData, equals(conflict.serverData));
    });
  });

  group('strategy: merge', () {
    test('uses global mergeFunction, force-pushes merged data', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => const PushSuccess());

      final service = buildService(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: (l, s) => {
            ...s,
            ...l,
            'extra': 'merged',
          },
        ),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isTrue);
      expect(result.resultData!['extra'], 'merged');
      verify(() => transport.forcePush(any())).called(1);
    });

    test(
      'falls back to ConflictUtils.defaultMerge when no merge function set',
      () async {
        when(() => transport.forcePush(any()))
            .thenAnswer((_) async => const PushSuccess());

        final service = buildService(
          config: const SyncConfig(conflictStrategy: ConflictStrategy.merge),
        );

        final result = await service.resolve(_upsert(), _conflict());

        expect(result.resolved, isTrue);
        // defaultMerge: server + non-null local overrides; local name='Local'
        // should win.
        expect(result.resultData!['name'], 'Local');
      },
    );

    test('per-table merge config overrides global', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => const PushSuccess());

      final service = buildService(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: (l, s) => {'src': 'global'},
        ),
        tableConfigs: {
          'test_item': TableConflictConfig(
            strategy: ConflictStrategy.merge,
            mergeFunction: (l, s) => {
              'id': 'item-1',
              'updated_at': '2024-06-03T00:00:00.000Z',
              'name': 'PerTable',
              'src': 'per-table',
            },
          ),
        },
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isTrue);
      expect(result.resultData!['src'], 'per-table');
    });

    test('returns unresolved if force-push keeps conflicting', () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => _conflict());

      final service = buildService(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: (l, s) => {'merged': true},
          maxConflictRetries: 2,
          conflictRetryDelay: const Duration(milliseconds: 1),
        ),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isFalse);
      verify(() => transport.forcePush(any())).called(2);
    });

    test('AcceptMerged is unresolved for DeleteOp (not an UpsertOp)',
        () async {
      final service = buildService(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: (l, s) => {'x': 1},
        ),
      );

      final result = await service.resolve(_delete(), _conflict());

      expect(result.resolved, isFalse);
      verifyNever(() => transport.forcePush(any()));
    });
  });

  group('strategy: manual', () {
    test('emits ConflictUnresolvedEvent and defers when no resolver',
        () async {
      final captured = <SyncEvent>[];
      final sub = events.stream.listen(captured.add);

      final service = buildService(
        config: const SyncConfig(conflictStrategy: ConflictStrategy.manual),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isFalse);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(captured.whereType<ConflictUnresolvedEvent>(), isNotEmpty);
    });

    test('calls global resolver and applies AcceptServer', () async {
      final service = buildService(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (c) async => const AcceptServer(),
        ),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isTrue);
      final rows = await db.select(db.testItems).get();
      expect(rows.first.name, 'Server');
    });

    test('per-table resolver overrides global, can DiscardOperation',
        () async {
      final service = buildService(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (c) async => const AcceptServer(),
        ),
        tableConfigs: {
          'test_item': TableConflictConfig(
            strategy: ConflictStrategy.manual,
            resolver: (c) async => const DiscardOperation(),
          ),
        },
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isTrue);
      // No data, no transport call.
      expect(result.resultData, equals(null));
      verifyNever(() => transport.forcePush(any()));
      // No row written.
      final rows = await db.select(db.testItems).get();
      expect(rows, isEmpty);
    });

    test('resolver returning DeferResolution leaves unresolved', () async {
      final service = buildService(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (c) async => const DeferResolution(),
        ),
      );

      final result = await service.resolve(_upsert(), _conflict());

      expect(result.resolved, isFalse);
    });
  });

  group('strategy: autoPreserve', () {
    test('merges local and server, force-pushes, emits DataMergedEvent',
        () async {
      when(() => transport.forcePush(any()))
          .thenAnswer((_) async => const PushSuccess());

      final captured = <SyncEvent>[];
      final sub = events.stream.listen(captured.add);

      final service = buildService(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      final op = _upsert(
        payload: {
          'id': 'item-1',
          'updated_at': '2024-06-01T12:00:00.000Z',
          'name': 'Local',
          'note': 'client-side',
        },
        changedFields: {'note'},
      );

      final result = await service.resolve(op, _conflict());

      expect(result.resolved, isTrue);
      expect(result.resultData!['note'], 'client-side');

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(captured.whereType<DataMergedEvent>(), hasLength(1));
    });
  });
}
