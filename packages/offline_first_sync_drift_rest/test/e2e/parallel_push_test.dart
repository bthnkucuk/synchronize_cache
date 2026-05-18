import 'dart:async';
import 'dart:developer' as developer;

import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';
import 'package:test/test.dart';

import 'helpers/test_database.dart';
import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late TestDatabase db;
  var dbClosed = false;

  Future<void> closeDb() async {
    if (dbClosed) return;
    dbClosed = true;
    await db.close();
  }

  setUp(() async {
    server = TestServer();
    await server.start();
    // Disable conflict checks to simplify push logic for this perf test
    server.conflictCheckEnabled = false;

    db = TestDatabase();
    dbClosed = false;
  });

  tearDown(() async {
    await closeDb();
    await server.stop();
  });

  SyncEngine createEngine(int concurrency) {
    final transport = RestTransport(
      base: server.baseUrl,
      token: () async => 'Bearer test-token',
      pushConcurrency: concurrency,
    );

    return SyncEngine(
      db: db,
      transport: transport,
      tables: [
        SyncableTable<TestEntity>(
          kind: 'test_entity',
          table: db.testEntities,
          fromJson: TestEntity.fromJson,
          toJson: (item) => item.toJson(),
          toInsertable: (item) => item.toInsertable(),
        ),
      ],
      config: const SyncConfig(
        pushImmediately: false, // We want to accumulate ops first
      ),
    );
  }

  test('parallel push is faster than sequential push with latency', () async {
    // Setup: Create 10 operations
    const opCount = 10;
    const requestDelay = Duration(milliseconds: 50);

    // Create ops in DB
    for (var i = 0; i < opCount; i++) {
      await db.enqueue(UpsertOp(
        opId: 'op-$i',
        kind: 'test_entity',
        id: 'entity-$i',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-$i', 'name': 'Item $i'},
      ));
    }

    // --- Run 1: Sequential (concurrency = 1) ---
    server.delayNextRequests(requestDelay, count: opCount);
    
    final engine1 = createEngine(1);
    final stopwatch1 = Stopwatch()..start();
    await engine1.sync(); // Will trigger push
    stopwatch1.stop();
    engine1.dispose();

    // Verify sequential timing: roughly opCount * delay
    // 10 * 50ms = 500ms minimum
    developer.log(
      'Sequential time: ${stopwatch1.elapsedMilliseconds}ms',
      name: 'ParallelPushTest',
    );
    expect(stopwatch1.elapsedMilliseconds, greaterThanOrEqualTo(opCount * requestDelay.inMilliseconds));

    // Reset server stats and DB outbox for next run
    server
      ..clear()
      ..conflictCheckEnabled = false;
    
    // Re-enqueue ops since they were acked
    for (var i = 0; i < opCount; i++) {
      await db.enqueue(UpsertOp(
        opId: 'op-$i',
        kind: 'test_entity',
        id: 'entity-$i',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-$i', 'name': 'Item $i'},
      ));
    }

    // --- Run 2: Parallel (concurrency = 5) ---
    // Should take roughly (opCount / 5) * delay
    // 2 batches * 50ms = 100ms minimum
    server.delayNextRequests(requestDelay, count: opCount);

    final engine2 = createEngine(5);
    final stopwatch2 = Stopwatch()..start();
    await engine2.sync();
    stopwatch2.stop();
    engine2.dispose();

    developer.log(
      'Parallel time: ${stopwatch2.elapsedMilliseconds}ms',
      name: 'ParallelPushTest',
    );
    
    // Check that parallel is significantly faster
    // Ideally it should be close to 1/5th of the time, but let's be conservative and say it should be at least 2x faster
    expect(stopwatch2.elapsedMilliseconds, lessThan(stopwatch1.elapsedMilliseconds * 0.6));
    
    // Verify all requests reached server
    expect(server.requestCounts['PUT'], opCount);
  });
}

