import '../auth/api_client.dart';
import 'accounts.dart';

export 'accounts.dart';

/// The account directory, support and metrics contract and the
/// suspension contract, one method per
/// route, for an admin. Problems surface as `ApiError`. Beside today's
/// codes, they are:
/// - `account_not_found`, `device_not_found`, `self_action`,
///   `reason_required`;
/// - `rate_limited` (30 lookups an hour, 3 reset emails an hour per
///   account);
/// - `subject_is_admin`, `already_suspended` and `not_suspended`.
///
/// The support actions and the suspension need a re-authentication
/// within 5 minutes. Each answers the refreshed sheet.
class AccountsApi {
  AccountsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async =>
      await _client.send(method, path, body: body) as Map<String, dynamic>;

  static String _id(String id) => Uri.encodeComponent(id);

  /// Finds one account by exactly one of [email] and [accountId].
  Future<AccountSheet> lookup({
    String? email,
    String? accountId,
    required String reason,
  }) async {
    assert(
      (email == null) != (accountId == null),
      'exactly one of email and accountId',
    );
    return AccountSheet.fromJson(
      await _json(
        'POST',
        '/v1/admin/accounts/lookup',
        body: {'email': ?email, 'account_id': ?accountId, 'reason': reason},
      ),
    );
  }

  Future<AccountSheet> revokeSessions(
    String accountId, {
    required String reason,
  }) async => AccountSheet.fromJson(
    await _json(
      'POST',
      '/v1/admin/accounts/${_id(accountId)}/sessions/revoke',
      body: {'reason': reason},
    ),
  );

  Future<AccountSheet> unlinkDevice(
    String accountId,
    String deviceId, {
    required String reason,
  }) async => AccountSheet.fromJson(
    await _json(
      'POST',
      '/v1/admin/accounts/${_id(accountId)}/devices/${_id(deviceId)}/unlink',
      body: {'reason': reason},
    ),
  );

  Future<AccountSheet> sendPasswordReset(
    String accountId, {
    required String reason,
  }) async => AccountSheet.fromJson(
    await _json(
      'POST',
      '/v1/admin/accounts/${_id(accountId)}/password-reset',
      body: {'reason': reason},
    ),
  );

  /// Suspends the account: its sessions end, its platform roles drop, and
  /// it reaches only its export, its erasure and signing out.
  Future<AccountSheet> suspend(
    String accountId, {
    required String reason,
  }) async => AccountSheet.fromJson(
    await _json(
      'POST',
      '/v1/admin/accounts/${_id(accountId)}/suspend',
      body: {'reason': reason},
    ),
  );

  /// Ends the suspension. The status returns; the roles do not.
  Future<AccountSheet> reinstate(
    String accountId, {
    required String reason,
  }) async => AccountSheet.fromJson(
    await _json(
      'POST',
      '/v1/admin/accounts/${_id(accountId)}/reinstate',
      body: {'reason': reason},
    ),
  );

  /// The staff audit log, newest first, 50 per page.
  Future<AuditPage> auditLog({int offset = 0}) async => AuditPage.fromJson(
    await _json(
      'GET',
      offset == 0 ? '/v1/admin/audit' : '/v1/admin/audit?offset=$offset',
    ),
  );

  Future<Metrics> metrics() async =>
      Metrics.fromJson(await _json('GET', '/v1/admin/metrics'));
}
