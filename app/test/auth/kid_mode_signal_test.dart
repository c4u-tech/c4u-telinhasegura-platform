import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';

import 'fakes.dart';

void main() {
  test('a kid_mode refusal signals once, then throws', () async {
    final t = build(ClientKind.web, (_) => problem(403, 'kid_mode'));
    var signals = 0;
    t.client.onKidMode = () => signals++;
    await expectLater(
      t.client.send('GET', '/v1/family'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'kid_mode')),
    );
    expect(signals, 1);
  });

  test('other problems do not signal', () async {
    final t = build(ClientKind.web, (_) => problem(403, 'not_owner'));
    var signals = 0;
    t.client.onKidMode = () => signals++;
    await expectLater(t.client.send('GET', '/v1/family'), throwsA(anything));
    expect(signals, 0);
  });
}
