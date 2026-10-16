import 'apple_id_tokens.dart';
import 'apple_js.dart';
import 'google_id_tokens.dart';
import 'once.dart';
import 'provider_sign_in.dart';

/// Obtains a provider ID token to offer to the API, or null when the
/// guardian cancels. The token is never a session: pass it to
/// `AuthApi.signInWithProvider`.
abstract interface class ProviderAuthenticator {
  Future<String?> idToken(IdentityProvider provider);

  /// A fresh Apple credential for an account deletion, or null when the
  /// guardian cancels.
  Future<AppleCredential?> appleCredential();
}

/// Provider client IDs, read only from `--dart-define`.
class ProviderSettings {
  const ProviderSettings({
    required this.googleClientId,
    required this.googleServerClientId,
    required this.appleServicesId,
    required this.appleRedirectUri,
  });

  factory ProviderSettings.fromEnvironment() => const ProviderSettings(
    googleClientId: String.fromEnvironment('GOOGLE_CLIENT_ID'),
    googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    appleServicesId: String.fromEnvironment('APPLE_SERVICES_ID'),
    appleRedirectUri: String.fromEnvironment('APPLE_REDIRECT_URI'),
  );

  /// The platform client ID: iOS, or web. Empty on Android.
  final String googleClientId;

  /// The web client ID, the `aud` of Android and iOS tokens.
  final String googleServerClientId;

  /// The Services ID of Apple's web flow (Android and web).
  final String appleServicesId;

  /// Android: the API's `/v1/oauth/apple/callback`. Web: the app origin
  /// registered with Apple.
  final String appleRedirectUri;

  bool get googleEnabled =>
      googleClientId.isNotEmpty || googleServerClientId.isNotEmpty;

  bool get appleEnabled =>
      appleServicesId.isNotEmpty && appleRedirectUri.isNotEmpty;
}

/// The production [ProviderAuthenticator], backed by the platform plugins.
class PluginProviderAuthenticator implements ProviderAuthenticator {
  PluginProviderAuthenticator(this._settings);

  final ProviderSettings _settings;
  GoogleIdTokens? _google;
  final _appleJs = Once(loadAppleJs);

  @override
  Future<String?> idToken(IdentityProvider provider) async {
    switch (provider) {
      case IdentityProvider.google:
        if (!_settings.googleEnabled) {
          throw StateError('Google sign-in is not configured');
        }
        return (_google ??= GoogleIdTokens(
          clientId: _settings.googleClientId,
          serverClientId: _settings.googleServerClientId,
        )).obtain();
      case IdentityProvider.apple:
        if (!_settings.appleEnabled) {
          throw StateError('Sign in with Apple is not configured');
        }
        return AppleIdTokens(
          servicesId: _settings.appleServicesId,
          redirectUri: Uri.parse(_settings.appleRedirectUri),
          prepare: _appleJs.call,
        ).obtain();
    }
  }

  @override
  Future<AppleCredential?> appleCredential() async {
    if (!_settings.appleEnabled) {
      throw StateError('Sign in with Apple is not configured');
    }
    return AppleIdTokens(
      servicesId: _settings.appleServicesId,
      redirectUri: Uri.parse(_settings.appleRedirectUri),
      prepare: _appleJs.call,
    ).obtainCredential();
  }
}
