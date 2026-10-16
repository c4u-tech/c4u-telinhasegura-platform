import '../auth/api_client.dart';
import 'mfa.dart';

export 'mfa.dart';

/// The privileged MFA contract, one method per
/// route, for any platform role holder. Problems surface as `ApiError`;
/// beside today's codes they are `not_staff`, `mfa_unavailable`,
/// `mfa_already_enrolled`, `mfa_not_pending`, `mfa_not_enrolled`,
/// `mfa_code_invalid`, `mfa_enrollment_required` and
/// `elevation_required`, and `rate_limited` while the factor is blocked.
/// Starting an enrollment needs a re-authentication within 5 minutes;
/// new recovery codes need it and the elevation.
class MfaApi {
  MfaApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async =>
      await _client.send(method, path, body: body) as Map<String, dynamic>;

  Future<MfaStatus> status() async =>
      MfaStatus.fromJson(await _json('GET', '/v1/staff/mfa'));

  Future<MfaEnrollment> startEnrollment() async =>
      MfaEnrollment.fromJson(await _json('POST', '/v1/staff/mfa/enrollment'));

  /// Confirms the pending factor; the session is elevated at once.
  Future<RecoveryCodes> confirmEnrollment(String code) async =>
      RecoveryCodes.fromJson(
        await _json(
          'POST',
          '/v1/staff/mfa/enrollment/confirm',
          body: {'code': code},
        ),
      );

  /// Elevates the session with exactly one of [code] (six digits, spaces
  /// allowed) and [recoveryCode].
  Future<Elevation> challenge({String? code, String? recoveryCode}) async {
    assert(
      (code == null) != (recoveryCode == null),
      'exactly one of code and recoveryCode',
    );
    return Elevation.fromJson(
      await _json(
        'POST',
        '/v1/staff/mfa/challenge',
        body: {'code': ?code, 'recovery_code': ?recoveryCode},
      ),
    );
  }

  Future<RecoveryCodes> regenerateRecoveryCodes() async =>
      RecoveryCodes.fromJson(
        await _json('POST', '/v1/staff/mfa/recovery-codes'),
      );
}
