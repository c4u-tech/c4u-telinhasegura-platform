import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'widgets.dart';

const _joining =
    'Ao entrar, você vê as crianças da família e cuida dos perfis delas '
    'junto com os outros adultos.';

/// The invitation problems that end this screen's task, each with its
/// copy for the invited adult.
const _ends = {
  'invalid_token': Copy.invitationGone,
  'invitation_email_mismatch': null,
  'already_in_family': null,
  'limit_reached': Copy.invitationFamilyFull,
};

/// `/convite?token=`, the emailed link, signed in (a signed-out visitor comes back here after signing in):
/// looks the invitation
/// up once, shows who invited and whom, and joins with "Entrar na
/// família". An invalid token says nothing beyond its copy.
class AcceptInvitationScreen extends StatefulWidget {
  const AcceptInvitationScreen({super.key, required this.token});

  final String? token;

  @override
  State<AcceptInvitationScreen> createState() => _AcceptInvitationState();
}

class _AcceptInvitationState extends State<AcceptInvitationScreen> {
  final _signOut = Submission();
  late final FamilyModel _model;
  late final FamilyWrite _lookup;
  late final FamilyWrite _accept;
  bool _started = false;
  InvitationPreview? _preview;

  /// The lookup reached no answer (network, 5xx, a rate limit).
  bool _unanswered = false;

  /// The problem that ended the task, by code.
  String? _ended;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    // The token is in the URL now; memory lets it go. This
    // screen takes over from a link that just went through: the home
    // must not replay its rise later.
    services.heldInvitation = null;
    services.justLinked = false;
    _model = services.familyModel;
    Future<bool> confirm() => confirmItsYou(context);
    _lookup = FamilyWrite(family: _model, confirm: confirm);
    _accept = FamilyWrite(family: _model, confirm: confirm);
    _open(widget.token);
  }

  /// Another link opened while this screen shows: start over with it.
  @override
  void didUpdateWidget(AcceptInvitationScreen old) {
    super.didUpdateWidget(old);
    if (widget.token == old.token) return;
    _preview = null;
    _unanswered = false;
    _ended = null;
    _open(widget.token);
  }

  void _open(String? token) {
    if (token != null && token.isNotEmpty) {
      scheduleMicrotask(() => _find(token));
    } else {
      _ended = 'invalid_token';
    }
  }

  @override
  void dispose() {
    _signOut.dispose();
    _lookup.dispose();
    _accept.dispose();
    super.dispose();
  }

  bool _end(ApiError e) {
    if (!_ends.containsKey(e.code)) return false;
    _ended = e.code;
    if (mounted) setState(() {});
    return true;
  }

  /// `email_unverified` went to the model: the home shows the prompt.
  void _leaveIfUnverified() {
    if (mounted && _model.state is EmailUnverified) context.go(Routes.home);
  }

  Future<void> _find(String token) async {
    final api = AppScope.of(context).family;
    InvitationPreview? preview;
    final ok = await _lookup.write(
      () async => preview = await api.lookupInvitation(token),
      // A newer link replaced this one while it was looked up: its
      // answer, problem or not, is no longer this screen's.
      handle: (e) => token != widget.token || _end(e),
    );
    if (!mounted || token != widget.token) return;
    setState(() {
      _preview = preview;
      _unanswered = !ok && _ended == null;
    });
    if (!ok) _leaveIfUnverified();
  }

  Future<void> _join(String token) async {
    final api = AppScope.of(context).family;
    Family? family;
    final ok = await _accept.write(
      () async => family = await api.acceptInvitation(token),
      handle: _end,
    );
    if (!ok) return _leaveIfUnverified();
    _model.joined(family!);
    if (mounted) context.go(Routes.home);
  }

  /// Signs out with the token still in the URL: the router holds it and
  /// brings it back after the next sign-in.
  Future<void> _switchAccount() =>
      _signOut.run(() => AppScope.of(context).auth.signOut());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_lookup, _accept, _signOut]),
    builder: (context, _) => FieldLayout(
      title: 'Convite',
      onBack: () => context.go(Routes.home),
      children: switch ((_ended, _preview)) {
        (final code?, _) => _problem(code),
        (null, final preview?) => _invitation(preview),
        _ when _unanswered => _retry(),
        _ => const [FamilyPlaceholder(label: 'Carregando o convite')],
      },
    ),
  );

  List<Widget> _invitation(InvitationPreview preview) {
    final text = Theme.of(context).textTheme;
    final token = widget.token!;
    return [
      Text(
        '${addressBreaks(preview.inviterEmail)} convidou você para a família.',
        semanticsLabel: '${preview.inviterEmail} convidou você para a família.',
        style: text.bodyLarge,
      ),
      const SizedBox(height: Space.md),
      Text('O convite foi enviado para', style: text.bodyLarge),
      const SizedBox(height: Space.xs),
      AddressText(preview.invitedEmail, style: text.titleMedium),
      const SizedBox(height: Space.md),
      Text(_joining, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      if (_accept.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Entrar na família',
        busy: _accept.busy,
        onPressed: _accept.blocked ? null : () => _join(token),
      ),
    ];
  }

  /// A lookup that did not reach an answer: network, 5xx or a rate limit.
  List<Widget> _retry() => [
    if (_lookup.message case final message?) ...[
      ErrorNote(message),
      const SizedBox(height: Space.lg),
    ],
    PrimaryButton(
      label: 'Tentar de novo',
      busy: _lookup.busy,
      onPressed: _lookup.blocked ? null : () => _find(widget.token!),
    ),
  ];

  List<Widget> _problem(String code) {
    final words =
        _ends[code] ?? Copy.forError(ApiError(status: 400, code: code));
    return [
      ErrorNote(words),
      const SizedBox(height: Space.lg),
      switch (code) {
        'invitation_email_mismatch' => QuietAction(
          label: 'Sair e entrar com outro e-\u2060mail',
          busy: _signOut.busy,
          onPressed: _switchAccount,
        ),
        'already_in_family' => QuietAction(
          label: 'Ir para sua família',
          onPressed: () => context.go(Routes.home),
        ),
        _ => QuietAction(
          label: 'Ir para o início',
          onPressed: () => context.go(Routes.home),
        ),
      },
    ];
  }
}
