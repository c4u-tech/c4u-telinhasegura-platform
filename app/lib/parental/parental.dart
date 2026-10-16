import '../family/family.dart';

/// A child as kid mode shows it: no dates, no consent.
class Profile {
  const Profile({
    required this.id,
    required this.nickname,
    required this.avatar,
    required this.ageBand,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    nickname: j['nickname'] as String,
    avatar: Avatar.parse(j['avatar']),
    ageBand: AgeBand.parse(j['age_band']),
  );

  final String id;
  final String nickname;
  final Avatar avatar;
  final AgeBand ageBand;
}

/// A 10-minute, single-use code that links a child's device, shown
/// `XXXX-XXXX` and as a QR.
class LinkCode {
  const LinkCode({
    required this.code,
    required this.minorId,
    required this.expiresAt,
  });

  factory LinkCode.fromJson(Map<String, dynamic> j) => LinkCode(
    code: j['code'] as String,
    minorId: j['minor_id'] as String,
    expiresAt: DateTime.parse(j['expires_at'] as String),
  );

  final String code;
  final String minorId;
  final DateTime expiresAt;
}

/// A child's linked device as the guardian area lists it.
class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.label,
    required this.minorId,
    required this.linkedAt,
    required this.lastSeenAt,
  });

  factory LinkedDevice.fromJson(Map<String, dynamic> j) => LinkedDevice(
    id: j['id'] as String,
    label: j['label'] as String,
    minorId: j['minor_id'] as String,
    linkedAt: DateTime.parse(j['linked_at'] as String),
    lastSeenAt: DateTime.parse(j['last_seen_at'] as String),
  );

  final String id;
  final String label;
  final String minorId;
  final DateTime linkedAt;
  final DateTime lastSeenAt;
}
