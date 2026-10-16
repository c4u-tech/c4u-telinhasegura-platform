import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/parental/parental.dart';
import 'package:telinha_segura/parental/parental_api.dart';

import '../access/harness.dart' show Harness;
import '../auth/fakes.dart';

const profileJson = {
  'id': 'm1',
  'nickname': 'Lia',
  'avatar': 'fox',
  'age_band': '5-8',
};

const deviceJson = {
  'id': 'd1',
  'label': 'Tablet',
  'minor_id': 'm1',
  'linked_at': '2026-10-03T12:00:00Z',
  'last_seen_at': '2026-10-03T13:00:00Z',
};

http.Response contract(http.Request req) {
  final p = req.url.path;
  if (p == '/v1/parental/pin' && req.method == 'GET') {
    return json(200, {'set': true});
  }
  if (p == '/v1/parental/link-codes') {
    return json(201, {
      'code': 'ABCD-EFGH',
      'minor_id': 'm1',
      'expires_at': '2026-10-03T12:10:00Z',
    });
  }
  if (p == '/v1/parental/devices') {
    return json(200, {
      'devices': [deviceJson],
    });
  }
  return http.Response('', 204);
}

void main() {
  test('every call hits its contract path and body', () async {
    final t = build(ClientKind.web, contract);
    final api = ParentalApi(t.client);
    await api.pinIsSet();
    await api.setPin('2580');
    await api.verifyPin('2580');
    await api.handOver('m1');
    await api.createLinkCode('m1');
    await api.devices();
    await api.unlink('d 1');

    expect(t.calls, [
      'GET /v1/parental/pin',
      'PUT /v1/parental/pin {"pin":"2580"}',
      'POST /v1/parental/pin/verify {"pin":"2580"}',
      'POST /v1/parental/kid-mode {"minor_id":"m1"}',
      'POST /v1/parental/link-codes {"minor_id":"m1"}',
      'GET /v1/parental/devices',
      'DELETE /v1/parental/devices/d%201',
    ]);
  });

  test('responses parse into the value types', () async {
    final api = ParentalApi(build(ClientKind.mobile, contract).client);
    expect(await api.pinIsSet(), isTrue);
    final code = await api.createLinkCode('m1');
    expect(
      (code.code, code.minorId, code.expiresAt),
      ('ABCD-EFGH', 'm1', DateTime.utc(2026, 10, 3, 12, 10)),
    );
    final device = (await api.devices()).single;
    expect(
      (device.id, device.label, device.minorId, device.lastSeenAt),
      ('d1', 'Tablet', 'm1', DateTime.utc(2026, 10, 3, 13)),
    );
  });

  test('a profile parses unknown wire values to unknown', () {
    final p = Profile.fromJson({
      ...profileJson,
      'avatar': 'dragon',
      'age_band': '13-17',
    });
    expect((p.avatar, p.ageBand), (Avatar.unknown, AgeBand.unknown));
    expect(Profile.fromJson(profileJson).avatar, Avatar.fox);
  });

  test('problems surface as ApiError codes', () async {
    final api = ParentalApi(
      build(ClientKind.web, (_) => problem(422, 'weak_pin')).client,
    );
    await expectLater(
      api.setPin('1234'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'weak_pin')),
    );
  });

  test('the app services build one ParentalApi', () {
    expect(Harness().services.parental, isA<ParentalApi>());
  });
}
