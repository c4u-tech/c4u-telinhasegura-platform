import '../auth/api_client.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../curation/curation.dart'
    show AuditCandidate, DisplayRole, HeldVideo, VideoTheme;
import '../family/family.dart' show AgeBand;
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

  /// Settles a video a curator's doubt holds: published with [theme] and
  /// [minAgeBand], or removed for good. Needs a re-authentication within
  /// 5 minutes; anything but a doubt answers `state_conflict`.
  Future<void> decideDoubt(
    String id, {
    required bool publish,
    VideoTheme? theme,
    AgeBand? minAgeBand,
    required String reason,
  }) => _client.send(
    'POST',
    '/v1/moderation/videos/${_id(id)}/decide',
    body: {
      'decision': publish ? 'approve' : 'reject',
      'theme': ?theme?.wire,
      'min_age_band': ?minAgeBand?.wire,
      'reason': reason,
    },
  );

  /// Up to 10 recent approvals not audited yet, drawn anew on each read.
  Future<List<AuditCandidate>> auditSample() async => [
    for (final c
        in (await _json('GET', '/v1/moderation/audit-sample'))['videos']
            as List<dynamic>)
      AuditCandidate.fromJson(c as Map<String, dynamic>),
  ];

  /// Records the audit of a published round: [agree], or a disagreement
  /// with its [reason] that holds the video when [hold]. Needs a
  /// re-authentication within 5 minutes; a second audit answers
  /// `already_audited`.
  Future<void> auditApproval({
    required String videoId,
    required int round,
    required bool agree,
    String? reason,
    bool hold = false,
  }) => _client.send(
    'POST',
    '/v1/moderation/audits',
    body: {
      'video_id': videoId,
      'round': round,
      'verdict': agree ? 'agree' : 'disagree',
      'reason': ?reason,
      if (hold) 'hold': true,
    },
  );
}
