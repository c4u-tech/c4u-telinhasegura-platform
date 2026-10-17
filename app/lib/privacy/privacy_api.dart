import 'dart:convert';

import '../auth/api_client.dart';
import '../auth/apple_id_tokens.dart';

/// The privacy contract (LGPD art. 18). Both calls need a
/// re-authentication within the last 5 minutes; on `reauth_required` the
/// screen re-authenticates and retries.
class PrivacyApi {
  PrivacyApi(this._client);

  final ApiClient _client;

  /// Everything the platform holds about the account and its family, as
  /// indented JSON text for the screen to save or share. Five per hour;
  /// a sixth answers `rate_limited` with its `retryAfter`.
  Future<String> export() async =>
      const JsonEncoder.withIndent('  ')
          .convert(await _client.send('GET', '/v1/account/export'));

  /// Erases the account at once. An owner gets `owner_must_transfer` and
  /// keeps the session; an account linked to Apple gets
  /// `apple_reauthorization_required` until it sends a fresh [apple]
  /// credential. On success the stored session is forgotten,
  /// which signs the app out.
  Future<void> deleteAccount({AppleCredential? apple}) async {
    await _client.send(
      'DELETE',
      '/v1/account',
      body: apple == null
          ? null
          : {
              'apple': {
                'identity_token': apple.identityToken,
                'authorization_code': apple.authorizationCode,
                if (apple.redirectUri case final redirect?)
                  'redirect_uri': redirect.toString(),
              },
            },
    );
    await _client.forgetSession();
  }
}
