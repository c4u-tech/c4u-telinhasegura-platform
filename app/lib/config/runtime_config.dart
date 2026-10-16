import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/provider_authenticator.dart';

/// Whether this build reads its configuration from `/config.json` at run
/// time. Only the web image's build sets it (`app/deploy/prebuild.sh`); the
/// value is the same in every environment.
const runtimeConfigBuild = bool.fromEnvironment('RUNTIME_CONFIG');

/// What an environment tells the web app at run time, served by the web
/// image as `/config.json`.
class RuntimeConfig {
  const RuntimeConfig({required this.apiBaseUrl, required this.providers});

  /// Parses `/config.json`. Throws [FormatException] unless `apiBaseUrl` is
  /// an absolute http(s) URL and every other field is a string or absent.
  factory RuntimeConfig.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('config.json is not an object');
    }
    final raw = json['apiBaseUrl'];
    final api = raw is String ? Uri.tryParse(raw) : null;
    if (api == null ||
        !api.hasAuthority ||
        !(api.isScheme('https') || api.isScheme('http'))) {
      throw const FormatException('config.json lacks a valid apiBaseUrl');
    }
    String field(String key) {
      final value = json[key];
      if (value == null) return '';
      if (value is! String) {
        throw FormatException('config.json: $key is not a string');
      }
      return value;
    }

    return RuntimeConfig(
      apiBaseUrl: api,
      providers: ProviderSettings(
        googleClientId: field('googleClientId'),
        googleServerClientId: field('googleServerClientId'),
        appleServicesId: field('appleServicesId'),
        appleRedirectUri: field('appleRedirectUri'),
      ),
    );
  }

  final Uri apiBaseUrl;
  final ProviderSettings providers;
}

/// Fetches `/config.json` from the page's [origin]. Throws on any failure.
Future<RuntimeConfig> loadRuntimeConfig(http.Client client, Uri origin) async {
  final res = await client.get(
    origin.resolve('/config.json'),
    headers: {'accept': 'application/json'},
  );
  if (res.statusCode != 200) {
    throw http.ClientException('config.json answered ${res.statusCode}');
  }
  return RuntimeConfig.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
}

/// The configuration the app starts with: [fallback] (the dart-defines)
/// unless [fromServer], else the served one, or null when it cannot be
/// loaded. Null means the app must not start: there is no API origin to
/// fall back to in production.
Future<RuntimeConfig?> startupConfig({
  required bool fromServer,
  required http.Client client,
  required Uri origin,
  required RuntimeConfig fallback,
}) async {
  if (!fromServer) return fallback;
  try {
    return await loadRuntimeConfig(client, origin);
  } on Object {
    return null;
  }
}

/// Whether the app may start against [url]: a mobile release talks to its
/// API only over HTTPS. The web keeps
/// `render-config.sh`'s own rule, and debug builds reach a local API.
bool usableApiBase(Uri url, {required bool mobileRelease}) =>
    !mobileRelease || url.isScheme('https');
