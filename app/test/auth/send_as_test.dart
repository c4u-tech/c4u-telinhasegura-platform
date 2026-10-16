import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/token_store.dart';

import 'fakes.dart';

void main() {
  test('sendAs uses the given bearer and never refreshes', () async {
    final seen = <http.Request>[];
    final t = build(
      ClientKind.mobile,
      (_) => problem(401, 'unauthenticated'),
      seen: seen,
    );
    await t.client.saveTokens(const Tokens(access: 'a', refresh: 'r'));

    await expectLater(
      t.client.sendAs('dev', 'GET', '/v1/child/profile'),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
    );
    expect(t.calls, ['GET /v1/child/profile']);
    expect(seen.single.headers['Authorization'], 'Bearer dev');
    // A device's 401 is not the guardian session's.
    expect(t.client.status.value, AuthStatus.signedIn);
  });

  test('sendAs sends no CSRF header on the web', () async {
    final seen = <http.Request>[];
    final t = build(ClientKind.web, (_) => json(200, {}), seen: seen);
    await t.client.sendAs(
      'dev',
      'POST',
      '/v1/child/profiles',
      body: {'pin': '2580'},
    );
    expect(seen.single.headers['X-CSRF-Token'], isNull);
    expect(seen.single.headers['Content-Type'], startsWith('application/json'));
  });
}
