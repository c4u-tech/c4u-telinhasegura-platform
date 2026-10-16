import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../auth/auth_api.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'account_write.dart';

/// What assistive technology hears while the sessions load.
const loadingSessions = 'Carregando os aparelhos conectados';

/// What marks the session of the device in hand.
const thisDevice = 'este aparelho';

/// The calm line after "Encerrar" ended a session.
const sessionEnded = 'Pronto. Esse aparelho saiu da sua conta.';

/// The primary while other devices are signed in.
const othersAction = 'Sair dos outros aparelhos';

/// The calm line after the others were signed out.
const othersEnded = 'Pronto. Sua conta saiu dos outros aparelhos.';

/// What the list says once no other device is signed in.
const onlyThisDevice = 'Só este aparelho está conectado.';

/// The quiet foot that signs every device out, this one too.
const allAction = 'Sair de todos os aparelhos';

/// A session's name: the label its sign-in sent, or, for a
/// session made before the app sent one, its client kind.
String sessionName(SessionSummary s) {
  final label = s.deviceLabel.trim();
  if (label.isNotEmpty) return label;
  return clientName(s.client);
}

/// A session's client kind in words: `mobile` "Celular ou tablet",
/// anything else "Navegador".
String clientName(String client) =>
    client == 'mobile' ? 'Celular ou tablet' : 'Navegador';

const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// When a session began, as its local day: "desde 1º de outubro", with
/// the year only when it is not [now]'s.
String sessionSince(DateTime createdAt, DateTime now) {
  final local = createdAt.toLocal();
  final day = local.day == 1 ? '1º' : '${local.day}';
  final year = local.year == now.toLocal().year ? '' : ' de ${local.year}';
  return 'desde $day de ${_months[local.month - 1]}$year';
}

/// When a session was last used, in calendar days on the device clock:
/// "último uso hoje", "ontem", "há 4 dias". A time ahead of
/// [now] still reads "hoje".
String sessionLastUse(DateTime seenAt, DateTime now) {
  final local = seenAt.toLocal();
  final here = now.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(here.year, here.month, here.day);
  // Rounded: a daylight-saving day is 23 or 25 hours long.
  final days = (today.difference(day).inHours / 24).round();
  return switch (days) {
    <= 0 => 'último uso hoje',
    1 => 'último uso ontem',
    _ => 'último uso há $days dias',
  };
}

/// The sessions as the screen lists them: this device's first, the
/// others by last use, the most recent first.
List<SessionSummary> sessionsInOrder(List<SessionSummary> sessions) => [
  ...sessions.where((s) => s.isCurrent),
  ...sessions.where((s) => !s.isCurrent).toList()
    ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt)),
];

/// `/conta/aparelhos`: the devices signed in to the guardian's account,
/// as the server lists its sessions.
/// They are "aparelhos conectados", never the child's linked
/// devices, which live under Modo criança.
///
/// The blocked MFA challenge pushes it over itself with [onBack], so
/// coming back finds the challenge as it was.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, this.onBack});

  /// Where the back goes; `/conta` by default.
  final VoidCallback? onBack;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late final AccountWrite _end;
  late final AccountWrite _others;
  late final AccountWrite _all;
  bool _started = false;
  List<SessionSummary>? _sessions;
  bool _failed = false;

  /// The session "Encerrar" is ending, whose row shows the progress.
  String? _pending;

  /// The calm line after a write.
  String? _done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    AccountWrite write() => AccountWrite(
      confirm: () => confirmItsYou(context),
      signOut: services.client.forgetSession,
    );
    _end = write();
    _others = write();
    _all = write();
    _read();
  }

  @override
  void dispose() {
    for (final write in _writes) {
      write.dispose();
    }
    super.dispose();
  }

  List<AccountWrite> get _writes => [_end, _others, _all];

  bool get _blocked => _writes.any((w) => w.blocked);

  /// Ends another device's session at once: signing in again undoes it.
  Future<void> _endSession(SessionSummary session) async {
    final auth = AppScope.of(context).auth;
    setState(() {
      _pending = session.id;
      _done = null;
    });
    var gone = false;
    final ok = await _end.write(
      () => auth.revokeSession(session.id),
      handle: (e) => gone = e.code == 'not_found',
    );
    if (gone) await _read(quiet: true);
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (ok) {
        _sessions = [
          for (final s in _sessions ?? const <SessionSummary>[])
            if (s.id != session.id) s,
        ];
        _done = sessionEnded;
      }
      if (gone) _done = Copy.sessionGone;
    });
  }

  /// A [quiet] read keeps the list until the answer replaces it.
  Future<void> _read({bool quiet = false}) async {
    final services = AppScope.of(context);
    if (!quiet) {
      setState(() {
        _sessions = null;
        _failed = false;
      });
    }
    try {
      final sessions = await services.auth.listSessions();
      if (mounted) setState(() => _sessions = sessionsInOrder(sessions));
    } on Object catch (e) {
      // Signed out elsewhere: the router lands on the entry.
      if (e is ApiError && e.code == 'unauthenticated') {
        unawaited(services.client.forgetSession());
        return;
      }
      if (mounted && !quiet) setState(() => _failed = true);
    }
  }

  /// Signs every other device out, then shows what is left.
  Future<void> _endOthers() async {
    final auth = AppScope.of(context).auth;
    setState(() => _done = null);
    final ok = await _others.write(
      () => auth.revokeSessions(includeCurrent: false),
    );
    if (!ok) return;
    await _read(quiet: true);
    if (mounted) setState(() => _done = othersEnded);
  }

  /// Signs every device out, this one included, once the guardian
  /// confirms; the router then lands on the entry screen.
  Future<void> _endAll() async {
    final auth = AppScope.of(context).auth;
    final confirmed = await confirmDestructive(
      context,
      title: 'Sair de todos os aparelhos?',
      body: const [
        'Sua conta sai de todos os aparelhos conectados, inclusive este. '
            'Você volta para a entrada.',
        'Para usar de novo, entre na sua conta em cada aparelho.',
      ],
      action: allAction,
    );
    if (!confirmed || !mounted) return;
    setState(() => _done = null);
    await _all.write(() => auth.revokeSessions(includeCurrent: true));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(_writes),
    builder: (context, _) => FieldLayout(
      title: 'Aparelhos conectados',
      onBack: widget.onBack ?? () => context.go(Routes.account),
      children: switch (_sessions) {
        final sessions? => _list(sessions),
        null when _failed => [
          const ErrorNote(Copy.genericRetry),
          const SizedBox(height: Space.lg),
          PrimaryButton(label: 'Tentar de novo', onPressed: _read),
        ],
        null => const [FamilyPlaceholder(label: loadingSessions)],
      },
    ),
  );

  List<Widget> _list(List<SessionSummary> sessions) {
    final now = clock.now();
    final message = _writes.map((w) => w.message).nonNulls.firstOrNull;
    return [
      if (message != null) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_done case final done?) ...[
        Notice(done),
        const SizedBox(height: Space.lg),
      ],
      Doors(
        children: [
          for (final session in sessions)
            SessionRow(
              label: sessionName(session),
              current: session.isCurrent,
              since: sessionSince(session.createdAt, now),
              lastUse: sessionLastUse(session.lastSeenAt, now),
              busy: _end.busy && _pending == session.id,
              onEnd: session.isCurrent || _blocked
                  ? null
                  : () => _endSession(session),
            ),
        ],
      ),
      const SizedBox(height: Space.xl),
      if (sessions.any((s) => !s.isCurrent))
        PrimaryButton(
          label: othersAction,
          busy: _others.busy,
          onPressed: _blocked ? null : _endOthers,
        )
      else
        Text(onlyThisDevice, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: Space.xxl),
      QuietAction(
        label: allAction,
        destructive: true,
        busy: _all.busy,
        onPressed: _blocked ? null : _endAll,
      ),
    ];
  }
}

/// One session, in a door row's rhythm but without a chevron: nobody
/// navigates into it. A screen module leads it, filled for this device
/// and hollow for the others, then its [label], "este aparelho" when
/// [current], and its dates. Assistive technology reads them as one.
/// Another device's row ends with a quiet "Encerrar" ([onEnd]).
class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.label,
    required this.current,
    required this.since,
    required this.lastUse,
    this.onEnd,
    this.busy = false,
  });

  final String label;
  final bool current;
  final String since;
  final String lastUse;
  final VoidCallback? onEnd;
  final bool busy;

  /// The module's height: its width (58:33) sits in the avatar's 40 dp
  /// column of the family rows.
  static const moduleHeight = 22.0;
  static const _lead = moduleHeight * 58 / 33 + Space.lg;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final words = [label, if (current) thisDevice, since, lastUse];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: EdgeInsets.only(
          top: Space.lg,
          bottom: current ? Space.lg : Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: words.join(', '),
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      // Centred on the title's first line.
                      padding: const EdgeInsets.only(top: 2),
                      child: StateModule(filled: current, height: moduleHeight),
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: text.titleMedium),
                          if (current) ...[
                            const SizedBox(height: Space.xs),
                            Text(thisDevice, style: text.labelLarge),
                          ],
                          const SizedBox(height: Space.xs),
                          Text(since, style: muted),
                          Text(lastUse, style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!current) ...[
              const SizedBox(height: Space.xs),
              Padding(
                // Under the text, past the module.
                padding: const EdgeInsetsDirectional.only(start: _lead),
                child: QuietAction(
                  label: 'Encerrar',
                  busy: busy,
                  onPressed: onEnd,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
