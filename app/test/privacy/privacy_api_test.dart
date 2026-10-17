import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/apple_id_tokens.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/token_store.dart';
import 'package:telinha_segura/privacy/privacy_api.dart';

import '../access/harness.dart' show Harness;
import '../auth/fakes.dart';

const document = {
  'format': 'telinhasegura.export/1',
  'generated_at': '2026-10-04T12:00:00Z',
  'account': {'email': 'ana@example.com', 'linked_providers': <Object>[]},
  'family': null,
};

http.Response contract(http.Request req) =>
    req.method == 'DELETE' ? http.Response('', 204) : json(200, document);

void main() {
  test('every call hits its contract path', () async {
    final t = build(ClientKind.web, contract);
    final api = PrivacyApi(t.client);
    await api.export();
    await api.deleteAccount();
    expect(t.calls, ['GET /v1/account/export', 'DELETE /v1/account']);
  });

  test('the export is the document as indented JSON text', () async {
    final api = PrivacyApi(build(ClientKind.mobile, contract).client);
    expect(
      await api.export(),
      '{\n'
      '  "format": "telinhasegura.export/1",\n'
      '  "generated_at": "2026-10-04T12:00:00Z",\n'
      '  "account": {\n'
      '    "email": "ana@example.com",\n'
      '    "linked_providers": []\n'
      '  },\n'
      '  "family": null\n'
      '}',
    );
  });

  test('a deletion forgets the session', () async {
    final t = build(ClientKind.mobile, contract);
    await t.store.write(const Tokens(access: 'a', refresh: 'r'));
    t.client.status.value = AuthStatus.signedIn;
    await PrivacyApi(t.client).deleteAccount();
    expect(t.store.tokens, isNull);
    expect(t.client.status.value, AuthStatus.signedOut);
  });

  test('a refused deletion keeps the session', () async {
    final t = build(
      ClientKind.mobile,
      (_) => problem(409, 'owner_must_transfer'),
    );
    await t.store.write(const Tokens(access: 'a', refresh: 'r'));
    await expectLater(
      PrivacyApi(t.client).deleteAccount(),
      throwsA(
        isA<ApiError>().having((e) => e.code, 'code', 'owner_must_transfer'),
      ),
    );
    expect(t.store.tokens, isNotNull);
  });

  test('problems surface as ApiError codes', () async {
    final api = PrivacyApi(
      build(
        ClientKind.web,
        (_) => problem(429, 'rate_limited', headers: {'retry-after': '60'}),
      ).client,
    );
    await expectLater(
      api.export(),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'rate_limited')
            .having((e) => e.retryAfter, 'retryAfter', isNotNull),
      ),
    );
  });

  test('the app services build one PrivacyApi', () {
    expect(Harness().services.privacy, isA<PrivacyApi>());
  });

  test('a deletion with an Apple credential sends it', () async {
    http.Request? sent;
    final t = build(ClientKind.mobile, (req) {
      sent = req;
      return http.Response('', 204);
    });
    await PrivacyApi(t.client).deleteAccount(
      apple: const AppleCredential(
        identityToken: 'id-token',
        authorizationCode: 'code',
      ),
    );
    expect(jsonDecode(sent!.body), {
      'apple': {'identity_token': 'id-token', 'authorization_code': 'code'},
    });
  });

  test('a web-flow credential sends its redirect URI', () async {
    http.Request? sent;
    final t = build(ClientKind.mobile, (req) {
      sent = req;
      return http.Response('', 204);
    });
    await PrivacyApi(t.client).deleteAccount(
      apple: AppleCredential(
        identityToken: 'id-token',
        authorizationCode: 'code',
        redirectUri: Uri.parse('https://api.test/v1/oauth/apple/callback'),
      ),
    );
    expect(jsonDecode(sent!.body), {
      'apple': {
        'identity_token': 'id-token',
        'authorization_code': 'code',
        'redirect_uri': 'https://api.test/v1/oauth/apple/callback',
      },
    });
  });

  test('a deletion without a credential sends no body', () async {
    http.Request? sent;
    final t = build(ClientKind.mobile, (req) {
      sent = req;
      return http.Response('', 204);
    });
    await PrivacyApi(t.client).deleteAccount();
    expect(sent!.body, isEmpty);
  });
}
