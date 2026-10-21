import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:telinha_segura/auth/google_id_tokens.dart';

/// A Google plugin that hands back [token] (or cancels, or fails) and
/// counts how often the signed-in state is cleared or revoked.
class _FakeGoogle extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  _FakeGoogle({this.canceled = false, this.signOutFails = false});

  final bool canceled;
  final bool signOutFails;
  final calls = <String>[];

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    calls.add('authenticate');
    if (canceled) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
    }
    return AuthenticationResults(
      user: const GoogleSignInUserData(email: 'a@b.c', id: '1'),
      authenticationTokens: AuthenticationTokenData(idToken: 'id-tok'),
    );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> signOut(SignOutParams params) async {
    calls.add('signOut');
    if (signOutFails) throw StateError('plugin is gone');
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {
    calls.add('disconnect');
  }
}

GoogleIdTokens _tokens(_FakeGoogle fake) {
  GoogleSignInPlatform.instance = fake;
  return GoogleIdTokens(clientId: '', serverClientId: 'server');
}

void main() {
  test('returns the token, then clears the signed-in state', () async {
    final fake = _FakeGoogle();

    expect(await _tokens(fake).obtain(), 'id-tok');
    expect(fake.calls, ['authenticate', 'signOut']);
  });

  test('a canceled sign-in yields null', () async {
    final fake = _FakeGoogle(canceled: true);

    expect(await _tokens(fake).obtain(), isNull);
    expect(fake.calls, ['authenticate']);
  });

  test('a failing sign-out still returns the token', () async {
    final fake = _FakeGoogle(signOutFails: true);

    expect(await _tokens(fake).obtain(), 'id-tok');
    expect(fake.calls, ['authenticate', 'signOut']);
  });
}
