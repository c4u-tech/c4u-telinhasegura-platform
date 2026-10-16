import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';

import 'fakes.dart';

void main() {
  test('a 403 account_suspended signals once, then throws', () async {
    final t = build(ClientKind.web, (_) => problem(403, 'account_suspended'));
    var signals = 0;
    t.client.onSuspended = () => signals++;
    await expectLater(
      t.client.send('GET', '/v1/sessions'),
      throwsA(
        isA<ApiError>().having((e) => e.code, 'code', 'account_suspended'),
      ),
    );
    expect(signals, 1);
  });

  test('a team grant\'s 409 account_suspended is a field error, not the '
      'signal', () async {
    final t = build(ClientKind.web, (_) => problem(409, 'account_suspended'));
    var signals = 0;
    t.client.onSuspended = () => signals++;
    await expectLater(
      t.client.send('POST', '/v1/admin/staff/grants'),
      throwsA(anything),
    );
    expect(signals, 0);
  });

  test('other refusals do not signal', () async {
    final t = build(ClientKind.web, (_) => problem(403, 'kid_mode'));
    var signals = 0;
    t.client.onSuspended = () => signals++;
    await expectLater(t.client.send('GET', '/v1/family'), throwsA(anything));
    expect(signals, 0);
  });
}
