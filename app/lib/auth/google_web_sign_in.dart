import 'package:flutter/widgets.dart';

import 'google_web_sign_in_io.dart'
    if (dart.library.js_interop) 'google_web_sign_in_web.dart'
    as platform;
import 'provider_authenticator.dart';

/// Google on the web: Google renders its own button (`renderButton`), and
/// ID tokens arrive on a stream the screen subscribes to on mount and
/// cancels on dispose. A dismissed popup emits
/// nothing.
abstract interface class GoogleWebSignIn {
  /// Completes once Google's client is initialized; [button] and
  /// [idTokens] wait for it.
  Future<void> get ready;

  /// Google's own button, [width] wide (GIS allows 200–400 px).
  Widget button({required double width});

  Stream<String> idTokens();
}

/// The web implementation when Google is configured; null elsewhere.
GoogleWebSignIn? createGoogleWebSignIn(ProviderSettings settings) =>
    settings.googleEnabled ? platform.create(settings) : null;
