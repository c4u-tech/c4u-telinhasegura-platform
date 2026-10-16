import '../auth/api_client.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../curation/curation.dart' show DisplayRole, HeldVideo;
import 'staff.dart';

/// The staff contract, one method per route: the
/// team routes answer an admin, the moderation routes a moderator or an
/// admin. Problems surface as `ApiError`; beside today's codes they are
/// `reason_required`, `self_appointment`, `admin_cli_only`,
/// `already_has_role` and `not_moderator`. Every write carries a reason
/// of 3 to 200 characters. Granting, changing and revoking a role, and
/// removing a video, need a re-authentication within 5 minutes.
class StaffApi {
  StaffApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async =>
      await _client.send(method, path, body: body) as Map<String, dynamic>;

  static String _id(String id) => Uri.encodeComponent(id);

  /// Every account holding a role, admins included, the longest-serving
  /// first.
  Future<List<StaffMember>> staff() async => [
    for (final m
        in (await _json('GET', '/v1/admin/staff'))['staff'] as List<dynamic>)
      StaffMember.fromJson(m as Map<String, dynamic>),
  ];

  /// Grants curator (with its displayed role) or moderator. Admin is the
  /// server command's alone: asking for it answers `admin_cli_only`. A
  /// suspended account answers `account_suspended` (409).
  Future<StaffMember> grant({
    required String email,
    required PlatformRole role,
    DisplayRole? displayRole,
    bool? verifiedProfessional,
    required String reason,
  }) async => StaffMember.fromJson(
    await _json(
      'POST',
      '/v1/admin/staff',
      body: {
        'email': email,
        'role': role.name,
        'display_role': ?displayRole?.wire,
        'verified_professional': ?verifiedProfessional,
        'reason': reason,
      },
    ),
  );

  /// Changes what is given of a curator's displayed role and flag.
  Future<StaffMember> updateCurator(
    String accountId, {
    DisplayRole? displayRole,
    bool? verifiedProfessional,
    required String reason,
  }) async => StaffMember.fromJson(
    await _json(
      'PATCH',
      '/v1/admin/staff/${_id(accountId)}/curator',
      body: {
        'display_role': ?displayRole?.wire,
        'verified_professional': ?verifiedProfessional,
        'reason': reason,
      },
    ),
  );

  /// Takes [role] away; the member answered may hold none.
  Future<StaffMember> revoke(
    String accountId,
    PlatformRole role, {
    required String reason,
  }) async => StaffMember.fromJson(
    await _json(
      'POST',
      '/v1/admin/staff/${_id(accountId)}/roles/${role.name}/revoke',
      body: {'reason': reason},
    ),
  );

  /// The held videos, the longest held first, as [HeldVideo] reads them.
  Future<List<HeldVideo>> heldVideos() async => [
    for (final h
        in (await _json('GET', '/v1/moderation/videos?state=held'))['videos']
            as List<dynamic>)
      HeldVideo.fromJson(h as Map<String, dynamic>),
  ];

  Future<void> removeVideo(String id, {required String reason}) => _client.send(
    'POST',
    '/v1/moderation/videos/${_id(id)}/remove',
    body: {'reason': reason},
  );

  Future<void> reopenVideo(String id, {required String reason}) => _client.send(
    'POST',
    '/v1/moderation/videos/${_id(id)}/reopen',
    body: {'reason': reason},
  );
}
