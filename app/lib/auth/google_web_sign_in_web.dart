import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

import 'google_id_tokens.dart';
import 'google_web_sign_in.dart';
import 'provider_authenticator.dart';

GoogleWebSignIn create(ProviderSettings settings) => _Gis(settings);

class _Gis implements GoogleWebSignIn {
  _Gis(ProviderSettings settings)
    : _tokens = GoogleIdTokens(
        clientId: settings.googleClientId,
        serverClientId: settings.googleServerClientId,
      );

  final GoogleIdTokens _tokens;

  @override
  Future<void> get ready => _tokens.ready();

  @override
  Widget button({required double width}) => gsi.renderButton(
    configuration: gsi.GSIButtonConfiguration(
      type: gsi.GSIButtonType.standard,
      // Outline in both modes: it pairs with Apple's white in dark mode
      // instead of an untinted charcoal.
      theme: gsi.GSIButtonTheme.outline,
      size: gsi.GSIButtonSize.large,
      text: gsi.GSIButtonText.continueWith,
      shape: gsi.GSIButtonShape.rectangular,
      logoAlignment: gsi.GSIButtonLogoAlignment.center,
      locale: 'pt-BR',
      minimumWidth: width.clamp(200, 400),
    ),
  );

  /// Sign-in events become ID tokens; sign-outs and errors (a closed
  /// popup) are dropped, so the screen stays idle.
  @override
  Stream<String> idTokens() => GoogleSignIn.instance.authenticationEvents
      .handleError((Object _) {})
      .where((e) => e is GoogleSignInAuthenticationEventSignIn)
      .map(
        (e) => (e as GoogleSignInAuthenticationEventSignIn)
            .user
            .authentication
            .idToken,
      )
      .where((t) => t != null)
      .cast<String>();
}
