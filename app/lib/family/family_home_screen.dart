import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/check_email_screen.dart' show resentNotice;
import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/staff_root_screen.dart';
import 'family.dart';
import 'family_model.dart';
import 'inicio.dart';
import 'labels.dart';
import 'profile_fields.dart' show SelectableRow;
import 'widgets.dart';

const _inviteHelp =
    'O convite chega por e-\u2060mail, enviado por quem cuida da família. Abra o '
    'link da mensagem: ele abre o app e mostra a família para você entrar.';

/// `/`: Início once the family is ready (the greeting, then the children,
/// each one tap from being handed the device), or what comes before it
/// (no family yet, the email to confirm, the first read). Before the
/// family, a role holder's "Equipe" door follows the first use, since
/// staff need no family, then "Sua conta", since an account exists
/// before a family does, and "Sair da conta" stays at the foot; once the
/// family is ready the navigation holds those places.
class FamilyHomeScreen extends StatefulWidget {
  const FamilyHomeScreen({super.key});

  /// How long a family just started stays on the home, the sun rising,
  /// before its first run opens.
  static const riseThenPath = PeekingHead.riseDuration;

  @override
  State<FamilyHomeScreen> createState() => _FamilyHomeScreenState();
}

class _FamilyHomeScreenState extends State<FamilyHomeScreen> {
  final _create = Submission();
  final _accept = Submission();
  final _resend = Submission();
  final _signOut = Submission();
  late final FamilyModel _model;
  bool _started = false;
  bool _rise = false;
  bool _resent = false;
  bool _inviteExplained = false;

  /// Opens the first run once the sun has risen on a family just started.
  Timer? _toFirstRun;

  /// The invitation chosen among several; with one, that one.
  String? _chosen;

  /// Why the guardian was sent here, taken once from the model.
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    _rise = services.justLinked || _model.takeRise();
    services.justLinked = false;
    _notice = _model.takeNotice();
    _model.addListener(_takeNotice);
    // Back from confirming the email elsewhere, or reinstated meanwhile,
    // the account is read again. The read
    // starts after this build: it notifies the router.
    scheduleMicrotask(
      _model.state is EmailUnverified || _model.suspended
          ? _model.refresh
          : _model.load,
    );
  }

  /// A notice raised while the home shows (a read finding the family
  /// gone) shows here too.
  void _takeNotice() {
    if (_model.takeNotice() case final notice?) {
      setState(() => _notice = notice);
    }
  }

  @override
  void dispose() {
    _toFirstRun?.cancel();
    _model.removeListener(_takeNotice);
    _create.dispose();
    _accept.dispose();
    _resend.dispose();
    _signOut.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _create.run(
      _model.create,
      handle: (e) => e.code == 'email_unverified',
    );
    if (ok && mounted) {
      setState(() {
        _rise = true;
        _notice = null;
      });
      // A family started here goes on to its first child, PIN and
      // hand-over; one joined by invitation shares a family already set
      // up, and stays on the home. Without motion there is no sun to wait
      // for.
      final still = MediaQuery.of(context).disableAnimations;
      _toFirstRun = Timer(
        still ? Duration.zero : FamilyHomeScreen.riseThenPath,
        () {
          // Only if the guardian is still here, not gone elsewhere.
          if (mounted && (ModalRoute.isCurrentOf(context) ?? true)) {
            context.go(Routes.firstRun);
          }
        },
      );
    }
  }

  /// Joins the family of invitation [id].
  /// A refusal leaves its words; the model has already read the list
  /// again, so a gone invitation leaves the rows.
  Future<void> _join(String id) async {
    final ok = await _accept.run(
      () => _model.acceptById(id),
      overrides: const {'limit_reached': Copy.invitationFamilyFull},
      handle: (e) => e.code == 'email_unverified',
    );
    if (ok && mounted) {
      setState(() {
        _rise = _model.takeRise();
        _notice = null;
      });
    }
  }

  Future<void> _resendLink(String email) async {
    final ok = await _resend.run(
      () => AppScope.of(context).auth.resendVerification(email),
    );
    if (ok) setState(() => _resent = true);
  }

  /// `signOut` forgets the local session even when the server cannot be
  /// reached, and the router then leaves this screen.
  Future<void> _leave() =>
      _signOut.run(() => AppScope.of(context).auth.signOut());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _create, _accept, _resend, _signOut]),
    builder: (context, _) {
      final state = _model.state;
      if (_model.suspended) return _suspended(state);
      if (state case FamilyReady(:final family)) {
        return LayoutBuilder(
          builder: (context, box) {
            // Beside the rail, the children stand two to a line once two
            // whole columns fit with the margins around them; until then
            // the home keeps the one column every screen shares.
            const pair = 2 * FieldSizes.columnMaxWidth + Space.xl;
            final paired =
                (ShellFrame.maybeOf(context)?.rail ?? false) &&
                box.maxWidth >= pair + 2 * Space.xxxl;
            return FieldLayout(
              title: greeting(clock.now()),
              rise: _rise,
              columnWidth: paired ? pair : FieldSizes.columnMaxWidth,
              children: [
                if (_notice case final notice?) ...[
                  Notice(notice),
                  const SizedBox(height: Space.lg),
                ],
                Inicio(family: family, columns: paired ? 2 : 1),
              ],
            );
          },
        );
      }
      return FieldLayout(
        title: switch (state) {
          EmailUnverified() => 'Confirme seu e-\u2060mail',
          NoFamily(:final invitations) when invitations.length == 1 =>
            'Você tem um\u00a0convite',
          NoFamily(:final invitations) when invitations.length > 1 =>
            'Você tem ${invitations.length}\u00a0convites',
          _ => 'Sua família',
        },
        rise: _rise,
        children: [
          if (_notice case final notice?) ...[
            Notice(notice),
            const SizedBox(height: Space.lg),
          ],
          ...switch (state) {
            FamilyReady() => const [],
            NoFamily(:final invitations) =>
              invitations.isEmpty ? _firstUse() : _invited(invitations),
            EmailUnverified(:final email) => _verify(email),
            FamilyLoading() || FamilyFailed() => familyPending(_model),
          },
          if (_stateDoors(state) case final doors when doors.isNotEmpty) ...[
            const SizedBox(height: Space.xxl),
            Doors(children: doors),
          ],
          const SizedBox(height: Space.xxl),
          ..._foot(state),
        ],
      );
    },
  );

  /// The suspended account's home: what
  /// happened, what still works and how to contest, then the two doors
  /// a suspended session reaches and signing out. With a family, one calm
  /// line says it keeps working; never the reason or the date. No other
  /// door is built, so nothing outside the allow-list is read.
  Widget _suspended(FamilyState state) {
    final body = Theme.of(context).textTheme.bodyLarge;
    final email = _model.email;
    return FieldLayout(
      title: 'Sua conta está suspensa',
      children: [
        ...switch (state) {
          FamilyLoading() || FamilyFailed() => familyPending(_model),
          _ => [
            Text(
              'Enquanto isso, você só consegue baixar seus dados, excluir a '
              'conta ou sair.',
              style: body,
            ),
            if (state is FamilyReady) ...[
              const SizedBox(height: Space.md),
              Text(
                'A família e os aparelhos das crianças continuam '
                'funcionando.',
                style: body,
              ),
            ],
            if (email != null) ...[
              const SizedBox(height: Space.md),
              Text(
                'Para contestar, responda ao e-⁠mail que enviamos para '
                '${addressBreaks(email)}.',
                semanticsLabel:
                    'Para contestar, responda ao e-⁠mail que enviamos '
                    'para $email.',
                style: body,
              ),
            ],
            const SizedBox(height: Space.xxl),
            Doors(
              children: [
                _mutedDoor(
                  'Seus dados',
                  'Baixar uma cópia',
                  Routes.accountData,
                ),
                DoorRow(
                  title: 'Excluir conta',
                  onTap: () => context.go(Routes.accountDelete),
                ),
              ],
            ),
          ],
        },
        const SizedBox(height: Space.xxl),
        QuietAction(
          label: 'Sair da conta',
          onPressed: _signOut.busy ? null : _leave,
        ),
      ],
    );
  }

  DoorRow _mutedDoor(String title, String line, String path) => DoorRow(
    title: title,
    semanticsLabel: '$title, $line',
    onTap: () => context.go(path),
    child: Text(
      line,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted),
    ),
  );

  /// The doors under a state before the family: with no family, the
  /// Equipe door, then "Sua conta". None while the first read runs.
  List<DoorRow> _stateDoors(FamilyState state) => switch (state) {
    NoFamily() => [
      ...staffDoors(context, _model.roles ?? const {}),
      ?_accountDoor(),
    ],
    EmailUnverified() || FamilyFailed() => [?_accountDoor()],
    FamilyReady() || FamilyLoading() => const [],
  };

  /// The account's own door, named by its email once read.
  DoorRow? _accountDoor() {
    final email = _model.email;
    if (email == null) return null;
    return DoorRow(
      title: 'Sua conta',
      semanticsLabel: 'Sua conta, $email',
      onTap: () => context.go(Routes.account),
      child: AddressText(
        email,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.muted),
      ),
    );
  }

  List<Widget> _firstUse() => [
    Text(
      'Comece a sua família para cadastrar as crianças e chamar os outros '
      'adultos que cuidam delas.',
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
    // A refused invitation's words stay when no invitation is left.
    if (_create.message ?? _accept.message case final message?) ...[
      ErrorNote(message),
      const SizedBox(height: Space.lg),
    ],
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
    if (_inviteExplained) ...[
      const SizedBox(height: Space.lg),
      const Notice(_inviteHelp),
    ],
  ];

  /// The first use when invitations wait for the account: who invited
  /// and until when, one "Entrar na família", and starting a family of
  /// one's own as a quiet way out.
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
      if (_accept.message ?? _create.message case final message?) ...[
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

  List<Widget> _verify(String email) {
    final text = Theme.of(context).textTheme;
    return [
      Text(
        'Para cadastrar as crianças e cuidar da sua família, confirme seu '
        'e-\u2060mail. Procure a mensagem que enviamos para',
        style: text.bodyLarge,
      ),
      const SizedBox(height: Space.xs),
      AddressText(email, style: text.titleMedium),
      const SizedBox(height: Space.xl),
      if (_resend.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_resent) ...[
        const Notice(resentNotice),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Reenviar e-\u2060mail',
        busy: _resend.busy,
        onPressed: _resend.blocked ? null : () => _resendLink(email),
      ),
    ];
  }

  /// The quiet way out, signing out.
  List<Widget> _foot(FamilyState state) {
    final p = context.palette;
    final email = _model.email;
    return [
      // The "Sua conta" door names the account; only the
      // first read, which has no door yet, names it here.
      if (email != null && state is FamilyLoading) ...[
        const SizedBox(height: Space.lg),
        Text(
          'Você entrou como ${addressBreaks(email)}',
          semanticsLabel: 'Você entrou como $email',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: p.muted),
        ),
      ],
      QuietAction(
        label: 'Sair da conta',
        onPressed: _signOut.busy ? null : _leave,
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
