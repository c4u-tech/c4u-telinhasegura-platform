import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// A fresh Sign in with Apple answer: the identity token and its single-use
/// authorization code, which the API exchanges to revoke the authorization
/// on deletion.
class AppleCredential {
  const AppleCredential({
    required this.identityToken,
    required this.authorizationCode,
    this.redirectUri,
  });

  final String identityToken;
  final String authorizationCode;

  /// The redirect URI Apple's web flow issued the code to, which the
  /// exchange must repeat; null for a native code.
  final Uri? redirectUri;
}

/// Sign in with Apple: native on iOS, Apple JS on the web, and Apple's
/// web flow on Android, which returns through the API's relay callback.
class AppleIdTokens {
  AppleIdTokens({
    required this.servicesId,
    required this.redirectUri,
    this._prepare,
  });

  final String servicesId;
  final Uri redirectUri;

  /// Loads what the platform needs first: Apple JS on the web, which no
  /// page loads until the first Apple sign-in.
  final Future<void> Function()? _prepare;

  /// Throws [StateError] if the answer carries a state other than the one
  /// this request sent: it belongs to another sign-in.
  Future<String?> obtain() async => (await obtainCredential())?.identityToken;

  /// Like [obtain], with the authorization code too.
  Future<AppleCredential?> obtainCredential() async {
    await _prepare?.call();
    final state = _newState();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: servicesId,
          redirectUri: redirectUri,
        ),
        state: state,
      );
      if (credential.state != null && credential.state != state) {
        throw StateError('Apple answered with another sign-in\'s state');
      }
      final identityToken = credential.identityToken;
      if (identityToken == null) {
        throw StateError('Apple answered without an identity token');
      }
      return AppleCredential(
        identityToken: identityToken,
        authorizationCode: credential.authorizationCode,
        redirectUri: _native ? null : redirectUri,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  /// Apple and the plugin sign in natively on Apple's own platforms; every
  /// other one goes through the web flow.
  static bool get _native =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static String _newState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
