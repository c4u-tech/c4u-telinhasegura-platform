import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;

import 'auth/api_client.dart';
import 'auth/google_web_sign_in.dart';
import 'auth/http_client.dart';
import 'auth/provider_authenticator.dart';
import 'auth/secure_token_store.dart';
import 'config/config_error_app.dart';
import 'config/runtime_config.dart';
import 'parental/kid_mode_mark.dart';
import 'parental/secure_device_credential_store.dart';
import 'shell/app.dart';
import 'shell/services.dart';

/// The API origin, from `--dart-define=API_BASE_URL=...`; local by default.
const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

Future<void> main() async {
  // Path URLs on the web, so the backend's mailed links resolve
  // (/verificar-email, /redefinir-senha). No-op elsewhere.
  usePathUrlStrategy();
  // The web image serves /config.json; everywhere else the dart-defines
  // hold.
  final config = await startupConfig(
    fromServer: kIsWeb && runtimeConfigBuild,
    client: http.Client(),
    origin: Uri.base,
    fallback: RuntimeConfig(
      apiBaseUrl: Uri.parse(_apiBaseUrl),
      providers: ProviderSettings.fromEnvironment(),
    ),
  );
  if (config == null ||
      !usableApiBase(
        config.apiBaseUrl,
        mobileRelease: kReleaseMode && !kIsWeb,
      )) {
    runApp(const ConfigErrorApp());
    return;
  }
  final settings = config.providers;
  final services = AppServices(
    client: ApiClient(
      baseUrl: config.apiBaseUrl,
      kind: kIsWeb ? ClientKind.web : ClientKind.mobile,
      httpClient: createHttpClient(),
      tokens: kIsWeb ? null : SecureTokenStore(),
    ),
    providers: PluginProviderAuthenticator(settings),
    settings: settings,
    devices: kIsWeb ? null : SecureDeviceCredentialStore(),
    kidModeMark: SecureKidModeMark(),
    googleWeb: kIsWeb ? createGoogleWebSignIn(settings) : null,
  );
  runApp(TelinhaSeguraApp(services: services));
  // Read the device label now, so a sign-in finds it ready.
  unawaited(services.deviceLabel.read());
}
