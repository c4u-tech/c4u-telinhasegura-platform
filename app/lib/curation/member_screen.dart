import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import '../staff/staff.dart';
import 'appoint_screen.dart' show selfAppointment;
import 'curation.dart';
import 'curator_form.dart';
import 'role_gate.dart';
import 'team_words.dart';
import 'words.dart';

/// Under "Salvar alterações" while nothing changed.
const unchangedHint = 'Mude o papel acima para salvar.';

/// Under the administration, which this app never changes.
const cliOnly = 'Muda só pela linha de comando';

/// On the caller's own sheet.
const ownRoles = selfAppointment;

/// Back on the team when the member is no longer there (`not_found`).
const memberGone = 'Essa pessoa não está mais na equipe.';

/// The sheet again after a save, with [email] as shown or read
/// and [role] inline.
String saved(String email, String role, {bool verified = false}) => verified
    ? '$email agora revisa como $role, com a formação verificada.'
    : '$email agora revisa como $role.';

/// The sheet again after a role goes, another left: [area] is
/// "curadoria" or "moderação".
String leftArea(String email, String area) => '$email saiu da $area.';

/// Back on the team after the last role goes.
String leftTeam(String email) => '$email saiu da equipe.';

String _plain(String address) => address;

/// What "Salvar alterações" sends: a new displayed role, the
/// affirmation, or both.
typedef _Changes = ({DisplayRole? role, bool? verified});

/// `/admin/equipe/:accountId`, titled by the member's email: one section
/// per role held, each with since when. The curation shows the six
/// displayed roles and the affirmation, "Salvar alterações" (only on a
/// change) and the clay quiet "Tirar da curadoria"; the moderation the
/// clay quiet "Tirar da moderação"; the administration is read-only. A
/// curation or moderation the member lacks is a door into the appoint
/// form, filled in. Every write confirms with "Motivo" and goes through
/// [ReauthWrite]. On the caller's own sheet the roles are read-only,
/// with no write and no door. There is no
/// read of one member: the team is read and theirs found.
class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key, required this.id});

  final String id;

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  late final ReauthWrite _write;
  bool _started = false;
  bool _failed = false;

  /// The member as read, or as the last write answered.
  StaffMember? _member;

  /// Whether [_member] is the caller, who changes none of their roles.
  bool _own = false;
  DisplayRole? _role;
  bool _verified = false;
  TeamNotice? _notice;

  /// The role whose removal runs, whose action shows the progress.
  PlatformRole? _revoking;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    final scope = AppScope.of(context);
    try {
      // The session's roles, for the guard, and its account, to tell the
      // caller's own sheet apart.
      await scope.familyModel.load();
      final all = await scope.staff.staff();
      if (!mounted) return;
      final member = all.where((m) => m.accountId == widget.id).firstOrNull;
      if (member == null) return _leave((_) => memberGone);
      _own = member.accountId == scope.familyModel.accountId;
      setState(() => _take(member));
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  StaffRole? _held(StaffMember m, PlatformRole role) =>
      m.roles.where((r) => r.role == role).firstOrNull;

  void _take(StaffMember m) {
    _member = m;
    final curator = _held(m, PlatformRole.curator);
    // A role the app does not know is no choice, and never sent back.
    final role = curator?.displayRole;
    _role = role == DisplayRole.unknown ? null : role;
    _verified = curator?.verifiedProfessional ?? false;
  }

  void _leave(TeamNotice notice) => context.go(Routes.team, extra: notice);

  /// Takes a write's [e]: a lost role goes home; a member already gone,
  /// back to the team.
  bool _handle(ApiError e) {
    if (takeLostRole(context, e)) return true;
    if (e.code != 'not_found') return false;
    _leave((_) => memberGone);
    return true;
  }

  /// What "Salvar alterações" would send; null while nothing changed or
  /// a professional role waits on its affirmation.
  _Changes? _changes(StaffRole c) {
    final role = _role;
    if (role == null) return null;
    if (role.professional && !_verified) return null;
    final wasVerified = c.verifiedProfessional ?? false;
    final newRole = role != c.displayRole;
    final affirmed = role.professional && (newRole || !wasVerified);
    if (!newRole && !affirmed) return null;
    return (role: newRole ? role : null, verified: affirmed ? true : null);
  }

  Future<void> _save(StaffMember m, _Changes c) async {
    final api = AppScope.of(context).staff;
    final role = c.role;
    String title(String Function(String) set) =>
        'Mudar o papel de ${set(m.email)} na curadoria?';
    final body = [
      if (role != null)
        'Nas revisões, essa pessoa passa a aparecer como ${role.inline}.',
      if (c.verified ?? false)
        'A formação dessa pessoa fica marcada como verificada.',
    ];
    final reason = await confirmWithReason(
      context,
      title: title(addressBreaks),
      titleSemanticsLabel: title(_plain),
      body: body,
      action: 'Salvar alterações',
    );
    if (reason == null || !mounted) return;
    StaffMember? after;
    final ok = await _write.write(
      () async => after = await api.updateCurator(
        m.accountId,
        displayRole: role,
        verifiedProfessional: c.verified,
        reason: reason,
      ),
      handle: _handle,
    );
    final member = after;
    if (!ok || member == null || !mounted) return;
    final curator = _held(member, PlatformRole.curator);
    final shown = curator?.displayRole ?? DisplayRole.unknown;
    final verified =
        shown.professional && (curator?.verifiedProfessional ?? false);
    setState(() {
      _take(member);
      _notice = (set) =>
          saved(set(member.email), shown.inline, verified: verified);
    });
  }

  Future<void> _revoke(StaffMember m, PlatformRole role) async {
    final api = AppScope.of(context).staff;
    final email = m.email;
    final area = role == PlatformRole.curator ? 'curadoria' : 'moderação';
    String title(String Function(String) set) =>
        'Tirar ${set(email)} da $area?';
    List<String> body(String Function(String) set) =>
        role == PlatformRole.curator
        ? [
            '${set(email)} deixa de revisar vídeos. As aprovações dessa '
                'pessoa nas rodadas em aberto deixam de contar.',
            'As revisões que essa pessoa já fez continuam no histórico dos '
                'vídeos.',
          ]
        : ['${set(email)} deixa de remover e reabrir vídeos retidos.'];
    final reason = await confirmWithReason(
      context,
      title: title(addressBreaks),
      titleSemanticsLabel: title(_plain),
      body: body(addressBreaks),
      bodySemanticsLabels: body(_plain),
      action: 'Tirar da $area',
    );
    if (reason == null || !mounted) return;
    setState(() => _revoking = role);
    StaffMember? after;
    final ok = await _write.write(
      () async => after = await api.revoke(m.accountId, role, reason: reason),
      handle: _handle,
    );
    if (!mounted) return;
    setState(() => _revoking = null);
    final member = after;
    if (!ok || member == null) return;
    if (member.roles.isEmpty) return _leave((set) => leftTeam(set(email)));
    setState(() {
      _take(member);
      _notice = (set) => leftArea(set(email), area);
    });
  }

  void _pickRole(StaffRole c, DisplayRole role) {
    _write.clearMessage();
    setState(() {
      if (role == _role) return;
      _role = role;
      // A professional role is affirmed with the save that gives it; the
      // role as it stands keeps its affirmation.
      _verified = role == c.displayRole && (c.verifiedProfessional ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final email = _member?.email;
    return ListenableBuilder(
      listenable: _write,
      builder: (context, _) => FieldLayout(
        title: email == null ? 'Equipe' : addressBreaks(email),
        titleSemanticsLabel: email,
        // Opened over an account's sheet, back to it as it was.
        onBack: () =>
            context.canPop() ? context.pop() : context.go(Routes.team),
        children: _body(),
      ),
    );
  }

  List<Widget> _body() {
    final member = _member;
    if (member == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando essa pessoa')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    final curator = _held(member, PlatformRole.curator);
    final moderator = _held(member, PlatformRole.moderator);
    final admin = _held(member, PlatformRole.admin);
    final lacking = [
      if (curator == null) PlatformRole.curator,
      if (moderator == null) PlatformRole.moderator,
    ];
    return [
      if (_notice case final notice?) ...[
        Notice(notice(addressBreaks), semanticsLabel: notice(_plain)),
        const SizedBox(height: Space.xl),
      ],
      if (_own) ...[
        Text(ownRoles, style: text.bodyLarge),
        const SizedBox(height: Space.xl),
      ],
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.xl),
      ],
      if (curator != null)
        ..._section(curator, _curator(member, curator), first: true),
      if (moderator != null)
        ..._section(moderator, first: curator == null, [
          if (!_own)
            QuietAction(
              label: 'Tirar da moderação',
              destructive: true,
              busy: _write.busy && _revoking == PlatformRole.moderator,
              onPressed: _write.blocked
                  ? null
                  : () => _revoke(member, PlatformRole.moderator),
            ),
        ]),
      if (admin != null)
        ..._section(admin, first: curator == null && moderator == null, [
          Text(
            cliOnly,
            style: text.bodyMedium?.copyWith(color: context.palette.muted),
          ),
        ]),
      if (!_own && lacking.isNotEmpty) ...[
        const SizedBox(height: Space.xxl),
        Doors(
          children: [
            for (final role in lacking)
              DoorRow(
                title: role == PlatformRole.curator
                    ? 'Nomear para a curadoria'
                    : 'Nomear para a moderação',
                onTap: () => context.go(Routes.appointFor(member.email, role)),
              ),
          ],
        ),
      ],
    ];
  }

  /// A role's section as the held video's: a heading in title-medium,
  /// since when muted between hairlines, then [content]; a whole xxl
  /// above it unless it is the [first].
  List<Widget> _section(
    StaffRole role,
    List<Widget> content, {
    required bool first,
  }) {
    final text = Theme.of(context).textTheme;
    return [
      if (!first) const SizedBox(height: Space.xxl),
      Semantics(
        header: true,
        child: Text(TeamWords.area(role.role), style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      Doors(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Text(
              TeamWords.since(role.grantedAt, clock.now()),
              style: text.bodyMedium?.copyWith(color: context.palette.muted),
            ),
          ),
        ],
      ),
      if (content.isNotEmpty) ...[const SizedBox(height: Space.lg), ...content],
    ];
  }

  List<Widget> _curator(StaffMember m, StaffRole c) {
    if (_own) {
      final marks = TeamWords.curatorMarks(c);
      return [
        if (marks.isNotEmpty)
          Text(marks.join(', '), style: Theme.of(context).textTheme.bodyLarge),
      ];
    }
    final idle = !_write.blocked;
    final changes = _changes(c);
    final role = _role;
    return [
      CuratorRoleFields(
        heading: 'Papel na curadoria',
        subordinate: true,
        role: role,
        verified: _verified,
        onRole: idle ? (r) => _pickRole(c, r) : null,
        onVerified: idle ? (v) => setState(() => _verified = v) : null,
      ),
      const SizedBox(height: Space.xl),
      PrimaryButton(
        label: 'Salvar alterações',
        busy: _write.busy && _revoking == null,
        onPressed: changes != null && idle ? () => _save(m, changes) : null,
      ),
      SubmitHint(
        role == null
            ? chooseRoleHint
            : role.professional && !_verified
            ? affirmHint
            : unchangedHint,
        visible: changes == null,
        reserve: true,
      ),
      const SizedBox(height: Space.xxl),
      QuietAction(
        label: 'Tirar da curadoria',
        destructive: true,
        busy: _write.busy && _revoking == PlatformRole.curator,
        onPressed: idle ? () => _revoke(m, PlatformRole.curator) : null,
      ),
    ];
  }
}
