import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/token_store.dart';
import 'package:telinha_segura/parental/child_api.dart';

import '../access/harness.dart' show Harness;
import '../auth/fakes.dart';
import 'fakes.dart';
import 'parental_api_test.dart' show profileJson;

http.Response childContract(http.Request req) {
  final p = req.url.path;
  if (p == '/v1/devices/redeem') {
    return json(201, {'token': 'dev-token', 'profile': profileJson});
  }
  if (p == '/v1/child/profiles') {
    return json(200, {
      'profiles': [profileJson],
    });
  }
  if (p == '/v1/child/unlock') return http.Response('', 204);
  return json(200, profileJson);
}

void main() {
  test('with a device credential every call carries it as Bearer', () async {
    final seen = <http.Request>[];
    final t = build(ClientKind.mobile, childContract, seen: seen);
    await t.client.saveTokens(const Tokens(access: 'a', refresh: 'r'));
    final api = ChildApi(
      t.client,
      devices: MemoryDeviceCredentialStore('dev-token'),
    );

    expect(await api.isLinked(), isTrue);
    expect((await api.profile()).nickname, 'Lia');
    expect((await api.profiles('2580')).single.id, 'm1');
    await api.switchProfile(pin: '2580', minorId: 'm2');

    expect(t.calls, [
      'GET /v1/child/profile',
      'POST /v1/child/profiles {"pin":"2580"}',
      'PUT /v1/child/profile {"pin":"2580","minor_id":"m2"}',
    ]);
    expect(
      seen.map((r) => r.headers['Authorization']),
      everyElement('Bearer dev-token'),
    );
  });

  test('without one, child calls go through the session', () async {
    final seen = <http.Request>[];
    final t = build(ClientKind.web, childContract, seen: seen);
    final api = ChildApi(t.client, devices: MemoryDeviceCredentialStore());

    expect(await api.isLinked(), isFalse);
    await api.unlock('2580');
    expect(t.calls, ['POST /v1/child/unlock {"pin":"2580"}']);
    expect(seen.single.headers['X-CSRF-Token'], 'c');
  });

  test('a 401 on the device credential forgets it', () async {
    final t = build(ClientKind.mobile, (_) => problem(401, 'unauthenticated'));
    final devices = MemoryDeviceCredentialStore('dev-token');
    await expectLater(
      ChildApi(t.client, devices: devices).profile(),
      throwsA(isA<ApiError>()),
    );
    expect(devices.token, isNull);
  });

  test('other problems keep it', () async {
    final t = build(ClientKind.mobile, (_) => problem(403, 'invalid_pin'));
    final devices = MemoryDeviceCredentialStore('dev-token');
    await expectLater(
      ChildApi(t.client, devices: devices).profiles('1357'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_pin')),
    );
    expect(devices.token, 'dev-token');
  });

  test(
    'on the web a 401 from a child route signs the session out at once',
    () async {
      final t = build(ClientKind.web, (_) => problem(401, 'unauthenticated'));
      expect(t.client.status.value, AuthStatus.signedIn);

      await expectLater(
        ChildApi(t.client).profile(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );

      expect(t.client.status.value, AuthStatus.signedOut);
    },
  );

  test('on the web a wrong PIN (403) keeps the session', () async {
    final t = build(ClientKind.web, (_) => problem(403, 'invalid_pin'));

    await expectLater(
      ChildApi(t.client).unlock('1357'),
      throwsA(isA<ApiError>()),
    );

    expect(t.client.status.value, AuthStatus.signedIn);
  });

  test('only a device with a credential store can link', () {
    final t = build(ClientKind.web, childContract);
    expect(ChildApi(t.client).canLink, isFalse);
    expect(
      ChildApi(t.client, devices: MemoryDeviceCredentialStore()).canLink,
      isTrue,
    );
  });

  test('a desktop with a credential store cannot link: Android and iOS '
      'only', () {
    final t = build(ClientKind.mobile, childContract);
    final api = ChildApi(t.client, devices: MemoryDeviceCredentialStore());
    for (final (platform, links) in [
      (TargetPlatform.android, true),
      (TargetPlatform.iOS, true),
      (TargetPlatform.macOS, false),
      (TargetPlatform.windows, false),
      (TargetPlatform.linux, false),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(api.canLink, links, reason: '$platform');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('redeem stores the token and sends no session credential', () async {
    final seen = <http.Request>[];
    final t = build(ClientKind.mobile, childContract, seen: seen);
    await t.client.saveTokens(const Tokens(access: 'a', refresh: 'r'));
    final devices = MemoryDeviceCredentialStore();

    final profile = await ChildApi(
      t.client,
      devices: devices,
    ).redeem(code: 'ABCD-EFGH', label: 'Tablet');

    expect(profile.id, 'm1');
    expect(devices.token, 'dev-token');
    expect(t.calls, [
      'POST /v1/devices/redeem {"code":"ABCD-EFGH","label":"Tablet"}',
    ]);
    expect(seen.single.headers['Authorization'], isNull);
  });

  test('redeem needs a credential store (Android and iOS only)', () {
    final t = build(ClientKind.web, childContract);
    expect(
      () => ChildApi(t.client).redeem(code: 'ABCD-EFGH', label: 'Tablet'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('the app services build one ChildApi', () {
    expect(Harness().services.child, isA<ChildApi>());
  });
}
