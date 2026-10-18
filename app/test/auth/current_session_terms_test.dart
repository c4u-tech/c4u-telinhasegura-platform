import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';

import 'fakes.dart';

Map<String, Object?> sessionWith(Object? accepted) => {
  'account': {
    'id': 'a1',
    'email': 'ana@example.com',
    'email_verified': true,
    'terms_accepted': ?accepted,
  },
  'session': {'id': 's1', 'client': 'web'},
  'kid_mode': null,
  'roles': <String>[],
};

void main() {
  test(
    'the terms acceptance parses: accepted, not accepted, missing',
    () async {
      Future<bool> accepted(Object? wire) async => (await build(
        ClientKind.web,
        (_) => json(200, sessionWith(wire)),
      ).api.currentSession()).termsAccepted;

      expect(await accepted(true), isTrue);
      expect(await accepted(false), isFalse);
      // An older server says nothing: nobody is held back by it.
      expect(await accepted(null), isTrue);
    },
  );
}
