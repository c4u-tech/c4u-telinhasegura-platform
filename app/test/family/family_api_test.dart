import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/family_api.dart';

import '../access/harness.dart' show Harness;
import '../auth/fakes.dart';
import 'fixtures.dart';

const minorJson = {
  'id': 'm1',
  'nickname': 'Lia',
  'avatar': 'fox',
  'age_band': '5-8',
  'created_at': '2026-10-03T12:30:00Z',
  'updated_at': '2026-10-03T12:30:00Z',
};

http.Response contract(http.Request req) {
  final p = req.url.path;
  if (req.method == 'DELETE' || p == '/v1/family/leave') {
    return http.Response('', 204);
  }
  if (p == '/v1/family/invitations') {
    return json(201, {
      'id': 'i1',
      'email': 'bia@example.com',
      'expires_at': '2026-10-10T12:00:00Z',
    });
  }
  if (p == '/v1/invitations/lookup') {
    return json(200, {
      'inviter_email': 'ana@example.com',
      'invited_email': 'bia@example.com',
      'expires_at': '2026-10-10T12:00:00Z',
    });
  }
  if (p == '/v1/invitations') {
    return json(200, {
      'invitations': [receivedInvitation],
    });
  }
  if (p.endsWith('/consent')) return http.Response('', 204);
  if (p.startsWith('/v1/family/minors')) return json(201, minorJson);
  return json(200, ownerFamily);
}

void main() {
  test('every call hits its contract path and body', () async {
    final t = build(ClientKind.web, contract);
    final api = FamilyApi(t.client);
    await api.create();
    await api.load();
    await api.invite('bia@example.com');
    await api.revokeInvitation('i 1');
    await api.lookupInvitation('tok');
    await api.acceptInvitation('tok');
    await api.pendingInvitations();
    await api.acceptInvitationById('i 1');
    await api.removeGuardian('a2');
    await api.leave();
    await api.transferOwnership('a2');
    await api.createMinor(
      nickname: 'Lia',
      avatar: Avatar.fox,
      ageBand: AgeBand.from5To8,
    );
    await api.updateMinor('m1', avatar: Avatar.owl);
    await api.updateMinor('m1', nickname: 'Liazinha', ageBand: AgeBand.upTo4);
    await api.deleteMinor('m1');
    await api.grantConsent('m 1');
    await api.delete();

    expect(t.calls, [
      'POST /v1/family',
      'GET /v1/family',
      'POST /v1/family/invitations {"email":"bia@example.com"}',
      'DELETE /v1/family/invitations/i%201',
      'POST /v1/invitations/lookup {"token":"tok"}',
      'POST /v1/invitations/accept {"token":"tok"}',
      'GET /v1/invitations',
      'POST /v1/invitations/i%201/accept',
      'DELETE /v1/family/members/a2',
      'POST /v1/family/leave',
      'POST /v1/family/owner {"account_id":"a2"}',
      'POST /v1/family/minors {"nickname":"Lia","avatar":"fox","age_band":"5-8",'
          '"consent":{"policy_version":"$kConsentPolicyVersion"}}',
      'PATCH /v1/family/minors/m1 {"avatar":"owl"}',
      'PATCH /v1/family/minors/m1 {"nickname":"Liazinha","age_band":"ate-4"}',
      'DELETE /v1/family/minors/m1',
      'POST /v1/family/minors/m%201/consent '
          '{"policy_version":"$kConsentPolicyVersion"}',
      'DELETE /v1/family',
    ]);
  });

  test('responses parse into the value types', () async {
    final api = FamilyApi(build(ClientKind.mobile, contract).client);
    expect((await api.load()).members.length, 2);
    expect((await api.invite('bia@example.com')).id, 'i1');
    expect((await api.lookupInvitation('t')).inviterEmail, 'ana@example.com');
    final received = (await api.pendingInvitations()).single;
    expect(received.id, 'i1');
    expect(received.inviterEmail, 'carla@example.com');
    expect(received.expiresAt, DateTime.utc(2026, 10, 10, 12));
    expect((await api.acceptInvitationById('i1')).members.length, 2);
    expect(
      (await api.createMinor(
        nickname: 'Lia',
        avatar: Avatar.fox,
        ageBand: AgeBand.from5To8,
      )).avatar,
      Avatar.fox,
    );
  });

  test('problems surface as ApiError codes', () async {
    final api = FamilyApi(
      build(ClientKind.web, (_) => problem(403, 'reauth_required')).client,
    );
    await expectLater(
      api.deleteMinor('m1'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'reauth_required')),
    );
  });

  test('the app services build one FamilyApi', () {
    expect(Harness().services.family, isA<FamilyApi>());
  });
}
