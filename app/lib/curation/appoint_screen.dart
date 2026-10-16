import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../family/profile_fields.dart' show SelectableRow;
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import '../staff/staff.dart';
import 'curation.dart';
import 'curator_form.dart';
import 'role_gate.dart';
import 'words.dart';

/// An address that is not one (`validation`), and the hint while the
/// field holds none.
const emailInvalid = 'Digite um e-⁠mail válido.';

/// `account_not_found`.
const noAccount =
    'Não há conta com esse e-⁠mail. A pessoa precisa criar a conta '
    'antes.';

/// `email_unverified`: the person's, not the admin's.
const accountUnverified =
    'Essa pessoa ainda não confirmou o e-⁠mail da conta. Peça que ela '
    'confirme e tente de novo.';

/// `already_has_role`, for the role asked.
const alreadyCurator = 'Essa pessoa já faz parte da curadoria.';
const alreadyModerator = 'Essa pessoa já faz parte da moderação.';

/// `self_appointment`, as the caller's own sheet says it.
const selfAppointment = 'Você não muda os seus próprios papéis.';

/// `account_suspended`: reinstated first.
const accountSuspended =
    'Essa conta está suspensa. Reative a conta antes de nomear.';

/// Under each "Papel" choice.
const curatorDetail = 'Revisa vídeos e monta pacotinhos';
const moderatorDetail =
    'Remove ou reabre vídeos retidos; não vê a equipe nem as contas';

/// The done state, with [email] as shown or read.
String joined(String email) => '$email agora faz parte da equipe.';

/// Whether [email], trimmed, reads as an address: something on each side
/// of one "@", no spaces. The server decides the rest (`validation`).
bool looksLikeEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(email.trim());

String _plain(String address) => address;

/// The two roles an admin gives here, in display order: admin is the
/// server command's alone.
const _papeis = [PlatformRole.curator, PlatformRole.moderator];

/// `/admin/equipe/nova` "Nomear alguém": the person's email and "Papel",
/// "Curadoria" or "Moderação"; the curation also asks one of the six
/// displayed roles and, for a professional one, the affirmation that the
/// training was verified. "Continuar" waits on all of it, then confirms
/// full screen with "Motivo" and grants through [ReauthWrite]; the
/// account's refusals (a suspended one's too)
/// are worded on the email field, the entries kept; then the done state
/// back to the team. Opened from a member's sheet,
/// [email] and [role] come filled in.
class AppointScreen extends StatefulWidget {
  const AppointScreen({super.key, this.email, this.role});

  final String? email;
  final PlatformRole? role;

  /// `papel` as `Routes.appointFor` writes it; null for anything else.
  static PlatformRole? parsePapel(String? papel) => switch (papel) {
    'curadoria' => PlatformRole.curator,
    'moderacao' => PlatformRole.moderator,
    _ => null,
  };

  @override
  State<AppointScreen> createState() => _AppointScreenState();
}

class _AppointScreenState extends State<AppointScreen> {
  late final _email = TextEditingController(text: widget.email);
  late final ReauthWrite _write;
  bool _started = false;
  late PlatformRole? _papel = widget.role;
  DisplayRole? _role;
  bool _verified = false;
  String? _emailError;
  StaffMember? _done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    _email.addListener(() => setState(() => _emailError = null));
  }

  @override
  void dispose() {
    _email.dispose();
    _write.dispose();
    super.dispose();
  }

  bool get _curator => _papel == PlatformRole.curator;

  /// Why "Continuar" waits, or null once it may go.
  String? get _waiting {
    if (!looksLikeEmail(_email.text)) return emailInvalid;
    if (_papel == null) return chooseRoleHint;
    if (!_curator) return null;
    final role = _role;
    if (role == null) return chooseRoleHint;
    if (role.professional && !_verified) return affirmHint;
    return null;
  }

  Future<void> _submit(PlatformRole papel) async {
    final email = _email.text.trim();
    final role = _curator ? _role : null;
    final reason = await _confirm(email, papel, role);
    if (reason == null || !mounted) return;
    final api = AppScope.of(context).staff;
    StaffMember? member;
    final ok = await _write.write(
      () async => member = await api.grant(
        email: email,
        role: papel,
        displayRole: role,
        verifiedProfessional: role == null
            ? null
            : role.professional && _verified,
        reason: reason,
      ),
      handle: (e) => takeLostRole(context, e) || _onField(e, papel),
    );
    if (ok && mounted) setState(() => _done = member);
  }

  /// The confirmation with "Motivo"; the reason, or null when cancelled.
  Future<String?> _confirm(String email, PlatformRole papel, DisplayRole? r) {
    final area = papel == PlatformRole.curator ? 'curadoria' : 'moderação';
    String title(String Function(String) set) =>
        'Nomear ${set(email)} para a $area?';
    List<String> body(String Function(String) set) => r == null
        ? [
            '${set(email)} passa a remover ou reabrir vídeos retidos, sempre '
                'com um motivo. Essa pessoa não vê a equipe nem as contas.',
          ]
        : [
            '${set(email)} passa a revisar vídeos e montar pacotinhos. Nas '
                'revisões, essa pessoa aparece como ${r.inline}.',
          ];
    return confirmWithReason(
      context,
      title: title(addressBreaks),
      titleSemanticsLabel: title(_plain),
      body: body(addressBreaks),
      bodySemanticsLabels: body(_plain),
      action: 'Nomear',
    );
  }

  bool _onField(ApiError e, PlatformRole papel) {
    final words = switch (e.code) {
      'account_not_found' => noAccount,
      'email_unverified' => accountUnverified,
      'already_has_role' =>
        papel == PlatformRole.curator ? alreadyCurator : alreadyModerator,
      'self_appointment' => selfAppointment,
      'validation' => emailInvalid,
      'account_suspended' => accountSuspended,
      _ => null,
    };
    if (words == null) return false;
    setState(() => _emailError = words);
    return true;
  }

  void _pickPapel(PlatformRole papel) {
    _write.clearMessage();
    setState(() => _papel = papel);
  }

  void _pickRole(DisplayRole role) {
    _write.clearMessage();
    // The affirmation is for the role it was given with.
    setState(() {
      if (role != _role) _verified = false;
      _role = role;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) => FieldLayout(
      title: 'Nomear alguém',
      onBack: () => context.go(Routes.team),
      children: switch (_done) {
        final done? => [
          Notice(
            joined(addressBreaks(done.email)),
            semanticsLabel: joined(done.email),
          ),
          const SizedBox(height: Space.xl),
          PrimaryButton(
            label: 'Voltar para a equipe',
            onPressed: () => context.go(Routes.team),
          ),
        ],
        null => _form(),
      },
    ),
  );

  List<Widget> _form() {
    final idle = !_write.blocked;
    final papel = _papel;
    final waiting = _waiting;
    final text = Theme.of(context).textTheme;
    return [
      EmailField(controller: _email, errorText: _emailError),
      const SizedBox(height: Space.xl),
      Semantics(header: true, child: Text('Papel', style: text.titleMedium)),
      const SizedBox(height: Space.md),
      for (final (i, p) in _papeis.indexed) ...[
        if (i > 0) const SizedBox(height: Space.sm),
        SelectableRow(
          label: p == PlatformRole.curator ? 'Curadoria' : 'Moderação',
          detail: p == PlatformRole.curator ? curatorDetail : moderatorDetail,
          selected: p == papel,
          onTap: idle ? () => _pickPapel(p) : null,
        ),
      ],
      if (_curator) ...[
        const SizedBox(height: Space.xl),
        CuratorRoleFields(
          heading: 'Papel na curadoria',
          role: _role,
          verified: _verified,
          onRole: idle ? _pickRole : null,
          onVerified: idle ? (v) => setState(() => _verified = v) : null,
        ),
      ],
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Continuar',
        busy: _write.busy,
        onPressed: papel != null && waiting == null && idle
            ? () => _submit(papel)
            : null,
      ),
      SubmitHint(
        waiting ?? chooseRoleHint,
        visible: waiting != null,
        reserve: true,
      ),
    ];
  }
}
