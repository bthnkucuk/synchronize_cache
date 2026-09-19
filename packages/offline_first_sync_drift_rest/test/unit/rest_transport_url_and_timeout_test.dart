// Regression tests for two RestTransport defects:
//  * entity ids were interpolated into the URL without encoding, so ids such
//    as `a#b`, `a?b`, `a/b` or `..` addressed a different resource;
//  * no request was ever bounded by a timeout, so a stalled connection hung
//    pull/push/health forever.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';
import 'package:test/test.dart';

/// `http.Response(String)` encodes as latin1 and throws for ids like "şehir".
http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  RestTransport buildTransport(
    http.Client client, {
    Uri? base,
    int maxRetries = 0,
    Duration? requestTimeout = const Duration(seconds: 30),
  }) => RestTransport(
    base: base ?? Uri.parse('https://api.example.com/v1'),
    token: () async => 'Bearer test-token',
    client: client,
    backoffMin: const Duration(milliseconds: 1),
    backoffMax: const Duration(milliseconds: 5),
    maxRetries: maxRetries,
    requestTimeout: requestTimeout,
  );

  UpsertOp upsert(String id) => UpsertOp(
    opId: 'op-$id',
    kind: 'todos',
    id: id,
    localTimestamp: DateTime.utc(2024),
    payloadJson: {'id': id, 'title': 'T'},
  );

  DeleteOp delete(String id) => DeleteOp(
    opId: 'op-$id',
    kind: 'todos',
    id: id,
    localTimestamp: DateTime.utc(2024),
  );

  group('entity ids in request URLs', () {
    for (final id in ['a#b', 'a?b', 'a/b', 'a b', 'şehir', '100%', 'a&b=c']) {
      test('upsert sends id "$id" as exactly one path segment', () async {
        final seen = <Uri>[];
        final transport = buildTransport(
          MockClient((req) async {
            seen.add(req.url);
            return jsonResponse({'id': id});
          }),
        );

        final result = await transport.push([upsert(id)]);

        expect(result.results.single.result, isA<PushSuccess>());
        final url = seen.single;
        expect(url.pathSegments, ['v1', 'todos', id]);
        expect(url.fragment, isEmpty);
        expect(url.hasQuery, isFalse);
      });

      test('delete and fetch address id "$id" as one path segment', () async {
        final seen = <Uri>[];
        final transport = buildTransport(
          MockClient((req) async {
            seen.add(req.url);
            return req.method == 'DELETE'
                ? http.Response('', 204)
                : jsonResponse({'id': id});
          }),
        );

        await transport.push([delete(id)]);
        await transport.fetch(kind: 'todos', id: id);

        expect(seen, hasLength(2));
        for (final url in seen) {
          expect(url.pathSegments, ['v1', 'todos', id]);
          expect(url.fragment, isEmpty);
        }
      });
    }

    test('delete keeps _baseUpdatedAt as the only query parameter', () async {
      Uri? seen;
      final transport = buildTransport(
        MockClient((req) async {
          seen = req.url;
          return http.Response('', 204);
        }),
      );

      await transport.push([
        DeleteOp(
          opId: 'op',
          kind: 'todos',
          id: 'a?b',
          localTimestamp: DateTime.utc(2024),
          baseUpdatedAt: DateTime.utc(2024, 1, 2),
        ),
      ]);

      expect(seen!.pathSegments, ['v1', 'todos', 'a?b']);
      expect(seen!.queryParameters, {
        '_baseUpdatedAt': '2024-01-02T00:00:00.000Z',
      });
    });

    for (final id in ['..', '.']) {
      test('id "$id" is rejected without sending a request', () async {
        var requests = 0;
        final transport = buildTransport(
          MockClient((req) async {
            requests++;
            return http.Response('', 204);
          }),
        );

        final pushed = await transport.push([upsert(id), delete(id)]);
        final fetched = await transport.fetch(kind: 'todos', id: id);

        expect(requests, 0, reason: 'dot segments resolve to another resource');
        for (final item in pushed.results) {
          expect(
            item.result,
            isA<PushError>().having(
              (e) => e.error,
              'error',
              isA<TransportException>(),
            ),
          );
        }
        expect(fetched, isA<FetchError>());
      });
    }

    test('delete and fetch reject an empty id instead of hitting the '
        'collection', () async {
      var requests = 0;
      final transport = buildTransport(
        MockClient((req) async {
          requests++;
          return http.Response('', 204);
        }),
      );

      final pushed = await transport.push([delete('')]);
      final fetched = await transport.fetch(kind: 'todos', id: '');

      expect(requests, 0);
      expect(pushed.results.single.result, isA<PushError>());
      expect(fetched, isA<FetchError>());
    });

    test('upsert with an empty id still POSTs to the collection', () async {
      http.BaseRequest? seen;
      final transport = buildTransport(
        MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'id': 'new'}), 201);
        }),
      );

      await transport.push([upsert('')]);

      expect(seen!.method, 'POST');
      expect(seen!.url.pathSegments, ['v1', 'todos']);
    });

    test('a query string on the base URL is kept on every request', () async {
      final seen = <Uri>[];
      final transport = buildTransport(
        MockClient((req) async {
          seen.add(req.url);
          return http.Response(
            jsonEncode({'items': <Map<String, Object?>>[], 'id': 'x'}),
            200,
          );
        }),
        base: Uri.parse('https://api.example.com/v1?tenant=acme'),
      );

      await transport.pull(
        kind: 'todos',
        updatedSince: DateTime.utc(2024),
        pageSize: 10,
      );
      await transport.push([upsert('x')]);

      expect(seen[0].pathSegments, ['v1', 'todos']);
      expect(seen[0].queryParameters['tenant'], 'acme');
      expect(seen[0].queryParameters['limit'], '10');
      expect(seen[1].pathSegments, ['v1', 'todos', 'x']);
      expect(seen[1].queryParameters, {'tenant': 'acme'});
    });
  });

  group('request timeout', () {
    // A connection that accepts the request and then never answers.
    http.Client stalled() =>
        MockClient((_) => Completer<http.Response>().future);

    // Guards the suite: before the fix these calls never completed.
    const guard = Duration(seconds: 5);
    const short = Duration(milliseconds: 40);

    test('pull fails with NetworkException instead of hanging', () async {
      final transport = buildTransport(stalled(), requestTimeout: short);

      await expectLater(
        transport
            .pull(kind: 'todos', updatedSince: DateTime.utc(2024), pageSize: 10)
            .timeout(guard),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.cause,
            'cause',
            isA<TimeoutException>(),
          ),
        ),
      );
    });

    test('push reports a per-op PushError instead of hanging', () async {
      final transport = buildTransport(stalled(), requestTimeout: short);

      final result = await transport.push([upsert('a')]).timeout(guard);

      expect(result.results.single.result, isA<PushError>());
    });

    test('fetch returns FetchError instead of hanging', () async {
      final transport = buildTransport(stalled(), requestTimeout: short);

      final result = await transport
          .fetch(kind: 'todos', id: 'a')
          .timeout(guard);

      expect(result, isA<FetchError>());
    });

    test('health returns false instead of hanging', () async {
      final transport = buildTransport(stalled(), requestTimeout: short);

      expect(await transport.health().timeout(guard), isFalse);
    });

    test(
      'a timed-out attempt is retried like any other network failure',
      () async {
        var attempts = 0;
        final transport = buildTransport(
          MockClient((_) {
            attempts++;
            if (attempts == 1) return Completer<http.Response>().future;
            return Future.value(
              http.Response(jsonEncode({'items': <Object?>[]}), 200),
            );
          }),
          maxRetries: 1,
          requestTimeout: short,
        );

        final page = await transport
            .pull(kind: 'todos', updatedSince: DateTime.utc(2024), pageSize: 10)
            .timeout(guard);

        expect(attempts, 2);
        expect(page.items, isEmpty);
      },
    );

    test('the timeout covers reading the body, not just the headers', () async {
      final transport = buildTransport(
        _StalledBodyClient(),
        requestTimeout: short,
      );

      final result = await transport.push([upsert('a')]).timeout(guard);

      expect(result.results.single.result, isA<PushError>());
    });

    test('requestTimeout: null disables the bound', () async {
      final transport = buildTransport(
        MockClient((_) async {
          await Future<void>.delayed(short * 3);
          return http.Response(jsonEncode({'items': <Object?>[]}), 200);
        }),
        requestTimeout: null,
      );

      final page = await transport
          .pull(kind: 'todos', updatedSince: DateTime.utc(2024), pageSize: 10)
          .timeout(guard);

      expect(page.items, isEmpty);
    });

    test('defaults to 30 seconds', () {
      final transport = RestTransport(
        base: Uri.parse('https://api.example.com'),
        token: () async => '',
        client: stalled(),
      );
      expect(transport.requestTimeout, const Duration(seconds: 30));
    });
  });
}

/// Sends the response headers immediately, then never delivers the body.
class _StalledBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(StreamController<List<int>>().stream, 200);
}
