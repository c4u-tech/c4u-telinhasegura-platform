import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';
import 'package:telinha_segura/legal/legal_links.dart';

import 'fakes.dart';

final mobileTokens = {
  'session_id': 's',
  'access_token': 'a',
  'access_expires_at': '2026-10-02T12:15:00Z',
  'refresh_token': 'r',
};

void main() {
  test('a linked identity signs in and stores the tokens', () async {
    final t = build(ClientKind.mobile, (_) => json(201, mobileTokens));
    final result = await t.api.signInWithProvider(
      IdentityProvider.google,
      'id-tok',
      deviceLabel: 'Pixel 9',
    );

    expect(result, isA<SignedIn>());
    expect(
      t.calls.single,
      'POST /v1/sessions/provider {"provider":"google","id_token":"id-tok",'
      '"client":"mobile","device_label":"Pixel 9"}',
    );
    expect((t.store.tokens?.access, t.store.tokens?.refresh), ('a', 'r'));
  });

  test('signup_required becomes SignupRequired and stores nothing', () async {
    final t = build(
      ClientKind.mobile,
      (_) => problem(
        409,
        'signup_required',
        extra: {'ticket': 'tk', 'email': 'ana@gmail.com'},
      ),
    );
    final result = await t.api.signInWithProvider(IdentityProvider.apple, 'x');

    expect(
      result,
      isA<SignupRequired>()
          .having((r) => r.ticket, 'ticket', 'tk')
          .having((r) => r.email, 'email', 'ana@gmail.com'),
    );
    expect(t.store.tokens, isNull);
  });

  test('link_required carries the offered options', () async {
    final t = build(
      ClientKind.web,
      (_) => problem(
        409,
        'link_required',
        extra: {
          'ticket': 'tk',
          'email': 'ana@gmail.com',
          'options': ['password', 'clear_password'],
        },
      ),
    );
    final result = await t.api.signInWithProvider(IdentityProvider.google, 'x');

    expect(
      result,
      isA<LinkRequired>().having((r) => r.options, 'options', {
        LinkOption.password,
        LinkOption.clearPassword,
      }),
    );
  });

  test('other problems stay typed errors', () async {
    final t = build(
      ClientKind.web,
      (_) => problem(422, 'provider_email_unverified'),
    );
    expect(
      t.api.signInWithProvider(IdentityProvider.google, 'x'),
      throwsA(
        isA<ApiError>().having(
          (e) => e.code,
          'code',
          'provider_email_unverified',
        ),
      ),
    );
  });

  test('web signup confirms the declaration and remembers CSRF', () async {
    final t = build(
      ClientKind.web,
      (req) => req.url.path == '/v1/sessions/provider/signup'
          ? json(201, {'session_id': 's', 'csrf_token': 'fresh'})
          : noContent(req),
      seedCsrf: false,
    );
    final result = await t.api.completeProviderSignup(
      'tk',
      adultDeclaration: true,
    );
    await t.api.signOut();

    expect(result, isA<SignedIn>());

    expect(t.calls, [
      'POST /v1/sessions/provider/signup {"ticket":"tk",'
          '"adult_declaration":true,"terms_version":"$kTermsVersion",'
          '"client":"web","device_label":""}',
      'DELETE /v1/session',
    ]);
  });

  test('a signup that finds the email taken meanwhile asks to link', () async {
    final t = build(
      ClientKind.mobile,
      (_) => problem(
        409,
        'link_required',
        extra: {
          'ticket': 'tk2',
          'email': 'ana@gmail.com',
          'options': ['password'],
        },
      ),
    );
    final result = await t.api.completeProviderSignup(
      'tk',
      adultDeclaration: true,
    );

    expect(
      result,
      isA<LinkRequired>().having((r) => r.ticket, 'ticket', 'tk2').having(
        (r) => r.options,
        'options',
        {LinkOption.password},
      ),
    );
    expect(t.store.tokens, isNull);
  });

  test('link requests carry exactly one proof', () async {
    final t = build(ClientKind.mobile, (_) => json(201, mobileTokens));
    await t.api.linkProvider('tk', password: 'senha');
    await t.api.linkProviderClearingPassword('tk2');

    expect(t.calls, [
      'POST /v1/sessions/provider/link {"ticket":"tk","password":"senha",'
          '"client":"mobile","device_label":""}',
      'POST /v1/sessions/provider/link {"ticket":"tk2","clear_password":true,'
          '"client":"mobile","device_label":""}',
    ]);
  });

  test('re-auth sends the provider token', () async {
    final t = build(ClientKind.web, noContent);
    await t.api.reauthenticateWithProvider(IdentityProvider.apple, 'id-tok');

    expect(
      t.calls.single,
      'POST /v1/session/reauth {"provider":"apple","id_token":"id-tok"}',
    );
  });
}
