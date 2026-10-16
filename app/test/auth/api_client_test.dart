import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/token_store.dart';

import 'fakes.dart';

void main() {
  group('mobile', () {
    test('requests carry the stored access token', () async {
      final store = MemoryTokenStore()
        ..tokens = const Tokens(access: 'a1', refresh: 'r1');
      final client = ApiClient(
        baseUrl: baseUrl,
        kind: ClientKind.mobile,
        tokens: store,
        httpClient: MockClient((req) async {
          expect(req.headers['authorization'], 'Bearer a1');
          expect(req.headers.containsKey('x-csrf-token'), isFalse);
          return json(200, {'ok': true});
        }),
      );

      expect(await client.send('GET', '/v1/session'), {'ok': true});
    });

    test('concurrent 401s share one refresh, then retry', () async {
      final store = MemoryTokenStore()
        ..tokens = const Tokens(access: 'old', refresh: 'r1');
      var refreshes = 0;
      final client = ApiClient(
        baseUrl: baseUrl,
        kind: ClientKind.mobile,
        tokens: store,
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/session/refresh') {
            refreshes++;
            expect(req.body, '{"refresh_token":"r1"}');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return json(200, {
              'session_id': 's',
              'access_token': 'new',
              'access_expires_at': '2026-10-02T12:15:00Z',
              'refresh_token': 'r2',
            });
          }
          return req.headers['authorization'] == 'Bearer new'
              ? json(200, {'ok': true})
              : problem(401, 'unauthenticated');
        }),
      );

      final results = await Future.wait([
        client.send('GET', '/v1/sessions'),
        client.send('GET', '/v1/session'),
      ]);

      expect(results, [
        {'ok': true},
        {'ok': true},
      ]);
      expect(refreshes, 1);
      expect(store.tokens?.refresh, 'r2');
    });

    test('a failed refresh clears the tokens and reports signed out', () async {
      final store = MemoryTokenStore()
        ..tokens = const Tokens(access: 'old', refresh: 'reused');
      final client = ApiClient(
        baseUrl: baseUrl,
        kind: ClientKind.mobile,
        tokens: store,
        httpClient: MockClient(
          (req) async => req.url.path == '/v1/session/refresh'
              ? problem(401, 'invalid_token')
              : problem(401, 'unauthenticated'),
        ),
      );

      await expectLater(
        client.send('GET', '/v1/session'),
        throwsA(
          isA<ApiError>().having((e) => e.code, 'code', 'unauthenticated'),
        ),
      );
      expect(store.tokens, isNull);
      expect(client.status.value, AuthStatus.signedOut);
    });

    test(
      'a transient refresh failure keeps the session and surfaces the error',
      () async {
        final store = MemoryTokenStore()
          ..tokens = const Tokens(access: 'old', refresh: 'r1');
        final client = ApiClient(
          baseUrl: baseUrl,
          kind: ClientKind.mobile,
          tokens: store,
          httpClient: MockClient(
            (req) async => req.url.path == '/v1/session/refresh'
                ? problem(429, 'rate_limited', headers: {'retry-after': '5'})
                : problem(401, 'unauthenticated'),
          ),
        );

        await expectLater(
          client.send('GET', '/v1/session'),
          throwsA(
            isA<ApiError>()
                .having((e) => e.code, 'code', 'rate_limited')
                .having(
                  (e) => e.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 5),
                ),
          ),
        );
        expect(store.tokens?.refresh, 'r1');
        expect(client.status.value, isNot(AuthStatus.signedOut));
      },
    );
  });

  group('web', () {
    test('unsafe requests echo the CSRF token and send no bearer', () async {
      final client = ApiClient(
        baseUrl: baseUrl,
        kind: ClientKind.web,
        httpClient: MockClient((req) async {
          expect(req.headers.containsKey('authorization'), isFalse);
          expect(req.headers['x-csrf-token'], 'c1');
          return http.Response('', 204);
        }),
      )..rememberSession(csrfToken: 'c1');

      await client.send('DELETE', '/v1/session');
      expect(client.status.value, AuthStatus.signedIn);
    });

    test(
      'after a reload the CSRF token is fetched from GET /v1/session',
      () async {
        final seen = <String>[];
        final client = ApiClient(
          baseUrl: baseUrl,
          kind: ClientKind.web,
          httpClient: MockClient((req) async {
            seen.add('${req.method} ${req.url.path}');
            if (req.method == 'GET') {
              return json(200, {
                'account': {
                  'id': 'a',
                  'email': 'ana@example.com',
                  'email_verified': true,
                },
                'session': {'id': 's', 'client': 'web', 'csrf_token': 'c2'},
              });
            }
            expect(req.headers['x-csrf-token'], 'c2');
            return http.Response('', 204);
          }),
        );

        await client.send('DELETE', '/v1/session');
        expect(seen, ['GET /v1/session', 'DELETE /v1/session']);
      },
    );
  });

  test('problem responses become typed ApiErrors', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.web,
      httpClient: MockClient(
        (req) async => req.url.path == '/v1/accounts'
            ? problem(422, 'weak_password', reasons: ['too_short'])
            : problem(429, 'rate_limited', headers: {'retry-after': '7'}),
      ),
    );

    await expectLater(
      client.send('POST', '/v1/accounts', body: {}, auth: false),
      throwsA(
        isA<ApiError>().having((e) => e.code, 'code', 'weak_password').having(
          (e) => e.reasons,
          'reasons',
          ['too_short'],
        ),
      ),
    );
    await expectLater(
      client.send('POST', '/v1/sessions', body: {}, auth: false),
      throwsA(
        isA<ApiError>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 7),
        ),
      ),
    );
  });

  test(
    'retryAfter falls back to the problem body without the header',
    () async {
      final client = ApiClient(
        baseUrl: baseUrl,
        kind: ClientKind.web,
        httpClient: MockClient(
          (req) async => problem(429, 'rate_limited', retryAfterBody: 9),
        ),
      );

      await expectLater(
        client.send('POST', '/v1/sessions', body: {}, auth: false),
        throwsA(
          isA<ApiError>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 9),
          ),
        ),
      );
    },
  );

  test('a baseUrl path prefix is kept', () async {
    final urls = <String>[];
    final client = ApiClient(
      baseUrl: Uri.parse('https://h.test/api'),
      kind: ClientKind.web,
      httpClient: MockClient((req) async {
        urls.add(req.url.toString());
        return json(200, {'ok': true});
      }),
    );

    await client.send('GET', '/v1/session');

    expect(urls, ['https://h.test/api/v1/session']);
  });

  test('web refetches the CSRF token once on csrf_failed', () async {
    final calls = <String>[];
    var issued = 0;
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.web,
      httpClient: MockClient((req) async {
        calls.add(
          '${req.method} ${req.url.path} ${req.headers['x-csrf-token']}',
        );
        if (req.method == 'GET') {
          issued++;
          return json(200, {
            'session': {'csrf_token': 'fresh$issued'},
          });
        }
        return req.headers['x-csrf-token'] == 'fresh1'
            ? http.Response('', 204)
            : problem(403, 'csrf_failed');
      }),
    )..rememberSession(csrfToken: 'stale');

    await client.send('DELETE', '/v1/session');

    expect(calls, [
      'DELETE /v1/session stale',
      'GET /v1/session null',
      'DELETE /v1/session fresh1',
    ]);
  });

  test('a second csrf_failed surfaces as an ApiError', () async {
    var deletes = 0;
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.web,
      httpClient: MockClient((req) async {
        if (req.method == 'GET') {
          return json(200, {
            'session': {'csrf_token': 'fresh'},
          });
        }
        deletes++;
        return problem(403, 'csrf_failed');
      }),
    )..rememberSession(csrfToken: 'stale');

    await expectLater(
      client.send('DELETE', '/v1/session'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'csrf_failed')),
    );
    expect(deletes, 2);
  });
}
