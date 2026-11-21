import 'package:flutter/material.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/address.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/services.dart';
import 'family.dart';
import 'family_model.dart';
import 'inicio.dart' show ChildCard;
import 'labels.dart';
import 'profile_fields.dart' show SelectableRow;
import 'widgets.dart';

const _inviteHelp =
    'O convite chega por e-⁠mail, enviado por quem cuida da família. Abra o '
    'link da mensagem: ele abre o app e mostra a família para você entrar.';

/// What an account with no family yet is offered, the same on Início and
/// on Família, so neither hides an invitation:
///
/// - with no invitation, the start of a family in the home's module (a
///   child's card), so it stands where the children will: what a family
///   is for, the room it has (children and adults, hollow), "Começar
///   minha família" and "Tenho um convite";
/// - with [invitations] waiting, who invited and until when, one "Entrar
///   na família", and starting a family of one's own as a quiet way out.
///
/// [onStarted] runs once a family was started here, [onJoined] once an
/// invitation was accepted.
class FamilyStart extends StatefulWidget {
  const FamilyStart({
    super.key,
    required this.invitations,
    required this.onStarted,
    this.onJoined,
  });

  final List<ReceivedInvitation> invitations;
  final VoidCallback onStarted;
  final VoidCallback? onJoined;

  @override
  State<FamilyStart> createState() => _FamilyStartState();
}

class _FamilyStartState extends State<FamilyStart> {
  final _create = Submission();
  final _accept = Submission();
  bool _inviteExplained = false;

  /// The invitation chosen among several; with one, that one.
  String? _chosen;

  @override
  void dispose() {
    _create.dispose();
    _accept.dispose();
    super.dispose();
  }

  FamilyModel get _model => AppScope.of(context).familyModel;

  Future<void> _start() async {
    final ok = await _create.run(
      _model.create,
      handle: (e) => e.code == 'email_unverified',
    );
    // The family read in its place may already have taken this widget
    // away: the screen around it still hears.
    if (ok) widget.onStarted();
  }

  /// Joins the family of invitation [id]. A refusal leaves its words; the
  /// model has already read the list again, so a gone invitation leaves
  /// the rows.
  Future<void> _join(String id) async {
    final ok = await _accept.run(
      () => _model.acceptById(id),
      overrides: const {'limit_reached': Copy.invitationFamilyFull},
      handle: (e) => e.code == 'email_unverified',
    );
    if (ok) widget.onJoined?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_create, _accept]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.invitations.isEmpty
          ? _plain()
          : _invited(widget.invitations),
    ),
  );

  /// The last refusal's words, whichever way it came: a refused
  /// invitation's stay when no invitation is left.
  String? get _message => _accept.message ?? _create.message;

  List<Widget> _plain() => [
    // Over the module, as the home sets a failed hand-over over the
    // children.
    if (_message case final message?) ...[
      ErrorNote(message),
      const SizedBox(height: Space.lg),
    ],
    ChildCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Comece a sua família para cadastrar as crianças e chamar '
              'os outros adultos que cuidam delas.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: Space.lg),
            const CapacityRow(
              filled: 0,
              total: kMaxMinors,
              words: FamilyWords.childrenRoom,
            ),
            const SizedBox(height: Space.md),
            const CapacityRow(
              filled: 0,
              total: kMaxAdults,
              words: FamilyWords.adultsRoom,
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Começar minha família',
              busy: _create.busy,
              onPressed: _create.blocked ? null : _start,
            ),
            const SizedBox(height: Space.md),
            OutlinedButton(
              onPressed: () => setState(() => _inviteExplained = true),
              child: const Text('Tenho um convite'),
            ),
          ],
        ),
      ),
    ),
    if (_inviteExplained) ...[
      const SizedBox(height: Space.lg),
      const Notice(_inviteHelp),
    ],
  ];

  List<Widget> _invited(List<ReceivedInvitation> invitations) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final single = invitations.length == 1;
    // A chosen invitation that is gone is no longer chosen.
    final chosen = single
        ? invitations.single.id
        : invitations.any((i) => i.id == _chosen)
        ? _chosen
        : null;
    final busy = _accept.busy || _create.busy;
    String who(ReceivedInvitation i) =>
        i.inviterEmail.isEmpty ? 'Uma família' : i.inviterEmail;
    String detail(ReceivedInvitation i) =>
        'convidou você · ${FamilyWords.expiry(i.expiresAt, now)}';
    return [
      Text(
        'Entre para cuidar das crianças junto com quem convidou você.',
        style: text.bodyLarge,
      ),
      const SizedBox(height: Space.xl),
      if (single)
        Doors(
          children: [
            _InvitedRow(
              who: who(invitations.single),
              detail: detail(invitations.single),
            ),
          ],
        )
      else
        for (final (n, invitation) in invitations.indexed) ...[
          if (n > 0) const SizedBox(height: Space.sm),
          SelectableRow(
            label:
                'Convite de ${invitation.inviterEmail.isEmpty ? 'uma família' : invitation.inviterEmail}, '
                '${FamilyWords.expiry(invitation.expiresAt, now)}',
            text: addressBreaks(who(invitation)),
            detail: detail(invitation),
            selected: invitation.id == chosen,
            onTap: busy ? null : () => setState(() => _chosen = invitation.id),
          ),
        ],
      const SizedBox(height: Space.xl),
      if (_message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Entrar na família',
        busy: _accept.busy,
        onPressed: chosen == null || _accept.blocked || _create.busy
            ? null
            : () => _join(chosen),
      ),
      if (!single)
        SubmitHint(
          'Escolha um convite acima.',
          visible: chosen == null,
          reserve: true,
        ),
      const SizedBox(height: Space.xxl),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Prefere começar a sua?',
            style: text.bodyLarge?.copyWith(color: context.palette.muted),
          ),
          const SizedBox(width: Space.xs),
          QuietAction(
            label: 'Começar minha família',
            busy: _create.busy,
            inline: true,
            onPressed: busy || _create.blocked ? null : _start,
          ),
        ],
      ),
    ];
  }
}

/// The one invitation waiting: who invited and until when, read as one
/// line by assistive technology. "Entrar na família" acts on it.
class _InvitedRow extends StatelessWidget {
  const _InvitedRow({required this.who, required this.detail});

  final String who;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AddressText(who, style: text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              detail,
              style: text.bodyMedium?.copyWith(color: context.palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
