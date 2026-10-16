import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/token_store.dart';

import 'fakes.dart';

void main() {
  test('mobile sign-in stores the tokens', () async {
    final t = build(
      ClientKind.mobile,
      (_) => json(201, {
        'session_id': 's',
        'access_token': 'a',
        'access_expires_at': '2026-10-02T12:15:00Z',
        'refresh_token': 'r',
      }),
    );
    await t.api.signIn(
      email: 'ana@example.com',
      password: 'p',
      deviceLabel: 'Pixel 9',
    );

    expect(
      t.calls.single,
      'POST /v1/sessions {"email":"ana@example.com","password":"p",'
      '"client":"mobile","device_label":"Pixel 9"}',
    );
    expect((t.store.tokens?.access, t.store.tokens?.refresh), ('a', 'r'));
  });

  test('web sign-in remembers the CSRF token for unsafe calls', () async {
    final seen = <http.Request>[];
    final t = build(
      ClientKind.web,
      (req) => req.url.path == '/v1/sessions' && req.method == 'POST'
          ? json(201, {'session_id': 's', 'csrf_token': 'fresh'})
          : http.Response('', 204),
      seedCsrf: false,
      seen: seen,
    );
    await t.api.signIn(email: 'ana@example.com', password: 'p');
    await t.api.revokeSession('s2');
    expect(t.calls.last, 'DELETE /v1/sessions/s2');
    expect(seen.last.headers['X-CSRF-Token'], 'fresh');
    expect(t.calls.where((c) => c.startsWith('GET /v1/session')), isEmpty);
  });

  test('every call hits its contract path and body', () async {
    final t = build(ClientKind.web, noContent);
    await t.api.signUp(email: 'a@b.co', password: 'p', adultDeclaration: true);
    await t.api.resendVerification('a@b.co');
    await t.api.confirmEmail('tok');
    await t.api.reauthenticate('p');
    await t.api.revokeSession('id-1');
    await t.api.revokeSessions(includeCurrent: false);
    await t.api.changePassword(current: 'p', next: 'q');
    await t.api.requestEmailChange('n@b.co');
    await t.api.requestPasswordReset('a@b.co');
    await t.api.confirmPasswordReset(token: 'tok', newPassword: 'q');
    await t.api.revokeSessions(
      includeCurrent: true,
    ); // last: forgets the CSRF token

    expect(t.calls, [
      'POST /v1/accounts {"email":"a@b.co","password":"p","adult_declaration":true}',
      'POST /v1/email-verifications {"email":"a@b.co"}',
      'POST /v1/email-verifications/confirm {"token":"tok"}',
      'POST /v1/session/reauth {"password":"p"}',
      'DELETE /v1/sessions/id-1',
      'DELETE /v1/sessions?scope=others',
      'POST /v1/account/password {"current_password":"p","new_password":"q"}',
      'POST /v1/account/email {"new_email":"n@b.co"}',
      'POST /v1/password-resets {"email":"a@b.co"}',
      'POST /v1/password-resets/confirm {"token":"tok","new_password":"q"}',
      'DELETE /v1/sessions?scope=all',
    ]);
  });

  test('currentSession and listSessions parse the contract', () async {
    final t = build(
      ClientKind.web,
      (req) => req.url.path == '/v1/session'
          ? json(200, {
              'account': {
                'id': 'a',
                'email': 'ana@example.com',
                'email_verified': false,
              },
              'session': {'id': 's1', 'client': 'web', 'csrf_token': 'c'},
            })
          : json(200, {
              'sessions': [
                {
                  'id': 's1',
                  'client': 'web',
                  'device_label': '',
                  'created_at': '2026-10-02T12:00:00Z',
                  'last_seen_at': '2026-10-02T12:05:00Z',
                  'current': true,
                },
              ],
            }),
    );

    final current = await t.api.currentSession();
    expect(
      (current.email, current.emailVerified, current.sessionId),
      ('ana@example.com', false, 's1'),
    );
    final list = await t.api.listSessions();
    expect(list.single.isCurrent, isTrue);
    expect(list.single.lastSeenAt, DateTime.utc(2026, 10, 2, 12, 5));
  });

  test('signOut forgets the session even when the server fails', () async {
    final t = build(ClientKind.mobile, (_) => problem(500, 'internal'));
    await t.client.saveTokens(const Tokens(access: 'a', refresh: 'r'));
    await expectLater(t.api.signOut(), throwsA(isA<ApiError>()));
    expect(t.store.tokens, isNull);
    expect(t.client.status.value, AuthStatus.signedOut);
  });

  test('signOut refused in kid mode keeps the session', () async {
    final t = build(ClientKind.mobile, (_) => problem(403, 'kid_mode'));
    await t.client.saveTokens(const Tokens(access: 'a', refresh: 'r'));
    await expectLater(
      t.api.signOut(),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'kid_mode')),
    );
    expect((t.store.tokens?.access, t.store.tokens?.refresh), ('a', 'r'));
    expect(t.client.status.value, AuthStatus.signedIn);
  });
}
