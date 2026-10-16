import '../account/sessions_screen.dart' show clientName;
import '../auth/auth_api.dart' show PlatformRole;
import '../curation/team_words.dart';
import '../curation/words.dart';
import 'accounts.dart';

/// PT-BR words for the account directory:
/// the numbers, an account's sheet, and the staff audit
/// log's rows. The event
/// words are the app's own, never the wire value; an event the app does
/// not know reads [otherEvent].
abstract final class AccountWords {
  /// An event the table does not name.
  static const otherEvent = 'Outra ação da equipe';

  static const _events = {
    'account_looked_up': 'Conta buscada',
    'account_sessions_revoked': 'Sessões encerradas',
    'account_device_unlinked': 'Aparelho desvinculado',
    'account_password_reset_sent': 'Redefinição de senha enviada',
    'curator_appointed': 'Nomeação para a curadoria',
    'curator_updated': 'Mudança na curadoria',
    'curator_removed': 'Saída da curadoria',
    'moderator_appointed': 'Nomeação para a moderação',
    'moderator_removed': 'Saída da moderação',
    'video_removed': 'Vídeo removido de vez',
    'video_reopened': 'Vídeo reaberto para revisão',
    'pack_removed': 'Pacotinho removido de vez',
    'admin_granted': 'Administração concedida',
    'admin_revoked': 'Administração retirada',
    'mfa_reset': 'Verificação em duas etapas redefinida',
    'account_suspended': 'Conta suspensa',
    'account_reinstated': 'Conta reativada',
  };

  /// A count with "." thousands ("1.240"), or "menos de 5" for a count
  /// the server suppressed below [suppressedBelow].
  static String figure(int? n, {required int suppressedBelow}) {
    if (n == null) return 'menos de $suppressedBelow';
    final digits = n.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      groups.insert(0, digits.substring(end < 3 ? 0 : end - 3, end));
    }
    return '${n < 0 ? '-' : ''}${groups.join('.')}';
  }

  /// The muted line under the numbers.
  static String suppression(int below) =>
      'Números abaixo de $below aparecem como “menos de $below”.';

  /// A local day and time: "3 de março, 14:20", the year only when it is
  /// not [now]'s.
  static String moment(DateTime at, DateTime now, {bool year = false}) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${CurationWords.date(local, now, always: year)}, '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// "Suspensa desde 8 de outubro de 2026, 14:20": local, always with
  /// the year.
  static String suspendedSince(DateTime at) =>
      'Suspensa desde ${moment(at, at, year: true)}';

  /// An event in words.
  static String event(String event) => _events[event] ?? otherEvent;

  /// What the action was about: "sobre p•••@g•••.com", "sobre uma conta
  /// apagada", "sobre um vídeo", "sobre um pacotinho"; a lookup that
  /// found nobody, "nenhuma conta encontrada". Null with no subject. The
  /// masked address goes through [address] (break marks to show, plain to
  /// read).
  static String? subject(
    AuditAction a, {
    String Function(String) address = _plain,
  }) => switch (a.subjectKind) {
    'account' => switch (a.subjectEmailMasked) {
      final email? => 'sobre ${address(email)}',
      null => 'sobre uma conta apagada',
    },
    'video' => 'sobre um vídeo',
    'pack' => 'sobre um pacotinho',
    _ when a.metadata['match'] == 'none' => 'nenhuma conta encontrada',
    _ => null,
  };

  /// From the metadata only how a lookup searched ("por e-mail", "por
  /// código") and how many sessions ended ("3 sessões").
  static List<String> details(AuditAction a) {
    final sessions = int.tryParse(a.metadata['sessions'] ?? '');
    return [
      switch (a.metadata['by']) {
        'email' => 'por e-\u2060mail',
        'id' => 'por código',
        _ => null,
      },
      ?switch (sessions) {
        null => null,
        1 => '1 sessão',
        final n => '$n sessões',
      },
    ].nonNulls.toList();
  }

  /// Who did it, under which role, when: "ana@example.com · Administração
  /// · 3 de março, 14:20"; "conta apagada" for an erased actor, a role the
  /// app does not know left out. The address goes through [address].
  static String actor(
    AuditAction a,
    DateTime now, {
    String Function(String) address = _plain,
  }) {
    final role = PlatformRole.values.where((r) => r.name == a.actorRole);
    return CurationWords.joined([
      switch (a.actorEmail) {
        final email? => address(email),
        null => 'conta apagada',
      },
      for (final r in role) TeamWords.area(r),
      moment(a.occurredAt, now),
    ]);
  }

  /// The reason in quotes, null when none was kept.
  static String? reason(AuditAction a) {
    final r = a.reason?.trim() ?? '';
    return r.isEmpty ? null : '“$r”';
  }

  static const _providers = {
    'password': 'Senha',
    'google': 'Google',
    'apple': 'Apple',
  };

  /// How the account signs in, in the order held: "Entra com Senha ·
  /// Google". A way the app does not know is left out; null with none.
  static String? providers(List<String> held) {
    final known = [for (final p in held) ?_providers[p]];
    return known.isEmpty ? null : 'Entra com ${CurationWords.joined(known)}';
  }

  /// "Conta criada em 3 de março de 2026", always with the year.
  static String created(DateTime at) =>
      'Conta criada em ${CurationWords.date(at, at, always: true)}';

  /// The account's place in its family: `owner` "Responsável principal",
  /// anything else "Responsável".
  static String familyRole(String role) =>
      role == 'owner' ? 'Responsável principal' : 'Responsável';

  /// The family's counts, never a name: "2 crianças · 1 aparelho ativo".
  static String familyCounts(SheetFamily f) => CurationWords.joined([
    f.minors == 1 ? '1 criança' : '${f.minors} crianças',
    f.devices == 1 ? '1 aparelho ativo' : '${f.devices} aparelhos ativos',
  ]);

  /// A family device's link: "Vinculado em 3 de março, 14:20".
  static String linked(DateTime at, DateTime now) =>
      'Vinculado em ${moment(at, now)}';

  /// A family device's last sight, in calendar days: "Visto há 2 dias".
  static String seen(DateTime at, DateTime now) =>
      'Visto ${CurationWords.ago(at, now)}';

  /// A session's client as "Aparelhos conectados" names it.
  static String client(String client) => clientName(client);

  /// When a session began: "entrou em 3 de março".
  static String started(DateTime at, DateTime now) =>
      'entrou em ${CurationWords.date(at, now)}';

  static String _plain(String address) => address;
}
