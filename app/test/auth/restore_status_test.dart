import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/token_store.dart';

import 'fakes.dart';

/// `ApiClient.restoreStatus` settles the start-up status:
/// the splash shows only while it is `unknown`.
void main() {
  final sessionBody = {
    'account': {'id': 'a', 'email': 'ana@example.com', 'email_verified': true},
    'session': {'id': 's', 'client': 'web', 'csrf_token': 'c9'},
  };

  test(
    'web: a live cookie session signs in and keeps its CSRF token',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: baseUrl,
        kind: ClientKind.web,
        httpClient: MockClient((req) async {
          seen.add(
            '${req.method} ${req.url.path} ${req.headers['x-csrf-token']}',
          );
          return req.method == 'GET'
              ? json(200, sessionBody)
              : http.Response('', 204);
        }),
      );

      await client.restoreStatus();
      await client.send('DELETE', '/v1/session');

      expect(client.status.value, AuthStatus.signedIn);
      expect(seen, ['GET /v1/session null', 'DELETE /v1/session c9']);
    },
  );

  test('web: no session signs out', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.web,
      httpClient: MockClient((_) async => problem(401, 'unauthenticated')),
    );

    await client.restoreStatus();

    expect(client.status.value, AuthStatus.signedOut);
  });

  test('web: an unreachable server signs out', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.web,
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );

    await client.restoreStatus();

    expect(client.status.value, AuthStatus.signedOut);
  });

  test('mobile: no stored tokens signs out without a request', () async {
    var requests = 0;
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.mobile,
      tokens: MemoryTokenStore(),
      httpClient: MockClient((_) async {
        requests++;
        return json(200, sessionBody);
      }),
    );

    await client.restoreStatus();

    expect(client.status.value, AuthStatus.signedOut);
    expect(requests, 0);
  });

  test('mobile: stored tokens the server accepts sign in', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.mobile,
      tokens: MemoryTokenStore()
        ..tokens = const Tokens(access: 'a', refresh: 'r'),
      httpClient: MockClient((_) async => json(200, sessionBody)),
    );

    await client.restoreStatus();

    expect(client.status.value, AuthStatus.signedIn);
  });

  test('mobile: refused tokens sign out and are cleared', () async {
    final store = MemoryTokenStore()
      ..tokens = const Tokens(access: 'a', refresh: 'r');
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.mobile,
      tokens: store,
      httpClient: MockClient((_) async => problem(401, 'unauthenticated')),
    );

    await client.restoreStatus();

    expect(client.status.value, AuthStatus.signedOut);
    expect(store.tokens, isNull);
  });

  test('mobile: an unreachable server keeps the stored session', () async {
    final store = MemoryTokenStore()
      ..tokens = const Tokens(access: 'a', refresh: 'r');
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: ClientKind.mobile,
      tokens: store,
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );

    await client.restoreStatus();

    expect(client.status.value, AuthStatus.signedIn);
    expect(store.tokens, isNotNull);
  });
}
