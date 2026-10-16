import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/staff/mfa_api.dart';

import '../auth/fakes.dart';

const codes = [
  'AAAAA-BBBBB',
  'CCCCC-DDDDD',
  'EEEEE-FFFFF',
  'GGGGG-HHHHH',
  'IIIII-JJJJJ',
  'KKKKK-LLLLL',
  'MMMMM-NNNNN',
  'OOOOO-PPPPP',
  'QQQQQ-RRRRR',
  'SSSSS-TTTTT',
];

http.Response contract(http.Request req) =>
    switch ('${req.method} ${req.url.path}') {
      'GET /v1/staff/mfa' => json(200, {
        'enrolled': true,
        'enrolled_at': '2026-10-07T12:00:00Z',
        'recovery_codes_left': 9,
        'elevated_until': '2026-10-07T12:30:00Z',
        'required': true,
      }),
      'POST /v1/staff/mfa/enrollment' => json(201, {
        'secret': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', // gitleaks:allow (RFC 6238 test vector)
        'otpauth_uri': 'otpauth://totp/Telinha%20Segura:ana@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Telinha%20Segura&algorithm=SHA1&digits=6&period=30',
      }),
      'POST /v1/staff/mfa/enrollment/confirm' => json(200, {
        'recovery_codes': codes,
        'elevated_until': '2026-10-07T12:30:00Z',
      }),
      'POST /v1/staff/mfa/challenge' => json(200, {
        'elevated_until': '2026-10-07T13:00:00Z',
        'recovery_codes_left': 9,
      }),
      'POST /v1/staff/mfa/recovery-codes' => json(200, {
        'recovery_codes': codes,
      }),
      _ => http.Response('', 404),
    };

void main() {
  test('every call hits its contract path', () async {
    final t = build(ClientKind.mobile, contract);
    final api = MfaApi(t.client);
    await api.status();
    await api.startEnrollment();
    await api.confirmEnrollment('287082');
    await api.challenge(code: '287 082');
    await api.challenge(recoveryCode: 'AAAAA-BBBBB');
    await api.regenerateRecoveryCodes();
    expect(t.calls, [
      'GET /v1/staff/mfa',
      'POST /v1/staff/mfa/enrollment',
      'POST /v1/staff/mfa/enrollment/confirm {"code":"287082"}',
      'POST /v1/staff/mfa/challenge {"code":"287 082"}',
      'POST /v1/staff/mfa/challenge {"recovery_code":"AAAAA-BBBBB"}',
      'POST /v1/staff/mfa/recovery-codes',
    ]);
  });

  test('the bodies parse into typed models', () async {
    final api = MfaApi(build(ClientKind.mobile, contract).client);

    final st = await api.status();
    expect(st.enrolled, isTrue);
    expect(st.enrolledAt, DateTime.utc(2026, 10, 7, 12));
    expect(st.recoveryCodesLeft, 9);
    expect(st.elevatedUntil, DateTime.utc(2026, 10, 7, 12, 30));
    expect(st.mfaRequired, isTrue);

    final e = await api.startEnrollment();
    expect(
      e.secret,
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
    ); // gitleaks:allow (RFC 6238 test vector)
    expect(e.otpauthUri, startsWith('otpauth://totp/'));

    final confirmed = await api.confirmEnrollment('287082');
    expect(confirmed.codes, codes);
    expect(confirmed.elevatedUntil, DateTime.utc(2026, 10, 7, 12, 30));

    final el = await api.challenge(code: '287082');
    expect(el.elevatedUntil, DateTime.utc(2026, 10, 7, 13));
    expect(el.recoveryCodesLeft, 9);

    final fresh = await api.regenerateRecoveryCodes();
    expect(fresh.codes, hasLength(10));
    expect(fresh.elevatedUntil, isNull);
  });

  test('a status before enrolling has no times', () {
    final st = MfaStatus.fromJson({
      'enrolled': false,
      'recovery_codes_left': 0,
      'required': false,
    });
    expect(st.enrolled, isFalse);
    expect(st.enrolledAt, isNull);
    expect(st.elevatedUntil, isNull);
    expect(st.mfaRequired, isFalse);
  });

  test('every MFA problem code surfaces as an ApiError', () async {
    const problems = {
      'not_staff': 403,
      'mfa_unavailable': 503,
      'mfa_already_enrolled': 409,
      'mfa_not_pending': 409,
      'mfa_not_enrolled': 409,
      'mfa_code_invalid': 422,
      'validation': 422,
      'mfa_enrollment_required': 403,
      'elevation_required': 403,
      'rate_limited': 429,
      'reauth_required': 403,
    };
    for (final MapEntry(key: code, value: status) in problems.entries) {
      final api = MfaApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.challenge(code: '287082'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.status, 'status', status),
        ),
      );
    }
  });
}
