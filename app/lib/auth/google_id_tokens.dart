import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// google_sign_in 7.x: `initialize` runs once per app run. On mobile the
/// token comes from `authenticate`. On the web it comes from Google's
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

  Future<String?> obtain() async {
    await ready();
    final google = GoogleSignIn.instance;
    if (!google.supportsAuthenticate()) {
      throw StateError('On the web, Google signs in through its own button');
    }
    try {
      return (await google.authenticate()).authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}
