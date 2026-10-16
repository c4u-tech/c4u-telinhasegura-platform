import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/family/family.dart';

import 'fixtures.dart';

void main() {
  test('an owner family parses with its invitations', () {
    final f = Family.fromJson(ownerFamily);
    expect((f.id, f.role, f.pendingInvitations), ('f1', FamilyRole.owner, 1));
    expect(f.members.map((m) => (m.accountId, m.role)), [
      ('a1', FamilyRole.owner),
      ('a2', FamilyRole.guardian),
    ]);
    final lia = f.minors.single;
    expect(
      (lia.nickname, lia.avatar, lia.ageBand),
      ('Lia', Avatar.fox, AgeBand.from5To8),
    );
    expect(lia.createdAt, DateTime.utc(2026, 10, 3, 12, 30));
    expect(f.invitations!.single.email, 'carla@example.com');
  });

  test('a guardian family has no invitations list', () {
    final f = Family.fromJson(
      {...ownerFamily, 'role': 'guardian'}..remove('invitations'),
    );
    expect(
      (f.role, f.invitations, f.pendingInvitations),
      (FamilyRole.guardian, null, 1),
    );
  });

  test('unknown wire values parse to unknown instead of throwing', () {
    expect(AgeBand.parse('13-17'), AgeBand.unknown);
    expect(Avatar.parse('dragon'), Avatar.unknown);
    expect(FamilyRole.parse('admin'), FamilyRole.unknown);
    expect(AgeBand.parse(''), AgeBand.unknown);
    expect(AgeBand.values.map((b) => b.wire), ['ate-4', '5-8', '9-12', '']);
  });

  test('the preview parses', () {
    final p = InvitationPreview.fromJson({
      'inviter_email': 'ana@example.com',
      'invited_email': 'bia@example.com',
      'expires_at': '2026-10-10T12:00:00Z',
    });
    expect(
      (p.inviterEmail, p.invitedEmail),
      ('ana@example.com', 'bia@example.com'),
    );
  });

  test('the consent version equals the backend constant', () {
    // The app must never record consent against unseen text.
    final source = File('../backend/internal/family/family.go')
        .readAsStringSync();
    final match = RegExp(r'ConsentPolicyVersion = "([^"]+)"')
        .firstMatch(source);
    expect(match?.group(1), kConsentPolicyVersion);
  });

  test('the family limits equal the backend constants', () {
    final source = File('../backend/internal/family/family.go')
        .readAsStringSync();
    int? limit(String name) => int.tryParse(
      RegExp('$name += (\\d+)').firstMatch(source)?.group(1) ?? '',
    );
    expect(limit('maxMinors'), kMaxMinors);
    expect(limit('maxSeats'), kMaxAdults);
  });

  test('the avatar keys equal the backend list, in order', () {
    final source = File('../backend/internal/family/family.go')
        .readAsStringSync();
    final list = RegExp(r'var Avatars = \[\]string\{([^}]*)\}')
        .firstMatch(source)
        ?.group(1);
    final goKeys = RegExp(r'"([^"]+)"')
        .allMatches(list ?? '')
        .map((m) => m.group(1))
        .toList();
    expect(goKeys, isNotEmpty);
    expect(
      Avatar.values.where((a) => a != Avatar.unknown).map((a) => a.wire),
      goKeys,
    );
  });
}
