import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/auth_api.dart';

import 'fakes.dart';

Map<String, Object?> sessionWith(Object? status) => {
  'account': {
    'id': 'a1',
    'email': 'ana@example.com',
    'email_verified': true,
    'status': ?status,
  },
  'session': {'id': 's1', 'client': 'web'},
  'kid_mode': null,
  'roles': <String>[],
};

void main() {
  test(
    'the account status parses: active, suspended, unknown, missing',
    () async {
      Future<AccountStatus> status(Object? wire) async => (await build(
        ClientKind.web,
        (_) => json(200, sessionWith(wire)),
      ).api.currentSession()).status;

      expect(await status('active'), AccountStatus.active);
      expect(await status('suspended'), AccountStatus.suspended);
      expect(await status('banned'), AccountStatus.active);
      expect(await status(null), AccountStatus.active);
    },
  );
}
