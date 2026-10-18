/// The consent text version the app shows before a minor is created. It
/// must equal the backend's `family.ConsentPolicyVersion` (a test pins
/// both).
const kConsentPolicyVersion = '2026-10-17';

/// The family's limits, as the backend enforces them (`maxMinors` and
/// `maxSeats` in backend/internal/family): children, and adults counting
/// members plus pending invitations.
const kMaxMinors = 10;
const kMaxAdults = 6;

enum FamilyRole {
  owner,
  guardian,
  unknown;

  static FamilyRole parse(Object? wire) => values.firstWhere(
    (r) => r != unknown && r.name == wire,
    orElse: () => unknown,
  );
}

/// The YouTube Kids tiers. [unknown] only ever comes from [parse]; never
/// send it.
enum AgeBand {
  upTo4('ate-4'),
  from5To8('5-8'),
  from9To12('9-12'),
  unknown('');

  const AgeBand(this.wire);

  final String wire;

  static AgeBand parse(Object? wire) => values.firstWhere(
    (b) => b != unknown && b.wire == wire,
    orElse: () => unknown,
  );
}

/// The preset avatar keys; the family screens map each key to its art.
/// [unknown] only ever comes from [parse]; never send it.
enum Avatar {
  fox,
  owl,
  cat,
  dog,
  rabbit,
  bear,
  turtle,
  whale,
  lion,
  panda,
  frog,
  penguin,
  unknown;

  String get wire => name;

  static Avatar parse(Object? wire) => values.firstWhere(
    (a) => a != unknown && a.name == wire,
    orElse: () => unknown,
  );
}

class Member {
  const Member({
    required this.accountId,
    required this.email,
    required this.role,
    required this.joinedAt,
  });

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    accountId: j['account_id'] as String,
    email: j['email'] as String,
    role: FamilyRole.parse(j['role']),
    joinedAt: DateTime.parse(j['joined_at'] as String),
  );

  final String accountId;
  final String email;
  final FamilyRole role;
  final DateTime joinedAt;
}

class Minor {
  const Minor({
    required this.id,
    required this.nickname,
    required this.avatar,
    required this.ageBand,
    required this.createdAt,
    required this.updatedAt,
    this.consentCurrent = true,
  });

  factory Minor.fromJson(Map<String, dynamic> j) => Minor(
    id: j['id'] as String,
    nickname: j['nickname'] as String,
    avatar: Avatar.parse(j['avatar']),
    ageBand: AgeBand.parse(j['age_band']),
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
    // An answer without the flag counts as current: an older API never
    // pauses a child by mistake.
    consentCurrent: j['consent_current'] as bool? ?? true,
  );

  final String id;
  final String nickname;
  final Avatar avatar;
  final AgeBand ageBand;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The guardian authorized the profile under the current consent text;
  /// until then, kid mode is paused for this child.
  final bool consentCurrent;
}

class PendingInvitation {
  const PendingInvitation({
    required this.id,
    required this.email,
    required this.expiresAt,
  });

  factory PendingInvitation.fromJson(Map<String, dynamic> j) =>
      PendingInvitation(
        id: j['id'] as String,
        email: j['email'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );

  final String id;
  final String email;
  final DateTime expiresAt;
}

/// The caller's view of their family: [role] is the caller's own.
class Family {
  const Family({
    required this.id,
    required this.role,
    required this.members,
    required this.minors,
    required this.pendingInvitations,
    required this.invitations,
  });

  factory Family.fromJson(Map<String, dynamic> j) {
    final invitations = j['invitations'] as List<dynamic>?;
    return Family(
      id: j['id'] as String,
      role: FamilyRole.parse(j['role']),
      members: [
        for (final m
            in (j['members'] as List<dynamic>).cast<Map<String, dynamic>>())
          Member.fromJson(m),
      ],
      minors: [
        for (final m
            in (j['minors'] as List<dynamic>).cast<Map<String, dynamic>>())
          Minor.fromJson(m),
      ],
      pendingInvitations: j['pending_invitations'] as int,
      invitations: invitations == null
          ? null
          : [
              for (final i in invitations.cast<Map<String, dynamic>>())
                PendingInvitation.fromJson(i),
            ],
    );
  }

  final String id;
  final FamilyRole role;
  final List<Member> members;
  final List<Minor> minors;
  final int pendingInvitations;

  /// The pending invitations themselves; only the owner receives them.
  final List<PendingInvitation>? invitations;
}

class InvitationPreview {
  const InvitationPreview({
    required this.inviterEmail,
    required this.invitedEmail,
    required this.expiresAt,
  });

  factory InvitationPreview.fromJson(Map<String, dynamic> j) =>
      InvitationPreview(
        inviterEmail: j['inviter_email'] as String,
        invitedEmail: j['invited_email'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );

  final String inviterEmail;
  final String invitedEmail;
  final DateTime expiresAt;
}

/// A pending invitation to the signed-in account's own email, offered on
/// the first use.
class ReceivedInvitation {
  const ReceivedInvitation({
    required this.id,
    required this.inviterEmail,
    required this.expiresAt,
  });

  factory ReceivedInvitation.fromJson(Map<String, dynamic> j) =>
      ReceivedInvitation(
        id: j['id'] as String,
        inviterEmail: j['inviter_email'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );

  final String id;

  /// Empty when the inviter's account no longer exists.
  final String inviterEmail;
  final DateTime expiresAt;
}
