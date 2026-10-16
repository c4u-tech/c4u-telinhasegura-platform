import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telinha_segura/auth/provider_authenticator.dart';
import 'package:telinha_segura/config/runtime_config.dart';

final origin = Uri.parse('https://app.test/redefinir-senha?t=1');

final fallback = RuntimeConfig(
  apiBaseUrl: Uri.parse('http://localhost:8080'),
  providers: const ProviderSettings(
    googleClientId: 'define-g',
    googleServerClientId: '',
    appleServicesId: '',
    appleRedirectUri: '',
  ),
);

http.Response jsonResponse(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('reads every field the web image writes', () {
    final config = RuntimeConfig.fromJson({
      'apiBaseUrl': 'https://api.test',
      'googleClientId': 'g1',
      'googleServerClientId': 'g2',
      'appleServicesId': 'a1',
      'appleRedirectUri': 'https://app.test',
    });
    expect(config.apiBaseUrl, Uri.parse('https://api.test'));
    expect(config.providers.googleClientId, 'g1');
    expect(config.providers.googleServerClientId, 'g2');
    expect(config.providers.appleServicesId, 'a1');
    expect(config.providers.appleRedirectUri, 'https://app.test');
  });

  test('empty provider fields disable the providers', () {
    final config = RuntimeConfig.fromJson({'apiBaseUrl': 'https://api.test'});
    expect(config.providers.googleEnabled, isFalse);
    expect(config.providers.appleEnabled, isFalse);
  });

  for (final bad in <Object?>[
    null,
    'text',
    <String, Object?>{},
    {'apiBaseUrl': ''},
    {'apiBaseUrl': 'api.test'},
    {'apiBaseUrl': 'ftp://api.test'},
    {'apiBaseUrl': 7},
    {'apiBaseUrl': 'https://api.test', 'googleClientId': 3},
  ]) {
    test('refuses $bad', () {
      expect(() => RuntimeConfig.fromJson(bad), throwsFormatException);
    });
  }

  test('fetches /config.json from the page origin', () async {
    final asked = <Uri>[];
    final config = await loadRuntimeConfig(
      MockClient((req) async {
        asked.add(req.url);
        return jsonResponse(200, {'apiBaseUrl': 'https://api.test'});
      }),
      origin,
    );
    expect(asked, [Uri.parse('https://app.test/config.json')]);
    expect(config.apiBaseUrl, Uri.parse('https://api.test'));
  });

  test('a non-200 answer is an error', () async {
    await expectLater(
      loadRuntimeConfig(
        MockClient((_) async => http.Response('nope', 404)),
        origin,
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  group('startupConfig', () {
    test(
      'off the runtime build, uses the dart-define fallback and asks nothing',
      () async {
        var requests = 0;
        final config = await startupConfig(
          fromServer: false,
          client: MockClient((_) async {
            requests++;
            return http.Response('', 500);
          }),
          origin: origin,
          fallback: fallback,
        );
        expect(identical(config, fallback), isTrue);
        expect(requests, 0);
      },
    );

    test('on the runtime build, returns the served config', () async {
      final config = await startupConfig(
        fromServer: true,
        client: MockClient(
          (_) async => jsonResponse(200, {'apiBaseUrl': 'https://api.test'}),
        ),
        origin: origin,
        fallback: fallback,
      );
      expect(config!.apiBaseUrl, Uri.parse('https://api.test'));
      expect(config.providers.googleClientId, '');
    });

    for (final (name, answer) in <(String, Future<http.Response> Function())>[
      ('a 404', () async => http.Response('', 404)),
      ('malformed JSON', () async => http.Response('{', 200)),
      ('no apiBaseUrl', () async => jsonResponse(200, {'googleClientId': 'g'})),
      ('a network error', () async => throw http.ClientException('offline')),
    ]) {
      test('returns null on $name, after one request only', () async {
        final asked = <Uri>[];
        final config = await startupConfig(
          fromServer: true,
          client: MockClient((req) async {
            asked.add(req.url);
            return answer();
          }),
          origin: origin,
          fallback: fallback,
        );
        expect(config, isNull);
        expect(asked, [Uri.parse('https://app.test/config.json')]);
      });
    }
  });

  test('a mobile release refuses a non-https API', () {
    final http = Uri.parse('http://localhost:8080');
    final https = Uri.parse('https://api.telinhasegura.coding4u.tech');
    expect(usableApiBase(http, mobileRelease: true), isFalse);
    expect(usableApiBase(https, mobileRelease: true), isTrue);
    expect(usableApiBase(http, mobileRelease: false), isTrue);
  });
}
