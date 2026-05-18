// Focused unit tests for RestTransport HTTP status branches and response
// parsing edge cases. These tests complement the existing rest_transport_test
// (happy paths) and the e2e tests (full sync flows) by pinning behavior at
// each request/response boundary.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';
import 'package:test/test.dart';

void main() {
  RestTransport buildTransport(
    MockClient client, {
    int pushConcurrency = 1,
    bool enableBatch = false,
    int batchSize = 100,
    int maxRetries = 3,
    Uri? base,
  }) => RestTransport(
    base: base ?? Uri.parse('https://api.example.com'),
    token: () async => 'Bearer test-token',
    client: client,
    backoffMin: const Duration(milliseconds: 1),
    backoffMax: const Duration(milliseconds: 5),
    maxRetries: maxRetries,
    pushConcurrency: pushConcurrency,
    enableBatch: enableBatch,
    batchSize: batchSize,
  );

  group('Pull parsing edge cases', () {
    test('malformed JSON body on 200 surfaces as FormatException', () async {
      final client = MockClient(
        (req) async => http.Response('not-json{', 200),
      );
      final transport = buildTransport(client);

      await expectLater(
        transport.pull(
          kind: 'thing',
          updatedSince: DateTime.utc(2024),
          pageSize: 10,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('body missing items field returns empty list', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({'nextPageToken': 'tok'}), 200),
      );
      final transport = buildTransport(client);

      final page = await transport.pull(
        kind: 'thing',
        updatedSince: DateTime.utc(2024),
        pageSize: 10,
      );

      expect(page.items, isEmpty);
      expect(page.nextPageToken, 'tok');
    });

    test('explicit null nextPageToken parses to null', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({'items': <Map<String, Object?>>[], 'nextPageToken': null}),
          200,
        ),
      );
      final transport = buildTransport(client);

      final page = await transport.pull(
        kind: 'thing',
        updatedSince: DateTime.utc(2024),
        pageSize: 10,
      );

      expect(page.nextPageToken, isNull);
    });

    test('includeDeleted=false propagates as query parameter', () async {
      String? sawIncludeDeleted;
      final client = MockClient((req) async {
        sawIncludeDeleted = req.url.queryParameters['includeDeleted'];
        return http.Response(
          jsonEncode({'items': <Map<String, Object?>>[]}),
          200,
        );
      });
      final transport = buildTransport(client);

      await transport.pull(
        kind: 'thing',
        updatedSince: DateTime.utc(2024),
        pageSize: 10,
        includeDeleted: false,
      );

      expect(sawIncludeDeleted, 'false');
    });

    test(
      '4xx (400) propagates as TransportException with status + body',
      () async {
        final client = MockClient(
          (req) async => http.Response('bad query', 400),
        );
        final transport = buildTransport(client);

        try {
          await transport.pull(
            kind: 'thing',
            updatedSince: DateTime.utc(2024),
            pageSize: 10,
          );
          fail('expected TransportException');
        } on TransportException catch (e) {
          expect(e.statusCode, 400);
          expect(e.responseBody, 'bad query');
        }
      },
    );

    test('base URL trailing slash is normalised, no double slash', () async {
      Uri? sawUri;
      final client = MockClient((req) async {
        sawUri = req.url;
        return http.Response(
          jsonEncode({'items': <Map<String, Object?>>[]}),
          200,
        );
      });
      final transport = buildTransport(
        client,
        base: Uri.parse('https://api.example.com/'),
      );

      await transport.pull(
        kind: 'thing',
        updatedSince: DateTime.utc(2024),
        pageSize: 10,
      );

      expect(sawUri!.path, '/thing');
    });
  });

  group('Push single (non-batch) parsing edge cases', () {
    test('upsert 2xx with empty body still returns PushSuccess', () async {
      final client = MockClient(
        (req) async => http.Response('', 200, headers: {'etag': 'v7'}),
      );
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isSuccess, isTrue);
      final ok = res.results[0].result as PushSuccess;
      expect(ok.serverData, isNull);
      expect(ok.serverVersion, 'v7');
    });

    test(
      'upsert 2xx with non-JSON body returns PushSuccess and serverData stays null',
      () async {
        final client = MockClient(
          (req) async => http.Response('not-json', 201),
        );
        final transport = buildTransport(client);

        final res = await transport.push([
          UpsertOp(
            opId: 'op-1',
            kind: 'thing',
            id: 'e1',
            localTimestamp: DateTime.now().toUtc(),
            payloadJson: {'name': 'x'},
          ),
        ]);

        expect(res.results[0].isSuccess, isTrue);
        final ok = res.results[0].result as PushSuccess;
        expect(ok.serverData, isNull);
      },
    );

    test('upsert sets X-Idempotency-Key header from opId', () async {
      String? sawKey;
      final client = MockClient((req) async {
        sawKey = req.headers['X-Idempotency-Key'];
        return http.Response('{}', 200);
      });
      final transport = buildTransport(client);

      await transport.push([
        UpsertOp(
          opId: 'unique-op-123',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(sawKey, 'unique-op-123');
    });

    test('upsert with empty id uses POST to /{kind}', () async {
      String? sawMethod;
      String? sawPath;
      final client = MockClient((req) async {
        sawMethod = req.method;
        sawPath = req.url.path;
        return http.Response(jsonEncode({'id': 'srv-1'}), 201);
      });
      final transport = buildTransport(client);

      await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: '',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(sawMethod, 'POST');
      expect(sawPath, '/thing');
    });

    test('upsert 5xx (after retries exhausted) returns PushError', () async {
      final client = MockClient(
        (req) async => http.Response('boom', 500),
      );
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isError, isTrue);
      final err = res.results[0].result as PushError;
      // 500 is not "exceptional" enough to throw — _parseResponse turns it
      // into a PushError wrapping a ClientException once retries are spent.
      expect(err.error, isA<http.ClientException>());
    });

    test('upsert 400 returns PushError (no retry)', () async {
      var attempts = 0;
      final client = MockClient((req) async {
        attempts++;
        return http.Response('bad', 400);
      });
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(attempts, 1, reason: '4xx must not be retried');
      expect(res.results[0].isError, isTrue);
    });

    test('upsert includes _baseUpdatedAt in payload when set', () async {
      Map<String, Object?>? sawPayload;
      final client = MockClient((req) async {
        sawPayload = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response('{}', 200);
      });
      final transport = buildTransport(client);

      final base = DateTime.utc(2024, 6, 1, 12);
      await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
          baseUpdatedAt: base,
        ),
      ]);

      expect(sawPayload!['_baseUpdatedAt'], base.toIso8601String());
    });

    test('forcePush upsert omits _baseUpdatedAt and sends X-Force-Update',
        () async {
      Map<String, Object?>? sawPayload;
      Map<String, String>? sawHeaders;
      final client = MockClient((req) async {
        sawPayload = jsonDecode(req.body) as Map<String, Object?>;
        sawHeaders = req.headers;
        return http.Response('{}', 200);
      });
      final transport = buildTransport(client);

      await transport.forcePush(
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
          baseUpdatedAt: DateTime.utc(2024),
        ),
      );

      expect(sawPayload!.containsKey('_baseUpdatedAt'), isFalse);
      expect(sawHeaders!['X-Force-Update'], 'true');
    });
  });

  group('Push conflict (409) parsing edge cases', () {
    test('409 with empty body falls back to default PushConflict', () async {
      final client = MockClient((req) async => http.Response('', 409));
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isConflict, isTrue);
      final c = res.results[0].result as PushConflict;
      expect(c.serverData, isEmpty);
      expect(c.serverTimestamp, isNotNull);
    });

    test('409 with malformed JSON body falls back to default PushConflict',
        () async {
      final client = MockClient(
        (req) async => http.Response('not-json{', 409),
      );
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isConflict, isTrue);
      final c = res.results[0].result as PushConflict;
      expect(c.serverData, isEmpty);
    });

    test('409 prefers `current` over `serverData` when both present',
        () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'current': {'id': 'e1', 'name': 'current-wins'},
            'serverData': {'id': 'e1', 'name': 'should-not-win'},
          }),
          409,
        ),
      );
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      final c = res.results[0].result as PushConflict;
      expect(c.serverData['name'], 'current-wins');
    });

    test(
      '409 with neither current nor serverData uses raw body as serverData',
      () async {
        final client = MockClient(
          (req) async => http.Response(
            jsonEncode({
              'id': 'e1',
              'name': 'flat-doc',
              'updated_at': '2024-01-15T12:00:00Z',
            }),
            409,
          ),
        );
        final transport = buildTransport(client);

        final res = await transport.push([
          UpsertOp(
            opId: 'op-1',
            kind: 'thing',
            id: 'e1',
            localTimestamp: DateTime.now().toUtc(),
            payloadJson: {'name': 'x'},
          ),
        ]);

        final c = res.results[0].result as PushConflict;
        expect(c.serverData['name'], 'flat-doc');
        expect(
          c.serverTimestamp,
          DateTime.parse('2024-01-15T12:00:00Z').toUtc(),
        );
      },
    );

    test('409 reads ETag header for serverVersion when body lacks one',
        () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'current': {'id': 'e1', 'name': 'x'},
          }),
          409,
          headers: {'etag': 'W/"42"'},
        ),
      );
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      final c = res.results[0].result as PushConflict;
      expect(c.serverVersion, 'W/"42"');
    });

    test('409 falls back to updated_at (snake) when serverTimestamp missing',
        () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'current': {
              'id': 'e1',
              'updated_at': '2024-03-04T05:06:07Z',
            },
          }),
          409,
        ),
      );
      final transport = buildTransport(client);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      final c = res.results[0].result as PushConflict;
      expect(
        c.serverTimestamp,
        DateTime.parse('2024-03-04T05:06:07Z').toUtc(),
      );
    });
  });

  group('Delete operation branches', () {
    test('delete 200 returns PushSuccess', () async {
      final client = MockClient((req) async => http.Response('', 200));
      final transport = buildTransport(client);

      final res = await transport.push([
        DeleteOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
        ),
      ]);

      expect(res.results[0].isSuccess, isTrue);
    });

    test('delete unexpected 418 returns PushError', () async {
      final client = MockClient(
        (req) async => http.Response('teapot', 418),
      );
      final transport = buildTransport(client);

      final res = await transport.push([
        DeleteOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
        ),
      ]);

      expect(res.results[0].isError, isTrue);
      expect(
        (res.results[0].result as PushError).error,
        isA<http.ClientException>(),
      );
    });

    test('delete includes _baseUpdatedAt as query param when set', () async {
      String? sawBase;
      String? sawMethod;
      final client = MockClient((req) async {
        sawMethod = req.method;
        sawBase = req.url.queryParameters['_baseUpdatedAt'];
        return http.Response('', 204);
      });
      final transport = buildTransport(client);

      final base = DateTime.utc(2024, 6, 1, 12);
      await transport.push([
        DeleteOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          baseUpdatedAt: base,
        ),
      ]);

      expect(sawMethod, 'DELETE');
      expect(sawBase, base.toIso8601String());
    });

    test('forcePush delete omits _baseUpdatedAt and sends X-Force-Delete',
        () async {
      Map<String, String>? sawQuery;
      Map<String, String>? sawHeaders;
      final client = MockClient((req) async {
        sawQuery = req.url.queryParameters;
        sawHeaders = req.headers;
        return http.Response('', 204);
      });
      final transport = buildTransport(client);

      await transport.forcePush(
        DeleteOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          baseUpdatedAt: DateTime.utc(2024),
        ),
      );

      expect(sawQuery!.containsKey('_baseUpdatedAt'), isFalse);
      expect(sawHeaders!['X-Force-Delete'], 'true');
    });
  });

  group('Batch push parsing edge cases', () {
    test('batch missing op result yields PushError for that opId', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {'opId': 'op-1', 'statusCode': 200},
            ],
          }),
          200,
        ),
      );
      final transport = buildTransport(client, enableBatch: true);

      final ops = [
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'a'},
        ),
        UpsertOp(
          opId: 'op-2',
          kind: 'thing',
          id: 'e2',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'b'},
        ),
      ];
      final res = await transport.push(ops);

      expect(res.results.length, 2);
      expect(res.results[0].isSuccess, isTrue);
      expect(res.results[1].isError, isTrue);
      expect(
        (res.results[1].result as PushError).error.toString(),
        contains('No result for op op-2'),
      );
    });

    test('batch item with 404 returns PushNotFound', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {'opId': 'op-1', 'statusCode': 404},
            ],
          }),
          200,
        ),
      );
      final transport = buildTransport(client, enableBatch: true);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isNotFound, isTrue);
    });

    test('batch item with 409 + nested error.current parses conflict',
        () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {
                'opId': 'op-1',
                'statusCode': 409,
                'error': {
                  'current': {
                    'id': 'e1',
                    'name': 'server-version',
                    'updated_at': '2024-02-02T02:02:02Z',
                  },
                  'version': 'v9',
                },
              },
            ],
          }),
          200,
        ),
      );
      final transport = buildTransport(client, enableBatch: true);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'local'},
        ),
      ]);

      expect(res.results[0].isConflict, isTrue);
      final c = res.results[0].result as PushConflict;
      expect(c.serverData['name'], 'server-version');
      expect(c.serverVersion, 'v9');
    });

    test('batch item with 500 statusCode → PushError', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {'opId': 'op-1', 'statusCode': 500},
            ],
          }),
          200,
        ),
      );
      final transport = buildTransport(client, enableBatch: true);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isError, isTrue);
      expect(
        (res.results[0].result as PushError).error.toString(),
        contains('500'),
      );
    });

    test('batch missing statusCode defaults to 200 (success)', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {
                'opId': 'op-1',
                // no statusCode field
                'data': {'id': 'e1', 'name': 'ok'},
                'version': 'v1',
              },
            ],
          }),
          200,
        ),
      );
      final transport = buildTransport(client, enableBatch: true);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isSuccess, isTrue);
      final ok = res.results[0].result as PushSuccess;
      expect(ok.serverData!['name'], 'ok');
      expect(ok.serverVersion, 'v1');
    });

    test('batch version coerces non-string (int) to string', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {'opId': 'op-1', 'statusCode': 200, 'version': 42},
            ],
          }),
          200,
        ),
      );
      final transport = buildTransport(client, enableBatch: true);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      final ok = res.results[0].result as PushSuccess;
      expect(ok.serverVersion, '42');
    });

    test('batch response missing `results` key returns PushError per op',
        () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({}), 200),
      );
      final transport = buildTransport(client, enableBatch: true);

      final res = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'thing',
          id: 'e1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'x'},
        ),
      ]);

      expect(res.results[0].isError, isTrue);
      expect(
        (res.results[0].result as PushError).error.toString(),
        contains('No result for op'),
      );
    });

    test('batch malformed JSON wraps to NetworkException PushError', () async {
      final client = MockClient(
        (req) async => http.Response('not-json{', 200),
      );
      final transport = buildTransport(client, enableBatch: true);

      // _pushBatchChunk catches non-SyncException errors and rethrows as
      // NetworkException. That propagates out of push() (no per-op result
      // wrapping for batch failures), so expect the throw.
      await expectLater(
        transport.push([
          UpsertOp(
            opId: 'op-1',
            kind: 'thing',
            id: 'e1',
            localTimestamp: DateTime.now().toUtc(),
            payloadJson: {'name': 'x'},
          ),
        ]),
        throwsA(isA<NetworkException>()),
      );
    });

    test('batch non-2xx (after retries) throws TransportException', () async {
      final client = MockClient(
        (req) async => http.Response('bad', 400),
      );
      final transport = buildTransport(client, enableBatch: true);

      await expectLater(
        transport.push([
          UpsertOp(
            opId: 'op-1',
            kind: 'thing',
            id: 'e1',
            localTimestamp: DateTime.now().toUtc(),
            payloadJson: {'name': 'x'},
          ),
        ]),
        throwsA(
          isA<TransportException>().having(
            (e) => e.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });

    test('batch chunks larger payloads by batchSize', () async {
      final chunkSizes = <int>[];
      final client = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final ops = body['ops'] as List;
        chunkSizes.add(ops.length);
        return http.Response(
          jsonEncode({
            'results':
                ops
                    .cast<Map<String, Object?>>()
                    .map(
                      (op) => {'opId': op['opId'], 'statusCode': 200},
                    )
                    .toList(),
          }),
          200,
        );
      });
      final transport = buildTransport(client, enableBatch: true, batchSize: 2);

      final ops = List.generate(
        5,
        (i) => UpsertOp(
          opId: 'op-$i',
          kind: 'thing',
          id: 'e$i',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'i': i},
        ),
      );
      final res = await transport.push(ops);

      expect(res.results.length, 5);
      expect(chunkSizes, [2, 2, 1]);
    });
  });

  group('Fetch parsing edge cases', () {
    test('fetch malformed JSON body returns FetchError', () async {
      final client = MockClient(
        (req) async => http.Response('not-json{', 200),
      );
      final transport = buildTransport(client);

      final res = await transport.fetch(kind: 'thing', id: 'e1');

      expect(res, isA<FetchError>());
      expect(
        (res as FetchError).error,
        anyOf(isA<NetworkException>(), isA<FormatException>()),
      );
    });

    test('fetch 5xx returns FetchError(TransportException)', () async {
      final client = MockClient(
        (req) async => http.Response('boom', 500),
      );
      final transport = buildTransport(client);

      final res = await transport.fetch(kind: 'thing', id: 'e1');

      expect(res, isA<FetchError>());
      final err = res as FetchError;
      expect(err.error, isA<TransportException>());
      expect((err.error as TransportException).statusCode, 500);
    });

    test('fetch 400 returns FetchError(TransportException)', () async {
      final client = MockClient(
        (req) async => http.Response('bad', 400),
      );
      final transport = buildTransport(client);

      final res = await transport.fetch(kind: 'thing', id: 'e1');

      expect(res, isA<FetchError>());
      expect(
        ((res as FetchError).error as TransportException).statusCode,
        400,
      );
    });

    test('fetch surfaces ETag as version on success', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({'id': 'e1', 'name': 'x'}),
          200,
          headers: {'etag': 'W/"3"'},
        ),
      );
      final transport = buildTransport(client);

      final res = await transport.fetch(kind: 'thing', id: 'e1');

      expect(res, isA<FetchSuccess>());
      expect((res as FetchSuccess).version, 'W/"3"');
    });
  });

  group('Retry behavior', () {
    test('Retry-After header (seconds) is honored', () async {
      var attempts = 0;
      final delays = <Duration>[];
      Stopwatch? sw;
      final client = MockClient((req) async {
        attempts++;
        if (sw != null) delays.add(sw!.elapsed);
        sw = Stopwatch()..start();
        if (attempts < 2) {
          return http.Response(
            'slow down',
            429,
            headers: {'retry-after': '0'},
          );
        }
        return http.Response(
          jsonEncode({'items': <Map<String, Object?>>[]}),
          200,
        );
      });
      final transport = buildTransport(client);

      final page = await transport.pull(
        kind: 'thing',
        updatedSince: DateTime.utc(2024),
        pageSize: 10,
      );

      expect(page.items, isEmpty);
      expect(attempts, 2);
    });

    test(
      'network failure exhausts retries → throws NetworkException with attempt count',
      () async {
        var attempts = 0;
        final client = MockClient((req) async {
          attempts++;
          throw http.ClientException('boom');
        });
        final transport = buildTransport(client, maxRetries: 2);

        try {
          await transport.pull(
            kind: 'thing',
            updatedSince: DateTime.utc(2024),
            pageSize: 10,
          );
          fail('expected NetworkException');
        } on NetworkException catch (e) {
          expect(e.message, contains('Request failed after'));
        }
        // initial + 2 retries == 3
        expect(attempts, 3);
      },
    );

    test('5xx retried until budget exhausted then propagated', () async {
      var attempts = 0;
      final client = MockClient((req) async {
        attempts++;
        return http.Response('boom', 503);
      });
      final transport = buildTransport(client, maxRetries: 2);

      await expectLater(
        transport.pull(
          kind: 'thing',
          updatedSince: DateTime.utc(2024),
          pageSize: 10,
        ),
        throwsA(isA<TransportException>()),
      );

      // initial + 2 retries = 3
      expect(attempts, 3);
    });
  });
}
