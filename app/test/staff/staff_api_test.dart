import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/auth_api.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/staff/staff.dart';
import 'package:telinha_segura/staff/staff_api.dart';

import '../auth/fakes.dart';

const memberJson = {
  'account_id': 'a2',
  'email': 'bia@example.com',
  'roles': [
    {
      'role': 'curator',
      'granted_at': '2026-10-07T12:00:00Z',
      'display_role': 'pedagogo',
      'verified_professional': true,
    },
    {'role': 'moderator', 'granted_at': '2026-10-07T13:00:00Z'},
  ],
};

const heldJson = {
  'video': {
    'id': 'v1',
    'youtube_id': 'dQw4w9WgXcQ',
    'title': 'Baby Shark',
    'channel_id': 'UC1',
    'channel_title': 'Canal Baby Shark',
    'duration_seconds': 300,
    'state': 'held',
    'round': 1,
    'theme': null,
    'min_age_band': null,
    'last_reviewed_at': null,
    'review_due_at': null,
    'created_at': '2026-10-07T11:00:00Z',
  },
  'rejections': <Object>[],
  'held_reason': 'reports',
  'reports': {
    'by_reason': {'assustador': 3},
    'notes': <Object>[],
  },
};

http.Response contract(http.Request req) =>
    switch ('${req.method} ${req.url.path}') {
      'GET /v1/admin/staff' => json(200, {
        'staff': [memberJson],
      }),
      'POST /v1/admin/staff' => json(201, memberJson),
      'PATCH /v1/admin/staff/a2/curator' => json(200, memberJson),
      'POST /v1/admin/staff/a2/roles/moderator/revoke' => json(200, {
        ...memberJson,
        'roles': <Object>[],
      }),
      'GET /v1/moderation/videos' => json(200, {
        'videos': [heldJson],
      }),
      _ => http.Response('', 204),
    };

void main() {
  test('every call hits its contract path', () async {
    final t = build(ClientKind.mobile, contract);
    final api = StaffApi(t.client);
    await api.staff();
    await api.grant(
      email: 'bia@example.com',
      role: PlatformRole.curator,
      displayRole: DisplayRole.pedagogo,
      verifiedProfessional: true,
      reason: 'Pedagoga da equipe.',
    );
    await api.grant(
      email: 'caio@example.com',
      role: PlatformRole.moderator,
      reason: 'Cuida dos retidos.',
    );
    await api.updateCurator(
      'a2',
      displayRole: DisplayRole.maePai,
      reason: 'Mudou de papel.',
    );
    await api.revoke('a2', PlatformRole.moderator, reason: 'Saiu da equipe.');
    await api.heldVideos();
    await api.removeVideo('v1', reason: 'Propaganda no meio.');
    await api.reopenVideo('v1', reason: 'Canal corrigiu.');
    expect(t.calls, [
      'GET /v1/admin/staff',
      'POST /v1/admin/staff {"email":"bia@example.com","role":"curator","display_role":"pedagogo","verified_professional":true,"reason":"Pedagoga da equipe."}',
      'POST /v1/admin/staff {"email":"caio@example.com","role":"moderator","reason":"Cuida dos retidos."}',
      'PATCH /v1/admin/staff/a2/curator {"display_role":"mae-pai","reason":"Mudou de papel."}',
      'POST /v1/admin/staff/a2/roles/moderator/revoke {"reason":"Saiu da equipe."}',
      'GET /v1/moderation/videos?state=held',
      'POST /v1/moderation/videos/v1/remove {"reason":"Propaganda no meio."}',
      'POST /v1/moderation/videos/v1/reopen {"reason":"Canal corrigiu."}',
    ]);
  });

  test('the bodies parse into typed models', () async {
    final api = StaffApi(build(ClientKind.mobile, contract).client);

    final member = (await api.staff()).single;
    expect(member.accountId, 'a2');
    expect(member.email, 'bia@example.com');
    expect(member.roles.map((r) => r.role), [
      PlatformRole.curator,
      PlatformRole.moderator,
    ]);
    expect(member.roles.first.displayRole, DisplayRole.pedagogo);
    expect(member.roles.first.displayRole!.professional, isTrue);
    expect(member.roles.first.verifiedProfessional, isTrue);
    expect(member.roles.first.grantedAt, DateTime.utc(2026, 10, 7, 12));
    expect(member.roles.last.displayRole, isNull);
    expect(member.roles.last.verifiedProfessional, isNull);

    final left = await api.revoke(
      'a2',
      PlatformRole.moderator,
      reason: 'Saiu da equipe.',
    );
    expect(left.roles, isEmpty);

    final held = (await api.heldVideos()).single;
    expect(held.video.state, VideoState.held);
    expect(held.heldReason, HeldReason.reports);
  });

  test('a role this app does not know is skipped', () {
    final m = StaffMember.fromJson({
      'account_id': 'a3',
      'email': 'dani@example.com',
      'roles': [
        {'role': 'admin', 'granted_at': '2026-10-07T12:00:00Z'},
        {'role': 'support', 'granted_at': '2026-10-07T12:00:00Z'},
      ],
    });
    expect(m.roles.single.role, PlatformRole.admin);
  });

  test('every staff problem code surfaces as an ApiError', () async {
    const codes = {
      'reason_required': 422,
      'validation': 422,
      'self_appointment': 403,
      'admin_cli_only': 403,
      'already_has_role': 409,
      'account_not_found': 404,
      'email_unverified': 409,
      'not_found': 404,
      'state_conflict': 409,
      'not_moderator': 403,
      'not_admin': 403,
      'reauth_required': 403,
    };
    for (final MapEntry(key: code, value: status) in codes.entries) {
      final api = StaffApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.removeVideo('v1', reason: 'Propaganda no meio.'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.status, 'status', status),
        ),
      );
    }
  });
}
