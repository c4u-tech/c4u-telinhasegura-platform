import '../auth/api_client.dart';
import 'family.dart';

/// The family contract, one method per endpoint. Problems
/// surface as `ApiError`; on `reauth_required` the screen re-authenticates
/// and retries.
class FamilyApi {
  FamilyApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async =>
      await _client.send(method, path, body: body) as Map<String, dynamic>;

  Future<Family> create() async =>
      Family.fromJson(await _json('POST', '/v1/family'));

  Future<Family> load() async =>
      Family.fromJson(await _json('GET', '/v1/family'));

  /// Needs a re-authentication within the last 5 minutes.
  Future<void> delete() => _client.send('DELETE', '/v1/family');

  Future<PendingInvitation> invite(String email) async =>
      PendingInvitation.fromJson(
        await _json('POST', '/v1/family/invitations', body: {'email': email}),
      );

  Future<void> revokeInvitation(String id) => _client.send(
    'DELETE',
    '/v1/family/invitations/${Uri.encodeComponent(id)}',
  );

  Future<InvitationPreview> lookupInvitation(String token) async =>
      InvitationPreview.fromJson(
        await _json('POST', '/v1/invitations/lookup', body: {'token': token}),
      );

  Future<Family> acceptInvitation(String token) async => Family.fromJson(
    await _json('POST', '/v1/invitations/accept', body: {'token': token}),
  );

  /// The pending invitations to the caller's verified email; empty once
  /// the caller has a family.
  Future<List<ReceivedInvitation>> pendingInvitations() async => [
    for (final j
        in (await _json('GET', '/v1/invitations'))['invitations'] as List)
      ReceivedInvitation.fromJson(j as Map<String, dynamic>),
  ];

  /// Takes the pending invitation [id], addressed to the caller's own
  /// email.
  Future<Family> acceptInvitationById(String id) async => Family.fromJson(
    await _json('POST', '/v1/invitations/${Uri.encodeComponent(id)}/accept'),
  );

  Future<void> removeGuardian(String accountId) => _client.send(
    'DELETE',
    '/v1/family/members/${Uri.encodeComponent(accountId)}',
  );

  Future<void> leave() => _client.send('POST', '/v1/family/leave');

  /// Needs a re-authentication within the last 5 minutes.
  Future<Family> transferOwnership(String accountId) async => Family.fromJson(
    await _json('POST', '/v1/family/owner', body: {'account_id': accountId}),
  );

  /// Records consent to [kConsentPolicyVersion], the text the screen shows.
  Future<Minor> createMinor({
    required String nickname,
    required Avatar avatar,
    required AgeBand ageBand,
  }) async => Minor.fromJson(
    await _json(
      'POST',
      '/v1/family/minors',
      body: {
        'nickname': nickname,
        'avatar': avatar.wire,
        'age_band': ageBand.wire,
        'consent': {'policy_version': kConsentPolicyVersion},
      },
    ),
  );

  /// Sends only the fields given.
  Future<Minor> updateMinor(
    String id, {
    String? nickname,
    Avatar? avatar,
    AgeBand? ageBand,
  }) async => Minor.fromJson(
    await _json(
      'PATCH',
      '/v1/family/minors/${Uri.encodeComponent(id)}',
      body: {
        'nickname': ?nickname,
        'avatar': ?avatar?.wire,
        'age_band': ?ageBand?.wire,
      },
    ),
  );

  /// Needs a re-authentication within the last 5 minutes.
  Future<void> deleteMinor(String id) =>
      _client.send('DELETE', '/v1/family/minors/${Uri.encodeComponent(id)}');
}
