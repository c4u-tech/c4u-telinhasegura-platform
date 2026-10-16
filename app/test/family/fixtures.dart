const ownerFamily = {
  'id': 'f1',
  'role': 'owner',
  'members': [
    {
      'account_id': 'a1',
      'email': 'ana@example.com',
      'role': 'owner',
      'joined_at': '2026-10-03T12:00:00Z',
    },
    {
      'account_id': 'a2',
      'email': 'bia@example.com',
      'role': 'guardian',
      'joined_at': '2026-10-03T13:00:00Z',
    },
  ],
  'minors': [
    {
      'id': 'm1',
      'nickname': 'Lia',
      'avatar': 'fox',
      'age_band': '5-8',
      'created_at': '2026-10-03T12:30:00Z',
      'updated_at': '2026-10-03T12:30:00Z',
    },
  ],
  'pending_invitations': 1,
  'invitations': [
    {
      'id': 'i1',
      'email': 'carla@example.com',
      'expires_at': '2026-10-10T12:00:00Z',
    },
  ],
};

/// A child as the API answers it.
Map<String, Object?> minorJson(
  String id,
  String nickname, {
  String avatar = 'fox',
  String ageBand = '5-8',
}) => {
  'id': id,
  'nickname': nickname,
  'avatar': avatar,
  'age_band': ageBand,
  'created_at': '2026-10-03T12:30:00Z',
  'updated_at': '2026-10-03T12:30:00Z',
};

/// The owner's family holding [minors] instead.
Map<String, Object?> familyWith(List<Map<String, Object?>> minors) => {
  ...ownerFamily,
  'minors': minors,
};

/// One item of `GET /v1/invitations`.
const receivedInvitation = {
  'id': 'i1',
  'inviter_email': 'carla@example.com',
  'expires_at': '2026-10-10T12:00:00Z',
};
