import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/provider_authenticator.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';

void main() {
  test('settings come only from dart-define and default to off', () {
    final s = ProviderSettings.fromEnvironment();

    expect((s.googleClientId, s.googleServerClientId), ('', ''));
    expect((s.appleServicesId, s.appleRedirectUri), ('', ''));
    expect((s.googleEnabled, s.appleEnabled), (false, false));
  });

  test('a provider without settings is refused before any plugin call', () {
    final auth = PluginProviderAuthenticator(
      const ProviderSettings(
        googleClientId: '',
        googleServerClientId: '',
        appleServicesId: '',
        appleRedirectUri: '',
      ),
    );

    expect(auth.idToken(IdentityProvider.google), throwsStateError);
    expect(auth.idToken(IdentityProvider.apple), throwsStateError);
  });

  test('either Google client ID enables Google; Apple needs both values', () {
    const s = ProviderSettings(
      googleClientId: '',
      googleServerClientId: 'web.apps.googleusercontent.com',
      appleServicesId: 'tech.coding4u.telinhasegura.web',
      appleRedirectUri: '',
    );

    expect((s.googleEnabled, s.appleEnabled), (true, false));
  });
}
