import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/auth_api.dart' show PlatformRole;
import 'package:telinha_segura/staff/accounts_api.dart';

import '../auth/fakes.dart';

const actionJson = {
  'id': 7,
  'occurred_at': '2026-10-08T12:00:00Z',
  'event': 'account_looked_up',
  'actor_id': 'a1',
  'actor_email': 'ana@example.com',
  'actor_role': 'admin',
  'subject_kind': 'account',
  'subject_id': 'a2',
  'subject_email_masked': 'b•••@e•••.com',
  'reason': 'Pedido de suporte.',
  'metadata': {'by': 'email'},
};

const sheetJson = {
  'account_id': 'a2',
  'email_masked': 'b•••@e•••.com',
  'email_verified': true,
  'created_at': '2026-10-01T12:00:00Z',
  'providers': ['password', 'google'],
  'roles': ['curator', 'auditor'],
  'mfa_enrolled': false,
  'family': {'role': 'owner', 'minors': 2, 'devices': 1},
  'devices': [
    {
      'id': 'd1',
      'linked_at': '2026-10-02T12:00:00Z',
      'last_seen_at': '2026-10-08T11:00:00Z',
    },
  ],
  'sessions': [
    {
      'client': 'web',
      'created_at': '2026-10-08T10:00:00Z',
      'last_seen_at': '2026-10-08T11:30:00Z',
    },
  ],
  'actions': [actionJson],
};

const suspensionJson = {
  'since': '2026-10-08T12:00:00Z',
  'reason': 'Denuncia de conteudo improprio.',
};

http.Response contract(http.Request req) =>
    switch ('${req.method} ${req.url.path}') {
      'POST /v1/admin/accounts/lookup' => json(200, sheetJson),
      'POST /v1/admin/accounts/a2/sessions/revoke' => json(200, {
        ...sheetJson,
        'sessions': <Object>[],
      }),
      'POST /v1/admin/accounts/a2/devices/d1/unlink' => json(200, {
        ...sheetJson,
        'devices': <Object>[],
      }),
      'POST /v1/admin/accounts/a2/password-reset' => json(200, sheetJson),
      'GET /v1/admin/audit' => json(200, {
        'actions': [actionJson],
        'next_offset': req.url.queryParameters['offset'] == null ? 50 : null,
      }),
      'GET /v1/admin/metrics' => json(200, {
        'accounts': 120,
        'families': 40,
        'minors': null,
        'active_devices': 12,
        'published_videos': 300,
        'published_packs': null,
        'reports_7d': null,
        'suppressed_below': 5,
      }),
      'POST /v1/admin/accounts/a2/suspend' => json(200, {
        ...sheetJson,
        'roles': <Object>[],
        'sessions': <Object>[],
        'suspension': suspensionJson,
      }),
      'POST /v1/admin/accounts/a2/reinstate' => json(200, {
        ...sheetJson,
        'roles': <Object>[],
        'suspension': null,
      }),
      _ => http.Response('', 404),
    };

void main() {
  test('every call hits its contract path', () async {
    final t = build(ClientKind.mobile, contract);
    final api = AccountsApi(t.client);
    await api.lookup(email: 'bia@example.com', reason: 'Pedido de suporte.');
    await api.lookup(accountId: 'a2', reason: 'Pedido de suporte.');
    await api.revokeSessions('a2', reason: 'Pedido do titular.');
    await api.unlinkDevice('a2', 'd1', reason: 'Pedido do titular.');
    await api.sendPasswordReset('a2', reason: 'Pedido do titular.');
    await api.auditLog();
    await api.auditLog(offset: 50);
    await api.metrics();
    expect(t.calls, [
      'POST /v1/admin/accounts/lookup {"email":"bia@example.com","reason":"Pedido de suporte."}',
      'POST /v1/admin/accounts/lookup {"account_id":"a2","reason":"Pedido de suporte."}',
      'POST /v1/admin/accounts/a2/sessions/revoke {"reason":"Pedido do titular."}',
      'POST /v1/admin/accounts/a2/devices/d1/unlink {"reason":"Pedido do titular."}',
      'POST /v1/admin/accounts/a2/password-reset {"reason":"Pedido do titular."}',
      'GET /v1/admin/audit',
      'GET /v1/admin/audit?offset=50',
      'GET /v1/admin/metrics',
    ]);
  });

  test('the sheet parses into typed models', () async {
    final api = AccountsApi(build(ClientKind.mobile, contract).client);
    final sh = await api.lookup(accountId: 'a2', reason: 'Pedido de suporte.');
    expect(sh.accountId, 'a2');
    expect(sh.emailMasked, 'b•••@e•••.com');
    expect(sh.emailVerified, isTrue);
    expect(sh.createdAt, DateTime.utc(2026, 10, 1, 12));
    expect(sh.providers, ['password', 'google']);
    expect(sh.roles, {PlatformRole.curator});
    expect(sh.mfaEnrolled, isFalse);
    expect(sh.family!.role, 'owner');
    expect(sh.family!.minors, 2);
    expect(sh.family!.devices, 1);
    expect(sh.devices.single.id, 'd1');
    expect(sh.devices.single.lastSeenAt, DateTime.utc(2026, 10, 8, 11));
    expect(sh.sessions.single.client, 'web');
    final a = sh.actions.single;
    expect(a.id, 7);
    expect(a.occurredAt, DateTime.utc(2026, 10, 8, 12));
    expect(a.event, 'account_looked_up');
    expect(a.actorEmail, 'ana@example.com');
    expect(a.subjectEmailMasked, 'b•••@e•••.com');
    expect(a.reason, 'Pedido de suporte.');
    expect(a.metadata, {'by': 'email'});

    final revoked = await api.revokeSessions(
      'a2',
      reason: 'Pedido do titular.',
    );
    expect(revoked.sessions, isEmpty);
  });

  test('a sheet with no family and an action with nulls', () {
    final sh = AccountSheet.fromJson({...sheetJson, 'family': null});
    expect(sh.family, isNull);
    final a = AuditAction.fromJson({
      ...actionJson,
      'actor_email': null,
      'subject_kind': null,
      'subject_id': null,
      'subject_email_masked': null,
      'reason': null,
      'metadata': null,
    });
    expect(a.actorEmail, isNull);
    expect(a.subjectKind, isNull);
    expect(a.subjectId, isNull);
    expect(a.subjectEmailMasked, isNull);
    expect(a.reason, isNull);
    expect(a.metadata, isEmpty);
  });

  test('audit pages and suppressed metrics', () async {
    final api = AccountsApi(build(ClientKind.mobile, contract).client);
    final first = await api.auditLog();
    expect(first.actions, hasLength(1));
    expect(first.nextOffset, 50);
    expect((await api.auditLog(offset: 50)).nextOffset, isNull);

    final m = await api.metrics();
    expect(m.accounts, 120);
    expect(m.families, 40);
    expect(m.minors, isNull);
    expect(m.activeDevices, 12);
    expect(m.publishedVideos, 300);
    expect(m.publishedPacks, isNull);
    expect(m.reports7d, isNull);
    expect(m.suppressedBelow, 5);
  });

  test('every directory problem code surfaces as an ApiError', () async {
    const problems = {
      'validation': 422,
      'reason_required': 422,
      'account_not_found': 404,
      'device_not_found': 404,
      'self_action': 403,
      'rate_limited': 429,
      'not_admin': 403,
      'mfa_enrollment_required': 403,
      'elevation_required': 403,
      'reauth_required': 403,
    };
    for (final MapEntry(key: code, value: status) in problems.entries) {
      final api = AccountsApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.unlinkDevice('a2', 'd1', reason: 'Pedido do titular.'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.status, 'status', status),
        ),
      );
    }
  });

  test('suspend and reinstate answer the sheet with its suspension', () async {
    final t = build(ClientKind.mobile, contract);
    final api = AccountsApi(t.client);
    final suspended = await api.suspend(
      'a2',
      reason: 'Denuncia de conteudo improprio.',
    );
    expect(suspended.suspension!.since, DateTime.utc(2026, 10, 8, 12));
    expect(suspended.suspension!.reason, 'Denuncia de conteudo improprio.');
    expect(suspended.roles, isEmpty);
    expect(suspended.sessions, isEmpty);
    final reinstated = await api.reinstate('a2', reason: 'Revisao concluida.');
    expect(reinstated.suspension, isNull);
    expect(reinstated.roles, isEmpty);
    expect(t.calls, [
      'POST /v1/admin/accounts/a2/suspend {"reason":"Denuncia de conteudo improprio."}',
      'POST /v1/admin/accounts/a2/reinstate {"reason":"Revisao concluida."}',
    ]);
    expect(AccountSheet.fromJson(sheetJson).suspension, isNull);
  });

  test('every suspension problem code surfaces as an ApiError', () async {
    const problems = [
      (code: 'account_suspended', status: 403),
      (code: 'account_suspended', status: 409),
      (code: 'subject_is_admin', status: 403),
      (code: 'already_suspended', status: 409),
      (code: 'not_suspended', status: 409),
      (code: 'self_action', status: 403),
      (code: 'account_not_found', status: 404),
      (code: 'reason_required', status: 422),
    ];
    for (final (:code, :status) in problems) {
      final api = AccountsApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.suspend('a2', reason: 'Denuncia de conteudo improprio.'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.status, 'status', status),
        ),
      );
    }
  });
}
