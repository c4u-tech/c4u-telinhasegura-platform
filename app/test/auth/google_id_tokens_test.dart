import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:telinha_segura/auth/google_id_tokens.dart';

/// A Google plugin that hands back a token (or cancels) and records the
/// nonce each sign-in was set up with.
class _FakeGoogle extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  _FakeGoogle({this.canceled = false});

  final bool canceled;
  final calls = <String>[];
  final nonces = <String?>[];

  @override
  Future<void> init(InitParameters params) async {
    calls.add('init');
    nonces.add(params.nonce);
  }

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
  test(
    'sets up each sign-in with a new nonce, so Google mints a new token',
    () async {
      final fake = _FakeGoogle();
      final tokens = _tokens(fake);

      expect(await tokens.obtain(), 'id-tok');
      expect(await tokens.obtain(), 'id-tok');

      expect(fake.calls, ['init', 'authenticate', 'init', 'authenticate']);
      expect(fake.nonces, everyElement(isNotNull));
      expect(fake.nonces.first, isNot(fake.nonces.last));
      expect(fake.nonces.first!.length, greaterThanOrEqualTo(22));
    },
  );

  test('a canceled sign-in yields null', () async {
    final fake = _FakeGoogle(canceled: true);

    expect(await _tokens(fake).obtain(), isNull);
    expect(fake.calls, ['init', 'authenticate']);
  });
}
