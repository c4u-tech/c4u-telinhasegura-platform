import 'dart:async';

import 'package:http/http.dart' as http;

import '../access/harness.dart';

/// The day the factor was enrolled in the fixtures: 7 October of this
/// year, so it reads without a year.
final enrolledDay = DateTime.utc(DateTime.now().year, 10, 7, 12);

/// `GET /v1/staff/mfa` as the server answers it.
Map<String, Object?> mfaStatusJson({
  bool enrolled = true,
  int codesLeft = 7,
  bool required = true,
  DateTime? elevatedUntil,
}) => {
  'enrolled': enrolled,
  'enrolled_at': enrolled ? enrolledDay.toIso8601String() : null,
  'recovery_codes_left': enrolled ? codesLeft : 0,
  'elevated_until': elevatedUntil?.toIso8601String(),
  'required': required,
};

const testSecret = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';

const testUri =
    'otpauth://totp/Telinha%20Segura:ana%40example.com?secret=$testSecret'
    '&issuer=Telinha%20Segura&algorithm=SHA1&digits=6&period=30';

/// `POST /v1/staff/mfa/enrollment`'s answer.
Map<String, Object?> enrollmentJson({String secret = testSecret}) => {
  'secret': secret,
  'otpauth_uri': testUri,
};

/// Ten recovery codes, as the server shows them once.
List<String> testCodes([String prefix = 'ABCDE']) => [
  for (var i = 0; i < 10; i++) '$prefix-${'FGHJK'.substring(0, 4)}$i',
];

Map<String, Object?> codesJson({List<String>? codes, bool elevated = true}) => {
  'recovery_codes': codes ?? testCodes(),
  if (elevated)
    'elevated_until': DateTime.now()
        .add(const Duration(minutes: 30))
        .toUtc()
        .toIso8601String(),
};

/// `POST /v1/staff/mfa/challenge`'s answer, with [left] recovery codes.
Map<String, Object?> elevationJson({int left = 7}) => {
  'elevated_until': DateTime.now()
      .add(const Duration(minutes: 30))
      .toUtc()
      .toIso8601String(),
  'recovery_codes_left': left,
};

/// An API whose MFA routes answer [status], [start], [confirm],
/// [challenge] and [regenerate] (each a 200 or 201 by default), and whose
/// other routes answer [other] (204 by default).
FutureOr<http.Response> Function(http.Request) mfaApi({
  FutureOr<http.Response> Function()? status,
  FutureOr<http.Response> Function()? start,
  FutureOr<http.Response> Function(http.Request)? confirm,
  FutureOr<http.Response> Function(http.Request)? challenge,
  FutureOr<http.Response> Function()? regenerate,
  FutureOr<http.Response> Function(http.Request)? other,
}) =>
    (req) => switch ((req.method, req.url.path)) {
      ('GET', '/v1/staff/mfa') =>
        (status ?? () => json(200, mfaStatusJson()))(),
      ('POST', '/v1/staff/mfa/enrollment') =>
        (start ?? () => json(201, enrollmentJson()))(),
      ('POST', '/v1/staff/mfa/enrollment/confirm') =>
        (confirm ?? (_) => json(200, codesJson()))(req),
      ('POST', '/v1/staff/mfa/challenge') =>
        (challenge ?? (_) => json(200, elevationJson()))(req),
      ('POST', '/v1/staff/mfa/recovery-codes') =>
        (regenerate ?? () => json(200, codesJson(elevated: false)))(),
      ('GET', '/v1/sessions') => json(200, {'sessions': <Object>[]}),
      _ => other?.call(req) ?? http.Response('', 204),
    };
