import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/token_store.dart';
import 'package:telinha_segura/family/family_api.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/parental/child_api.dart';
import 'package:telinha_segura/parental/kid_mode_mark.dart';
import 'package:telinha_segura/parental/parental_api.dart';

import '../access/harness.dart' show Harness;
import '../auth/fakes.dart';
import 'fakes.dart';
import 'parental_api_test.dart' show profileJson;

http.Response Function(http.Request) server({
  Object? kidMode,
  int profileStatus = 200,
  int profilesStatus = 200,
  (int, String)? verifyProblem,
  String Function()? account,
}) => (req) {
  final p = req.url.path;
  if (p == '/v1/session') {
    return json(200, {
      'account': {
        'id': account?.call() ?? 'a1',
        'email': 'ana@example.com',
        'email_verified': true,
      },
      'session': {'id': 's1', 'client': 'mobile'},
      'kid_mode': kidMode,
    });
  }
  if (p == '/v1/child/profile' && req.method == 'PUT') {
    return json(200, {...profileJson, 'id': 'm2'});
  }
  if (p == '/v1/child/profile') {
    return profileStatus == 200
        ? json(200, profileJson)
        : problem(profileStatus, 'unauthenticated');
  }
  if (p == '/v1/child/profiles') {
    return profilesStatus == 200
        ? json(200, {
            'profiles': [profileJson],
          })
        : problem(profilesStatus, 'unauthenticated');
  }
  if (p == '/v1/devices/redeem') {
    return json(201, {'token': 'dev-token', 'profile': profileJson});
  }
  if (p == '/v1/parental/pin/verify' && verifyProblem != null) {
    return problem(verifyProblem.$1, verifyProblem.$2);
  }
  if (p == '/v1/family') return problem(403, 'kid_mode');
  return http.Response('', 204);
};

({
  AppModeModel model,
  ApiClient client,
  List<String> calls,
  MemoryDeviceCredentialStore devices,
  KidModeMark mark,
})
setUpModel(
  http.Response Function(http.Request) answer, {
  String? device,
  String? marked,
  KidModeMark? markOverride,
}) {
  final t = build(ClientKind.mobile, answer);
  final devices = MemoryDeviceCredentialStore(device);
  final mark = markOverride ?? MemoryKidModeMark({?marked});
  final model = AppModeModel(
    auth: t.api,
    parental: ParentalApi(t.client),
    child: ChildApi(t.client, devices: devices),
    client: t.client,
    mark: mark,
  );
  return (
    model: model,
    client: t.client,
    calls: t.calls,
    devices: devices,
    mark: mark,
  );
}

Future<void> signIn(ApiClient client) =>
    client.saveTokens(const Tokens(access: 'a', refresh: 'r'));

/// Lets the model's fire-and-forget resync finish.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class ControlledMark implements KidModeMark {
  final read$ = Completer<Set<String>>();

  @override
  Future<Set<String>> read() => read$.future;

  @override
  Future<void> add(String accountId) async {}

  @override
  Future<void> remove(String accountId) async {}
}

class ThrowingMark implements KidModeMark {
  @override
  Future<Set<String>> read() async => throw StateError('storage');

  @override
  Future<void> add(String accountId) async {}

  @override
  Future<void> remove(String accountId) async {}
}

void main() {
  test('a stored device credential restores a linked device', () async {
    final m = setUpModel(server(), device: 'dev-token');
    await m.model.restore();
    expect(m.model.mode, const LinkedDevice('m1'));
    expect(m.calls, ['GET /v1/child/profile']);
  });

  test('a refused device credential restores the guardian mode', () async {
    final m = setUpModel(server(profileStatus: 401), device: 'dev-token');
    await m.model.restore();
    expect(m.model.mode, const Guardian());
    expect(m.devices.token, isNull);
  });

  test('an unreachable server keeps a linked device a child\'s', () async {
    final m = setUpModel(
      (_) => throw http.ClientException('offline'),
      device: 'dev-token',
    );
    await m.model.restore();
    expect(m.model.mode, const LinkedDevice(null));
  });

  test('signed out restores the guardian mode without a request', () async {
    final m = setUpModel(server());
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();
    expect(m.model.mode, const Guardian());
    expect(m.calls, isEmpty);
  });

  test('a locked session restores kid mode on a shared device', () async {
    final m = setUpModel(server(kidMode: {'minor_id': 'm1'}));
    await signIn(m.client);
    await m.model.restore();
    expect(m.model.mode, const SharedKid('m1'));

    final free = setUpModel(server());
    await signIn(free.client);
    await free.model.restore();
    expect(free.model.mode, const Guardian());
  });

  test('a failed session read leaves the mode unknown', () async {
    final m = setUpModel((_) => problem(500, 'internal'));
    await signIn(m.client);
    await expectLater(m.model.restore(), throwsA(isA<ApiError>()));
    expect(m.model.mode, isNull);
  });

  test('hand-over and unlock move between the modes', () async {
    final m = setUpModel(server());
    await signIn(m.client);
    await m.model.restore();
    var notified = 0;
    m.model.addListener(() => notified++);

    await m.model.handOver('m1');
    expect(m.model.mode, const SharedKid('m1'));
    expect(await m.mark.read(), {'a1'});
    await m.model.unlock('2580');
    expect(m.model.mode, const Guardian());
    expect(await m.mark.read(), isEmpty);
    expect(notified, 2);
    expect(m.calls, [
      'GET /v1/session',
      'GET /v1/session',
      'POST /v1/parental/kid-mode {"minor_id":"m1"}',
      'GET /v1/session',
      'POST /v1/child/unlock {"pin":"2580"}',
    ]);
  });

  test('a signed-in device refuses to redeem', () async {
    final m = setUpModel(server());
    await signIn(m.client);
    await expectLater(
      m.model.redeem(code: 'ABCD-EFGH', label: 'Tablet'),
      throwsA(isA<SignedInDevice>()),
    );
    expect(m.calls, isEmpty);
  });

  test('redeeming and switching keep a linked device', () async {
    final m = setUpModel(server());
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();

    expect((await m.model.redeem(code: 'ABCD-EFGH', label: 'Tablet')).id, 'm1');
    expect(m.model.mode, const LinkedDevice('m1'));
    expect(m.devices.token, 'dev-token');
    expect((await m.model.listProfiles('2580')).single.id, 'm1');
    await m.model.switchProfile(pin: '2580', minorId: 'm2');
    expect(m.model.mode, const LinkedDevice('m2'));
  });

  test('an unlinked device falls back to the guardian mode', () async {
    final m = setUpModel(server(profilesStatus: 401), device: 'dev-token');
    await m.model.restore();
    await expectLater(m.model.listProfiles('2580'), throwsA(isA<ApiError>()));
    expect(m.model.mode, const Guardian());
    expect(m.devices.token, isNull);
  });

  test('a kid_mode refusal resyncs to kid mode', () async {
    final m = setUpModel(server(kidMode: {'minor_id': 'm1'}));
    await signIn(m.client);
    m.model.restoreAs(const Guardian());
    await expectLater(FamilyApi(m.client).load(), throwsA(isA<ApiError>()));
    await settle();
    expect(m.model.mode, const SharedKid('m1'));
  });

  test('losing the session in kid mode ends kid mode', () async {
    final m = setUpModel(server(kidMode: {'minor_id': 'm1'}));
    await signIn(m.client);
    await m.model.restore();
    await m.client.forgetSession();
    expect(m.model.mode, const Guardian());
  });

  test('a locked session restored sets the mark', () async {
    final m = setUpModel(server(kidMode: {'minor_id': 'm1'}));
    await signIn(m.client);
    await m.model.restore();
    expect(await m.mark.read(), {'a1'});
  });

  test('a kid_mode resync sets the mark', () async {
    final m = setUpModel(server(kidMode: {'minor_id': 'm1'}));
    await signIn(m.client);
    m.model.restoreAs(const Guardian());
    await expectLater(FamilyApi(m.client).load(), throwsA(isA<ApiError>()));
    await settle();
    expect(await m.mark.read(), {'a1'});
  });

  test('restore with the mark and an unlocked session asks the PIN', () async {
    final m = setUpModel(server(), marked: 'a1');
    await signIn(m.client);
    await m.model.restore();
    expect(m.model.mode, const PinRequired());
    expect(await m.mark.read(), {'a1'});
  });

  test('restore without the mark opens the guardian mode', () async {
    final m = setUpModel(server());
    await signIn(m.client);
    await m.model.restore();
    expect(m.model.mode, const Guardian());
  });

  test('a sign-in after losing the session in kid mode asks the PIN', () async {
    var locked = true;
    final m = setUpModel(
      (req) => server(kidMode: locked ? {'minor_id': 'm1'} : null)(req),
    );
    await signIn(m.client);
    await m.model.restore();
    await m.client.forgetSession();
    expect(m.model.mode, const Guardian());
    expect(await m.mark.read(), {'a1'});

    locked = false;
    await signIn(m.client);
    await settle();
    expect(m.model.mode, const PinRequired());
  });

  test('a sign-in without the mark stays a guardian', () async {
    final m = setUpModel(server());
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();
    await signIn(m.client);
    await settle();
    expect(m.model.mode, const Guardian());
  });

  test('losing the session while the PIN is asked leaves the mark', () async {
    final m = setUpModel(server(), marked: 'a1');
    await signIn(m.client);
    await m.model.restore();
    await m.client.forgetSession();
    expect(m.model.mode, const Guardian());
    expect(await m.mark.read(), {'a1'});
  });

  test('verifyPin accepts the PIN and clears the mark', () async {
    final m = setUpModel(server(), marked: 'a1');
    await signIn(m.client);
    await m.model.restore();
    await m.model.verifyPin('2580');
    expect(m.model.mode, const Guardian());
    expect(await m.mark.read(), isEmpty);
    expect(m.calls, contains('POST /v1/parental/pin/verify {"pin":"2580"}'));
  });

  test('verifyPin rethrows a wrong PIN and keeps asking', () async {
    final m = setUpModel(
      server(verifyProblem: (403, 'invalid_pin')),
      marked: 'a1',
    );
    await signIn(m.client);
    await m.model.restore();
    await expectLater(
      m.model.verifyPin('1357'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_pin')),
    );
    expect(m.model.mode, const PinRequired());
    expect(await m.mark.read(), {'a1'});
  });

  for (final (status, code) in [(404, 'no_family'), (409, 'pin_not_set')]) {
    test('verifyPin with $code has no PIN to give', () async {
      final m = setUpModel(server(verifyProblem: (status, code)), marked: 'a1');
      await signIn(m.client);
      await m.model.restore();
      await m.model.verifyPin('2580');
      expect(m.model.mode, const Guardian());
      expect(await m.mark.read(), isEmpty);
    });
  }

  test('another account cannot clear the mark', () async {
    var acct = 'b1';
    final m = setUpModel(
      server(verifyProblem: (404, 'no_family'), account: () => acct),
      marked: 'a1',
    );
    await signIn(m.client);
    await m.model.restore();
    expect(m.model.mode, const PinRequired());
    await m.model.verifyPin('2580'); // B has no family: nothing to give
    expect(m.model.mode, const Guardian());
    expect(await m.mark.read(), {'a1'});

    await m.client.forgetSession();
    acct = 'a1';
    await signIn(m.client);
    await settle();
    expect(m.model.mode, const PinRequired());
  });

  test('another account verifying its own PIN keeps the mark', () async {
    final m = setUpModel(server(account: () => 'b1'), marked: 'a1');
    await signIn(m.client);
    await m.model.restore();
    await m.model.verifyPin('2580');
    expect(m.model.mode, const Guardian());
    expect(await m.mark.read(), {'a1'});
  });

  test('the marked account without a family clears the mark', () async {
    final m = setUpModel(
      server(verifyProblem: (404, 'no_family')),
      marked: 'a1',
    );
    await signIn(m.client);
    await m.model.restore();
    await m.model.verifyPin('2580');
    expect(m.model.mode, const Guardian());
    expect(await m.mark.read(), isEmpty);
  });

  test('a sign-in is unknown until the mark is read', () async {
    final mark = ControlledMark();
    final m = setUpModel(server(), markOverride: mark);
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();
    await signIn(m.client);
    expect(m.model.mode, isNull);
    mark.read$.complete({'a1'});
    await settle();
    expect(m.model.mode, const PinRequired());
  });

  test('without a mark the unknown sign-in resolves to guardian', () async {
    final mark = ControlledMark();
    final m = setUpModel(server(), markOverride: mark);
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();
    await signIn(m.client);
    mark.read$.complete({});
    await settle();
    expect(m.model.mode, const Guardian());
  });

  test('a sign-out while the mark is read wins', () async {
    final mark = ControlledMark();
    final m = setUpModel(server(), markOverride: mark);
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();
    await signIn(m.client);
    await m.client.forgetSession();
    mark.read$.complete({'a1'});
    await settle();
    expect(m.model.mode, const Guardian());
  });

  test('a failing mark read fails closed', () async {
    final m = setUpModel(server(), markOverride: ThrowingMark());
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();
    await signIn(m.client);
    await settle();
    expect(m.model.mode, const PinRequired());
  });

  test('rebinding the mark through another account cannot clear it', () async {
    var acct = 'b1';
    final m = setUpModel(server(account: () => acct), marked: 'a1');
    await signIn(m.client);
    await m.model.restore();
    await m.model.verifyPin('2580'); // B's own PIN: Guardian, mark stays
    expect(await m.mark.read(), {'a1'});
    await m.model.handOver('m9'); // B's own child
    expect(await m.mark.read(), {'a1', 'b1'});
    await m.model.unlock('2580');
    expect(await m.mark.read(), {'a1'});

    await m.client.forgetSession();
    acct = 'a1';
    await signIn(m.client);
    await settle();
    expect(m.model.mode, const PinRequired());
  });

  test('the gate holds while any marked account remains', () async {
    final m = setUpModel(server(account: () => 'a1'), marked: 'a1');
    await m.mark.add('b1');
    await signIn(m.client);
    await m.model.restore();
    await m.model.verifyPin('2580');
    expect(await m.mark.read(), {'b1'});
    await m.client.forgetSession();
    await signIn(m.client);
    await settle();
    expect(m.model.mode, const PinRequired());
  });

  test('a hand-over during the mark read wins', () async {
    final mark = ControlledMark();
    final m = setUpModel(server(), markOverride: mark);
    m.client.status.value = AuthStatus.signedOut;
    await m.model.restore();
    await signIn(m.client);
    expect(m.model.mode, isNull);
    await m.model.handOver('m1');
    mark.read$.complete({});
    await settle();
    expect(m.model.mode, const SharedKid('m1'));
  });

  test('the app services build one AppModeModel', () {
    expect(Harness().services.appMode, isA<AppModeModel>());
  });
}
