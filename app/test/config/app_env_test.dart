import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/config/app_env.dart';

const valid =
    '{"API_BASE_URL":"https://api.telinhasegura.coding4u.tech",'
    '"GOOGLE_CLIENT_ID":"","GOOGLE_SERVER_CLIENT_ID":"",'
    '"APPLE_SERVICES_ID":"","APPLE_REDIRECT_URI":""}';

void main() {
  test('a complete https file passes', () {
    expect(appEnvProblems(valid), isEmpty);
  });

  test('every rule names its problem', () {
    expect(appEnvProblems('not json'), ['not a JSON object']);
    expect(appEnvProblems('[]'), ['not a JSON object']);
    expect(
      appEnvProblems(valid.replaceFirst('"APPLE_REDIRECT_URI":""', '"X":""')),
      contains('missing APPLE_REDIRECT_URI'),
    );
    expect(appEnvProblems(valid.replaceFirst('https://api', 'http://api')), [
      'API_BASE_URL must be an https:// URL',
    ]);
    expect(
      appEnvProblems(
        valid.replaceFirst('"GOOGLE_CLIENT_ID":""', '"GOOGLE_CLIENT_ID":1'),
      ),
      ['GOOGLE_CLIENT_ID is not a string'],
    );
  });

  test('the committed environments pass and point at their hosts', () {
    for (final (env, host) in [
      ('stg', 'stg.api.telinhasegura.coding4u.tech'),
      ('prd', 'api.telinhasegura.coding4u.tech'),
    ]) {
      final text = File('config/$env.json').readAsStringSync();
      expect(appEnvProblems(text), isEmpty, reason: env);
      expect(text, contains('"https://$host"'), reason: env);
    }
  });
}
