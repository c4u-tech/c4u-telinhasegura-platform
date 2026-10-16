import '../auth/auth_api.dart' show PlatformRole;
import '../staff/staff.dart';
import 'curation.dart';
import 'words.dart';

/// A calm line brought back to the team or its sheet, naming an address
/// through the given function: break marks to show, plain to read (the
/// Plain Address Rule).
typedef TeamNotice = String Function(String Function(String) address);

/// PT-BR words for the team: roles by their
/// area's name, the displayed role inclusive, never gendering the
/// member ("essa pessoa").
abstract final class TeamWords {
  /// A role's area: "Curadoria", "Moderação", "Administração".
  static String area(PlatformRole role) => switch (role) {
    PlatformRole.curator => 'Curadoria',
    PlatformRole.moderator => 'Moderação',
    PlatformRole.admin => 'Administração',
  };

  /// A curator's displayed role, and whether the training was verified:
  /// "Pedagogo(a), formação verificada". Empty for a role the app does
  /// not know, not verified.
  static List<String> curatorMarks(StaffRole r) => [
    if (r.displayRole case final d? when d != DisplayRole.unknown) d.label,
    if (r.verifiedProfessional ?? false) 'formação verificada',
  ];

  /// One role in words, never nesting parentheses: "Curadoria:
  /// Pedagogo(a), formação verificada", "Moderação", "Administração".
  static String role(StaffRole r) {
    final marks = r.role == PlatformRole.curator ? curatorMarks(r) : const [];
    final name = area(r.role);
    return marks.isEmpty ? name : '$name: ${marks.join(', ')}';
  }

  /// A member's roles in words, in the order the server gave them.
  static List<String> roles(StaffMember m) => [
    for (final r in m.roles) role(r),
  ];

  /// A member as assistive technology reads their row: the email, then
  /// the roles apart by semicolons, since a role's own words hold commas:
  /// "bia@example.com, Curadoria: Pedagogo(a), formação verificada;
  /// Moderação".
  static String member(StaffMember m) =>
      [m.email, if (m.roles.isNotEmpty) roles(m).join('; ')].join(', ');

  /// The admin's door: "1 pessoa", "5 pessoas".
  static String people(int n) => n == 1 ? '1 pessoa' : '$n pessoas';

  /// Under a role's heading: "Desde 3 de março".
  static String since(DateTime at, DateTime now) =>
      'Desde ${CurationWords.date(at, now)}';
}
