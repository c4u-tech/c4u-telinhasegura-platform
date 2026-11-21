import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/check_email_screen.dart' show resentNotice;
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'family_model.dart';
import 'family_start.dart';
import 'inicio.dart';
import 'widgets.dart';

/// `/`: Início once the family is ready (the greeting, then the children,
/// each one tap from being handed the device), or what comes before it.
/// With no family yet it is Início still, inside the navigation: the
/// greeting, then the start of a family in the module the children will
/// take, or the invitations waiting; the navigation holds Equipe and the
/// account. With the email to confirm, or on the first read, the screen
/// stands alone: a role holder's "Equipe" door, then "Sua conta", since
/// an account exists before a family does, and "Sair da conta" at the
/// foot.
class FamilyHomeScreen extends StatefulWidget {
  const FamilyHomeScreen({super.key});

  /// How long a family just started stays on the home, the mascot
  /// winking, before its first run opens.
  static const winkThenPath = PerchedTevi.winkDuration;

  @override
  State<FamilyHomeScreen> createState() => _FamilyHomeScreenState();
}

class _FamilyHomeScreenState extends State<FamilyHomeScreen> {
  final _resend = Submission();
  final _signOut = Submission();
  late final FamilyModel _model;
  bool _started = false;
  bool _wink = false;
  bool _resent = false;

  /// Opens the first run once the mascot has winked at a family just
  /// started.
  Timer? _toFirstRun;

  /// Why the guardian was sent here, taken once from the model.
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    _wink = services.justLinked || _model.takeWink();
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
    _resend.dispose();
    _signOut.dispose();
    super.dispose();
  }

  /// The start of a family, kept across the invitations' changes.
  final _start = GlobalKey();

  /// An invitation accepted: the mascot winks at the family joined.
  void _joined() {
    if (!mounted) return;
    setState(() {
      _wink = _model.takeWink();
      _notice = null;
    });
  }

  /// A family just started: the mascot winks, then its first run opens.
  void _familyStarted() {
    if (!mounted) return;
    setState(() {
      _wink = true;
      _notice = null;
    });
    // A family started here goes on to its first child, PIN and
    // hand-over; one joined by invitation shares a family already set
    // up, and stays on the home. Without motion there is no wink to wait
    // for.
    final still = MediaQuery.of(context).disableAnimations;
    _toFirstRun = Timer(
      still ? Duration.zero : FamilyHomeScreen.winkThenPath,
      () {
        // Only if the guardian is still here, not gone elsewhere.
        if (mounted && (ModalRoute.isCurrentOf(context) ?? true)) {
          context.go(Routes.firstRun);
        }
      },
    );
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
    listenable: Listenable.merge([_model, _resend, _signOut]),
    builder: (context, _) {
      final state = _model.state;
      if (_model.suspended) return _suspended(state);
      if (state case FamilyReady(:final family)) {
        return LayoutBuilder(
          builder: (context, box) {
            final paired = _paired(context, box);
            return FieldLayout(
              title: greeting(clock.now()),
              wink: _wink,
              columnWidth: paired ? _pair : FieldSizes.columnMaxWidth,
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
      // Inside the navigation, which holds Equipe, the account and
      // signing out.
      // Still being read inside the navigation: Início's greeting over the
      // placeholder rows, so the page only fills in once the read answers.
      if (state is FamilyLoading && ShellFrame.maybeOf(context) != null) {
        return FieldLayout(
          title: greeting(clock.now()),
          wink: _wink,
          children: familyPending(_model),
        );
      }
      // Inside the navigation, which holds Equipe, the account and
      // signing out.
      if (state case NoFamily(:final invitations)) {
        return LayoutBuilder(
          builder: (context, box) {
            // Início's own arrangement: beside the rail the start stands
            // where the first child's card will, in the first of the two
            // columns. The invitations keep the one column.
            final paired = invitations.isEmpty && _paired(context, box);
            final start = FamilyStart(
              // Kept as the invitations come and go, with its words.
              key: _start,
              invitations: invitations,
              onStarted: _familyStarted,
              onJoined: _joined,
            );
            return FieldLayout(
              title: switch (invitations.length) {
                0 => greeting(clock.now()),
                1 => 'Você tem um\u00a0convite',
                final n => 'Você tem $n\u00a0convites',
              },
              wink: _wink,
              columnWidth: paired ? _pair : FieldSizes.columnMaxWidth,
              children: [
                if (_notice case final notice?) ...[
                  Notice(notice),
                  const SizedBox(height: Space.lg),
                ],
                if (paired)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: start),
                      const SizedBox(width: Space.xl),
                      const Spacer(),
                    ],
                  )
                else
                  start,
              ],
            );
          },
        );
      }
      return FieldLayout(
        title: switch (state) {
          EmailUnverified() => 'Confirme seu e-\u2060mail',
          _ => 'Sua família',
        },
        wink: _wink,
        children: [
          if (_notice case final notice?) ...[
            Notice(notice),
            const SizedBox(height: Space.lg),
          ],
          ...switch (state) {
            FamilyReady() || NoFamily() => const [],
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

  /// Two columns of the task's width with a gap between them.
  static const _pair = 2 * FieldSizes.columnMaxWidth + Space.xl;

  /// Beside the rail, the children stand two to a line once two whole
  /// columns fit with the margins around them; until then the home keeps
  /// the one column every screen shares.
  static bool _paired(BuildContext context, BoxConstraints box) =>
      (ShellFrame.maybeOf(context)?.rail ?? false) &&
      box.maxWidth >= _pair + 2 * Space.xxxl;

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

  /// The doors under a state the navigation does not frame: "Sua
  /// conta". None while the first read runs.
  List<DoorRow> _stateDoors(FamilyState state) => switch (state) {
    EmailUnverified() || FamilyFailed() => [?_accountDoor()],
    FamilyReady() || FamilyLoading() || NoFamily() => const [],
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
