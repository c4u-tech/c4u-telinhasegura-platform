import '../auth/auth_api.dart' show PlatformRole;
import '../curation/curation.dart' show DisplayRole;

/// One platform role a team member holds (Member). The
/// displayed role and the verified flag are a curator's only.
class StaffRole {
  const StaffRole({
    required this.role,
    required this.grantedAt,
    this.displayRole,
    this.verifiedProfessional,
  });

  /// The role in [j], or null for a role this app does not know yet.
  static StaffRole? fromJson(Map<String, dynamic> j) {
    final known = PlatformRole.parseAll([j['role']]);
    if (known.isEmpty) return null;
    return StaffRole(
      role: known.single,
      grantedAt: DateTime.parse(j['granted_at'] as String),
      displayRole: j['display_role'] == null
          ? null
          : DisplayRole.parse(j['display_role']),
      verifiedProfessional: j['verified_professional'] as bool?,
    );
  }

  final PlatformRole role;
  final DateTime grantedAt;
  final DisplayRole? displayRole;
  final bool? verifiedProfessional;
}

/// An account holding platform roles, as the team lists it.
class StaffMember {
  const StaffMember({
    required this.accountId,
    required this.email,
    required this.roles,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    accountId: j['account_id'] as String,
    email: j['email'] as String,
    roles: [
      for (final r in j['roles'] as List<dynamic>)
        ?StaffRole.fromJson(r as Map<String, dynamic>),
    ],
  );

  final String accountId;
  final String email;

  /// By name; empty once the last role is revoked.
  final List<StaffRole> roles;
}
