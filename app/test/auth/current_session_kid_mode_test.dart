import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';

import 'fakes.dart';

Map<String, Object?> sessionBody(Object? kidMode) => {
  'account': {'id': 'a1', 'email': 'ana@example.com', 'email_verified': true},
  'session': {'id': 's1', 'client': 'web'},
  'kid_mode': kidMode,
};

void main() {
  test('kid_mode parses: none, a child, a deleted child', () async {
    Future<({String? minorId})?> kidMode(Object? wire) async => (await build(
      ClientKind.web,
      (_) => json(200, sessionBody(wire)),
    ).api.currentSession()).kidMode;

    expect(await kidMode(null), isNull);
    expect((await kidMode({'minor_id': 'm1'}))?.minorId, 'm1');
    final gone = await kidMode({'minor_id': null});
    expect(gone, isNotNull);
    expect(gone!.minorId, isNull);
  });
}
