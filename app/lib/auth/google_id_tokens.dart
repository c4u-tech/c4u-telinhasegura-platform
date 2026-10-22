import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// google_sign_in 7.x. On mobile the token comes from `authenticate`, and
/// `initialize` runs before each sign-in (see [obtain]). On the web
/// `initialize` runs once ([ready]) and the token comes from Google's
/// rendered button through `GoogleWebSignIn` (google_web_sign_in.dart),
/// whose stream the screen owns.
class GoogleIdTokens {
  GoogleIdTokens({required this.clientId, required this.serverClientId});

  final String clientId;
  final String serverClientId;
  Future<void>? _ready;

  Future<void> ready() => _ready ??= GoogleSignIn.instance.initialize(
    clientId: clientId.isEmpty ? null : clientId,
    // The web plugin has no server client; its token's aud is clientId.
    serverClientId: kIsWeb || serverClientId.isEmpty ? null : serverClientId,
  );

  /// Signs in on mobile. Each call sets the plugin up again with a new
  /// nonce: Google's Android service caches the token it issued and hands
  /// the same one back for about an hour, and the server accepts each token
  /// once, so a repeat sign-in would be refused. A token bound to a new
  /// nonce is always a new token.
  Future<String?> obtain() async {
    final google = GoogleSignIn.instance;
    if (!google.supportsAuthenticate()) {
      throw StateError('On the web, Google signs in through its own button');
    }
    await google.initialize(
      clientId: clientId.isEmpty ? null : clientId,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
      nonce: _newNonce(),
    );
    try {
      return (await google.authenticate()).authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}

String _newNonce() {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(16, (_) => random.nextInt(256)));
}
