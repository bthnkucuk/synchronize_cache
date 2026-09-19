// What RestTransport reports when a push does not go through, and when it
// stops sending the rest of a batch.
//
//  * An HTTP failure used to come back as `http.ClientException('Push failed
//    401')`: the status only existed inside a string, so the engine could not
//    tell an expired token or a server outage from a rejected operation.
//  * With the network gone every op of the batch was still sent, each one
//    running through all of its retries and timeouts first.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';
import 'package:test/test.dart';

void main() {
  RestTransport buildTransport(
    http.Client client, {
    int pushConcurrency = 1,
    bool enableBatch = false,
  }) => RestTransport(
    base: Uri.parse('https://api.example.com'),
    token: () async => 'Bearer expired',
    client: client,
    backoffMin: const Duration(milliseconds: 1),
    backoffMax: const Duration(milliseconds: 2),
    maxRetries: 1,
    pushConcurrency: pushConcurrency,
    enableBatch: enableBatch,
  );

  UpsertOp upsert(int n, {Map<String, Object?>? payload}) => UpsertOp(
    opId: 'op-$n',
    kind: 'todos',
    id: 'id-$n',
    localTimestamp: DateTime.utc(2026),
    payloadJson: payload ?? {'id': 'id-$n', 'title': 'T$n'},
  );

  DeleteOp delete(int n) => DeleteOp(
    opId: 'op-$n',
    kind: 'todos',
    id: 'id-$n',
    localTimestamp: DateTime.utc(2026),
  );

  Object errorOf(OpPushResult result) => (result.result as PushError).error;

  group('an HTTP failure keeps its status', () {
    for (final status in [400, 401, 403, 413, 422]) {
      test('upsert $status', () async {
        final transport = buildTransport(
          MockClient((_) async => http.Response('{"why":"$status"}', status)),
        );

        final result = await transport.push([upsert(1)]);

        expect(
          errorOf(result.results.single),
          isA<TransportException>()
              .having((e) => e.statusCode, 'statusCode', status)
              .having((e) => e.responseBody, 'body', '{"why":"$status"}'),
        );
      });

      test('delete $status', () async {
        final transport = buildTransport(
          MockClient((_) async => http.Response('', status)),
        );

        final result = await transport.push([delete(1)]);

        expect(
          errorOf(result.results.single),
          isA<TransportException>().having(
            (e) => e.statusCode,
            'statusCode',
            status,
          ),
        );
      });
    }

    test('so the engine can tell what kind of failure it was', () async {
      SyncErrorInfo infoFor(int status) =>
          SyncErrorInfo.fromError(TransportException.httpError(status));
      final transport = buildTransport(
        MockClient((_) async => http.Response('', 401)),
      );

      final result = await transport.push([upsert(1)]);
      final info = SyncErrorInfo.fromError(errorOf(result.results.single));

      expect(info.category, SyncErrorCategory.auth);
      expect(info.statusCode, 401);
      expect(info.isEnvironmental, isTrue);
      expect(infoFor(422).isEnvironmental, isFalse);
    });

    test('a failed op of a batch response', () async {
      final transport = buildTransport(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'results': [
                {
                  'opId': 'op-1',
                  'statusCode': 422,
                  'error': {'title': 'too long'},
                },
                {'opId': 'op-2', 'statusCode': 503},
              ],
            }),
            200,
          ),
        ),
        enableBatch: true,
      );

      final result = await transport.push([upsert(1), upsert(2)]);

      expect(
        errorOf(result.results[0]),
        isA<TransportException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.responseBody, 'body', '{"title":"too long"}'),
      );
      expect(
        errorOf(result.results[1]),
        isA<TransportException>().having((e) => e.statusCode, 'status', 503),
      );
    });

    test('an op the batch response does not mention', () async {
      final transport = buildTransport(
        MockClient(
          (_) async => http.Response(jsonEncode({'results': <Object>[]}), 200),
        ),
        enableBatch: true,
      );

      final result = await transport.push([upsert(1)]);

      expect(errorOf(result.results.single), isA<TransportException>());
    });
  });

  group('the rest of a batch is not sent', () {
    test('once the network is gone', () async {
      final requested = <String>[];
      final transport = buildTransport(
        MockClient((req) async {
          requested.add(req.url.pathSegments.last);
          throw http.ClientException('Connection refused');
        }),
      );

      final result = await transport.push([
        for (var n = 1; n <= 5; n++) upsert(n),
      ]);

      // Only the first op went out (with its one retry).
      expect(requested, ['id-1', 'id-1']);
      expect(result.results.map((r) => r.opId), [
        'op-1',
        'op-2',
        'op-3',
        'op-4',
        'op-5',
      ]);
      for (final item in result.results) {
        expect(errorOf(item), isA<NetworkException>());
      }
    });

    test('once the token was rejected (401)', () async {
      var requests = 0;
      final transport = buildTransport(
        MockClient((_) async {
          requests++;
          return http.Response('', 401);
        }),
      );

      final result = await transport.push([upsert(1), delete(2), upsert(3)]);

      expect(requests, 1);
      for (final item in result.results) {
        expect(
          errorOf(item),
          isA<TransportException>().having((e) => e.statusCode, 'status', 401),
        );
      }
    });

    test('with pushConcurrency > 1, after the chunk that found out', () async {
      var requests = 0;
      final transport = buildTransport(
        MockClient((_) async {
          requests++;
          return http.Response('', 401);
        }),
        pushConcurrency: 2,
      );

      final result = await transport.push([
        for (var n = 1; n <= 6; n++) upsert(n),
      ]);

      expect(requests, 2);
      expect(result.results, hasLength(6));
      expect(result.results.every((r) => r.result is PushError), isTrue);
    });
  });

  group('the batch goes on', () {
    for (final status in [403, 422, 500]) {
      test('after a $status: it may be about that one op', () async {
        final requested = <String>[];
        final transport = buildTransport(
          MockClient((req) async {
            requested.add(req.url.pathSegments.last);
            return req.url.pathSegments.last == 'id-1'
                ? http.Response('', status)
                : http.Response(jsonEncode({'id': 'x'}), 200);
          }),
        );

        final result = await transport.push([upsert(1), upsert(2), upsert(3)]);

        expect(requested.toSet(), {'id-1', 'id-2', 'id-3'});
        expect(result.results[0].result, isA<PushError>());
        expect(result.results[1].result, isA<PushSuccess>());
        expect(result.results[2].result, isA<PushSuccess>());
      });
    }

    test('after a payload that cannot be encoded: no request, no retries, '
        'and it is that op\'s problem', () async {
      final requested = <String>[];
      final transport = buildTransport(
        MockClient((req) async {
          requested.add(req.url.pathSegments.last);
          return http.Response(jsonEncode({'id': 'x'}), 200);
        }),
      );

      final result = await transport.push([
        upsert(1, payload: {'id': 'id-1', 'when': DateTime.utc(2026)}),
        upsert(2),
      ]);

      expect(requested, ['id-2']);
      final error = errorOf(result.results[0]);
      expect(error, isA<TransportException>());
      expect(SyncErrorInfo.fromError(error).isEnvironmental, isFalse);
      expect(result.results[1].result, isA<PushSuccess>());
    });
  });
}
