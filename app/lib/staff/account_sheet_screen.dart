import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../account/sessions_screen.dart' show sessionLastUse;
import '../auth/api_error.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../curation/pack_parts.dart' show ReadLine;
import '../curation/team_words.dart';
import '../curation/words.dart' show CurationWords;
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'account_words.dart';
import '../curation/role_gate.dart';
import 'accounts.dart';
import 'audit_row.dart';
import 'challenge.dart';

/// On the caller's own sheet, in place of every support action.
const ownSheet = 'Suas sessões e aparelhos ficam em Sua conta.';

/// The sections' empty lines.
const noFamily = 'Sem família.';
const noDevices = 'Nenhum aparelho vinculado.';
const noSessions = 'Nenhuma sessão ativa.';
const noAccountActions = 'Nenhuma ação da equipe sobre esta conta.';

/// The sheet again after each action.
const resetSent = 'Redefinição de senha enviada.';
const deviceUnlinked = 'Aparelho desvinculado.';
const sessionsEnded = 'Sessões encerradas.';

/// Back on the search when the account is gone (`account_not_found`).
const accountGone = 'Essa conta não existe mais.';

/// On the sheet when the device already left (`device_not_found`).
const deviceGone = 'Esse aparelho já não está nessa família.';

/// On the sheet when the account's resets are spent for the hour (the reset's `rate_limited`),
/// in whole minutes; the number and "min"
/// never part across a line.
String resetsSpent(int minutes) =>
    'Já foram 3 redefinições nesta hora. Tente de novo em '
    '$minutes\u00A0min.';

/// The confirmations' titles and consequences.
String resetTitle(String email) =>
    'Enviar uma redefinição de senha para $email?';
const resetBody =
    'Chega um link válido por 30 minutos no e-\u2060mail da conta. A senha '
    'só muda se a pessoa usar o link.';
const unlinkTitle = 'Desvincular este aparelho?';
const unlinkBody =
    'Ele deixa de ser um aparelho da família e sai do modo criança na '
    'próxima vez que for usado. Para usar de novo, a família gera outro '
    'código.';
String sessionsTitle(int n) => n == 1
    ? 'Encerrar a sessão desta conta?'
    : 'Encerrar as $n sessões desta conta?';
const sessionsBody =
    'A pessoa sai da conta em todos os aparelhos e precisa entrar de novo. '
    'Os aparelhos vinculados das crianças continuam funcionando.';

/// The standing.
const accountActive = 'Conta ativa.';

/// At the foot, in place of "Suspender conta", while the account holds
/// the admin role.
const adminNotSuspended = 'Uma conta com administração não é suspensa.';

/// Under Situação after each act.
const accountSuspended = 'Conta suspensa.';
const accountReinstated = 'Conta reativada.';

/// The suspension's races and its one refusal, under the action that ran,
/// the sheet never read again.
const suspensionRefusals = {
  'already_suspended': 'Outra pessoa da equipe já suspendeu esta conta.',
  'not_suspended': 'Outra pessoa da equipe já reativou esta conta.',
  'subject_is_admin': 'Essa conta tem administração e não é suspensa.',
};

/// The suspension's and reinstatement's confirmations.
String suspendTitle(String email) => 'Suspender a conta $email?';
const suspendBody =
    'A pessoa sai de todos os aparelhos. Ao entrar de novo, só consegue '
    'baixar os dados, excluir a conta ou sair. A família e os aparelhos das '
    'crianças continuam funcionando.';
String suspendRoles(String roles) =>
    'Ela também sai da equipe ($roles). Reativar a conta não devolve esses '
    'papéis.';
const suspendTold = 'A pessoa recebe um e-\u2060mail avisando, sem o motivo.';
String reinstateTitle(String email) => 'Reativar a conta $email?';
const reinstateBody =
    'A pessoa volta a usar a Telinha Segura normalmente, nos aparelhos em '
    'que já estiver. Os papéis na equipe não voltam: para isso, nomeie de '
    'novo em Equipe. A pessoa recebe um e-\u2060mail avisando.';

String _plain(String address) => address;

/// A support action, by what it acts on.
sealed class _Action {
  const _Action();
}

final class _Reset extends _Action {
  const _Reset();
}

final class _Unlink extends _Action {
  const _Unlink(this.deviceId);

  final String deviceId;

  @override
  bool operator ==(Object other) =>
      other is _Unlink && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

final class _EndSessions extends _Action {
  const _EndSessions();
}

final class _Suspend extends _Action {
  const _Suspend();
}

final class _Reinstate extends _Action {
  const _Reinstate();
}

/// `/admin/contas/:accountId`, one account's sheet as the lookup answered
/// it, held in memory only:
/// the router opens it only with its [sheet]; without one it returns to
/// the search. Titled "Conta", the masked email under it, then the
/// sections Acesso, Família, Aparelhos (with a family), Sessões and
/// Ações da equipe, each a title-medium header over read lines between
/// hairlines, never a child's name, a device label or a session id.
/// A role is a door to the member's sheet. The support
/// actions sit beside what they act on: the reset under Acesso (ink),
/// "Desvincular" on each device and "Encerrar todas as sessões" under
/// Sessões (clay); each confirms full screen with its consequence and
/// "Motivo", then goes through [ReauthWrite] (re-authentication and the
/// second factor, the write sent again with the same reason), and its
/// answer replaces the sheet, its outcome (a notice, or why it did not
/// happen) shown under the action that ran. On the caller's
/// own account there are none.
///
/// The standing opens the sheet: "Situação" above Acesso, "Conta ativa."
/// or since when and why it is suspended, with the ink "Reativar conta";
/// the clay "Suspender conta" closes it, after the evidence, unless the
/// account holds the admin role. Either confirms its whole consequence,
/// and its notice lands under Situação; a race's refusal stays under the
/// action that ran, the sheet never read again.
class AccountSheetScreen extends StatefulWidget {
  const AccountSheetScreen({super.key, required this.sheet});

  final AccountSheet sheet;

  @override
  State<AccountSheetScreen> createState() => _AccountSheetScreenState();
}

class _AccountSheetScreenState extends State<AccountSheetScreen> {
  late final ReauthWrite _write;
  bool _started = false;

  /// The sheet as the lookup answered it, or as the last action did.
  late AccountSheet _sheet = widget.sheet;

  /// The last action run, under whose control its outcome shows.
  _Action? _acted;

  /// Where the last unlinked device stood, for its outcome once it left.
  int _unlinkedAt = 0;

  /// The calm line after [_acted].
  String? _notice;

  /// Why [_acted] was refused, besides the write's own message.
  String? _refusal;

  /// Where the outcome stands, to bring it into view.
  final _outcomeKey = GlobalKey();

  /// The action running, whose control shows the progress.
  _Action? _running;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    // The session's account, to tell the caller's own sheet apart.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  /// Takes an action's [e]: a lost role goes home; an account
  /// gone, back to the search; a device gone, the sheet with its notice.
  bool _handle(ApiError e) {
    if (takeLostRole(context, e)) return true;
    switch (e.code) {
      case 'account_not_found':
        context.go(Routes.accounts, extra: accountGone);
        return true;
      case 'device_not_found':
        // Gone already: dropped from the sheet as held, never read again
        // (a read is an audited lookup).
        if (_acted case _Unlink(:final deviceId)) _drop(deviceId);
        setState(() => _notice = deviceGone);
        return true;
    }
    return false;
  }

  /// The sheet without the device [id], the family's count of active
  /// devices one lower when it counted.
  void _drop(String id) {
    final s = _sheet;
    final gone = s.devices.where((d) => d.id == id);
    final f = s.family;
    if (gone.isEmpty) return;
    final counted =
        clock.now().difference(gone.first.lastSeenAt) <=
        const Duration(days: 180);
    _sheet = AccountSheet(
      accountId: s.accountId,
      emailMasked: s.emailMasked,
      emailVerified: s.emailVerified,
      createdAt: s.createdAt,
      providers: s.providers,
      roles: s.roles,
      mfaEnrolled: s.mfaEnrolled,
      suspension: s.suspension,
      family: f == null || !counted || f.devices == 0
          ? f
          : SheetFamily(role: f.role, minors: f.minors, devices: f.devices - 1),
      devices: [
        for (final d in s.devices)
          if (d.id != id) d,
      ],
      sessions: s.sessions,
      actions: s.actions,
    );
  }

  Future<void> _act(_Action action) async {
    final api = AppScope.of(context).accounts;
    final s = _sheet;
    final email = s.emailMasked;
    final (title, read, body, label, done) = switch (action) {
      _Suspend() => (
        suspendTitle(addressBreaks(email)),
        suspendTitle(_plain(email)),
        [
          suspendBody,
          if (s.roles.isNotEmpty) suspendRoles(_rolesInWords(s.roles)),
          suspendTold,
        ],
        'Suspender conta',
        accountSuspended,
      ),
      _Reinstate() => (
        reinstateTitle(addressBreaks(email)),
        reinstateTitle(_plain(email)),
        [reinstateBody],
        'Reativar conta',
        accountReinstated,
      ),
      _Reset() => (
        resetTitle(addressBreaks(email)),
        resetTitle(_plain(email)),
        [resetBody],
        'Enviar redefinição de senha',
        resetSent,
      ),
      _Unlink() => (
        unlinkTitle,
        unlinkTitle,
        [unlinkBody],
        'Desvincular',
        deviceUnlinked,
      ),
      _EndSessions() => (
        sessionsTitle(s.sessions.length),
        sessionsTitle(s.sessions.length),
        [sessionsBody],
        'Encerrar todas as sessões',
        sessionsEnded,
      ),
    };
    final reason = await confirmWithReason(
      context,
      title: title,
      titleSemanticsLabel: read,
      body: body,
      action: label,
    );
    if (reason == null || !mounted) return;
    _write.clearMessage();
    setState(() {
      _notice = null;
      _refusal = null;
      _acted = action;
      if (action case _Unlink(:final deviceId)) {
        _unlinkedAt = s.devices.indexWhere((d) => d.id == deviceId);
      }
      _running = action;
    });
    AccountSheet? after;
    Duration? spent;
    final ok = await _write.write(
      () async {
        try {
          after = await switch (action) {
            _Reset() => api.sendPasswordReset(s.accountId, reason: reason),
            _Unlink(:final deviceId) => api.unlinkDevice(
              s.accountId,
              deviceId,
              reason: reason,
            ),
            _EndSessions() => api.revokeSessions(s.accountId, reason: reason),
            _Suspend() => api.suspend(s.accountId, reason: reason),
            _Reinstate() => api.reinstate(s.accountId, reason: reason),
          };
        } on ApiError catch (e) {
          // The reset's hour is said on the sheet in minutes, not as the
          // form's countdown.
          if (action is! _Reset || e.code != 'rate_limited') rethrow;
          spent = e.retryAfter ?? const Duration(minutes: 1);
        }
      },
      overrides: suspensionRefusals,
      handle: _handle,
    );
    if (!mounted) return;
    setState(() {
      _running = null;
      if (spent case final wait?) {
        _refusal = resetsSpent((wait.inSeconds / 60).ceil());
      } else if (after case final sheet? when ok) {
        _sheet = sheet;
        _notice = done;
      }
    });
    _reveal();
  }

  /// [action]'s outcome, when it was the last run: its notice, or why it
  /// did not happen, 12 px (md) under its control. Without [notices] or
  /// [errors], that half is left to another place.
  List<Widget> _outcome(
    _Action action, {
    bool notices = true,
    bool errors = true,
  }) {
    if (_acted != action) return const [];
    final notice = notices ? _notice : null;
    final error = errors ? _refusal ?? _write.message : null;
    if (notice == null && error == null) return const [];
    return [
      Column(
        key: _outcomeKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice case final notice?) ...[
            const SizedBox(height: Space.md),
            Notice(notice),
          ],
          if (error case final error?) ...[
            const SizedBox(height: Space.md),
            ErrorNote(error),
          ],
        ],
      ),
    ];
  }

  /// [action]'s outcome as a row of its own in a [Doors] list, 12 px
  /// (md) clear of the hairline under it; none when it has no outcome.
  List<Widget> _outcomeRow(_Action action) {
    final outcome = _outcome(action);
    if (outcome.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: outcome,
        ),
      ),
    ];
  }

  /// Scrolls the outcome into view when it landed past an edge (a row
  /// gone above it, a control at the viewport's foot), without motion.
  /// A change of standing shows with its evidence: the sheet goes back to
  /// its top, where Situação sits, and only a notice still below the fold
  /// is pulled up to the viewport's foot.
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final at = _outcomeKey.currentContext;
    if (at == null || !at.mounted) return;
    if (_acted is _Suspend || _acted is _Reinstate) {
      Scrollable.of(at).position.jumpTo(0);
      Scrollable.ensureVisible(
        at,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      return;
    }
    for (final policy in [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      Scrollable.ensureVisible(at, alignmentPolicy: policy);
    }
  });

  /// Whether [action]'s control shows the progress.
  bool _busy(_Action action) => _write.busy && _running == action;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context).familyModel;
    return ListenableBuilder(
      listenable: Listenable.merge([model, _write]),
      builder: (context, _) {
        final mine = model.accountId == _sheet.accountId;
        return FieldLayout(
          title: 'Conta',
          onBack: () => context.go(Routes.accounts),
          // Until the session's account is read, no action is offered.
          children: _body(mine: mine, act: model.accountId != null && !mine),
        );
      },
    );
  }

  TextStyle? get _muted =>
      Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted);

  /// The sheet; [mine] says where the caller's own sessions live, and
  /// only with [act] are the support actions offered.
  List<Widget> _body({required bool mine, required bool act}) {
    final text = Theme.of(context).textTheme;
    final s = _sheet;
    final email = s.emailMasked;
    final now = clock.now();
    final family = s.family;
    final suspension = s.suspension;
    final idle = !_write.blocked;
    // Suspending is the sheet's last thing, after the evidence.
    final foot = act && suspension == null;
    // An unlinked device's outcome stays where the device stood.
    final unlinked = switch (_acted) {
      final _Unlink u when !s.devices.any((d) => d.id == u.deviceId) => u,
      _ => null,
    };
    return [
      Text(
        addressBreaks(email),
        semanticsLabel: email,
        style: text.titleMedium,
      ),
      if (mine) ...[
        const SizedBox(height: Space.lg),
        Text(ownSheet, style: text.bodyLarge),
      ],
      const SizedBox(height: Space.xxl),
      ..._section(
        'Situação',
        [
          if (suspension == null)
            Doors(
              children: [
                _lines([accountActive]),
              ],
            )
          else
            Doors(
              children: [
                _lines([
                  AccountWords.suspendedSince(suspension.since),
                  '“${suspension.reason.trim()}”',
                ]),
              ],
            ),
          // The suspension's notice under the standing it changed.
          ..._outcome(const _Suspend(), errors: false),
        ],
        actions: [
          if (act && suspension != null)
            QuietAction(
              label: 'Reativar conta',
              busy: _busy(const _Reinstate()),
              onPressed: idle ? () => _act(const _Reinstate()) : null,
            ),
          ..._outcome(const _Reinstate()),
        ],
      ),
      ..._section(
        'Acesso',
        [
          Doors(
            children: [
              _lines([
                s.emailVerified
                    ? 'E-\u2060mail confirmado'
                    : 'E-\u2060mail não confirmado',
                ?AccountWords.providers(s.providers),
                AccountWords.created(s.createdAt),
                s.mfaEnrolled
                    ? 'Verificação em duas etapas ativada'
                    : 'Verificação em duas etapas não ativada',
              ]),
              if (s.roles.isNotEmpty)
                DoorRow(
                  title: 'Na equipe',
                  semanticsLabel: 'Na equipe, ${_roles(s.roles)}',
                  child: Text(_roles(s.roles), style: _muted),
                  // Over the sheet, which lives only here.
                  onTap: () => context.push(Routes.member(s.accountId)),
                ),
            ],
          ),
        ],
        actions: [
          if (act)
            QuietAction(
              label: 'Enviar redefinição de senha',
              busy: _busy(const _Reset()),
              onPressed: idle ? () => _act(const _Reset()) : null,
            ),
          ..._outcome(const _Reset()),
        ],
      ),
      ..._section('Família', [
        if (family == null)
          Text(noFamily, style: text.bodyLarge)
        else
          Doors(
            children: [
              _lines([
                AccountWords.familyRole(family.role),
              ], muted: AccountWords.familyCounts(family)),
            ],
          ),
      ]),
      if (family != null)
        ..._section('Aparelhos', [
          if (s.devices.isEmpty)
            Text(noDevices, style: text.bodyLarge)
          else
            Doors(
              children: [
                for (final (i, d) in s.devices.indexed) ...[
                  // The unlinked device's outcome holds the row it left,
                  // between its own hairlines, so it never reads as the
                  // next device's state.
                  if (unlinked != null && i == _unlinkedAt)
                    ..._outcomeRow(unlinked),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _lines([
                        AccountWords.linked(d.linkedAt, now),
                      ], muted: AccountWords.seen(d.lastSeenAt, now)),
                      if (act)
                        QuietAction(
                          label: 'Desvincular',
                          semanticsLabel:
                              'Desvincular o aparelho vinculado em '
                              '${AccountWords.moment(d.linkedAt, now)}',
                          destructive: true,
                          busy: _busy(_Unlink(d.id)),
                          onPressed: idle ? () => _act(_Unlink(d.id)) : null,
                        ),
                      ..._outcome(_Unlink(d.id)),
                      if (act) const SizedBox(height: Space.sm),
                    ],
                  ),
                ],
                if (unlinked != null && _unlinkedAt >= s.devices.length)
                  ..._outcomeRow(unlinked),
              ],
            ),
          if (unlinked != null && s.devices.isEmpty) ..._outcome(unlinked),
        ]),
      ..._section(
        'Sessões',
        [
          if (s.sessions.isEmpty)
            Text(noSessions, style: text.bodyLarge)
          else
            Doors(
              children: [
                for (final session in s.sessions)
                  _lines([
                    AccountWords.client(session.client),
                    AccountWords.started(session.createdAt, now),
                  ], muted: sessionLastUse(session.lastSeenAt, now)),
              ],
            ),
        ],
        actions: [
          if (act && s.sessions.isNotEmpty)
            QuietAction(
              label: 'Encerrar todas as sessões',
              destructive: true,
              busy: _busy(const _EndSessions()),
              onPressed: idle ? () => _act(const _EndSessions()) : null,
            ),
          ..._outcome(const _EndSessions()),
        ],
      ),
      ..._section('Ações da equipe', [
        if (s.actions.isEmpty)
          Text(noAccountActions, style: text.bodyLarge)
        else
          Doors(children: [for (final a in s.actions) AuditActionRow(a)]),
      ], last: !foot),
      if (foot)
        if (s.roles.contains(PlatformRole.admin))
          Text(adminNotSuspended, style: _muted)
        else ...[
          QuietAction(
            label: 'Suspender conta',
            destructive: true,
            busy: _busy(const _Suspend()),
            onPressed: idle ? () => _act(const _Suspend()) : null,
          ),
          // Why it did not happen stays at the foot; done, the notice
          // stands under Situação.
          ..._outcome(const _Suspend(), notices: false),
        ],
    ];
  }

  /// The roles held, by their area's name, in the app's order.
  static String _roles(Set<PlatformRole> roles) => [
    for (final r in PlatformRole.values)
      if (roles.contains(r)) TeamWords.area(r),
  ].join(CurationWords.dot);

  /// The roles held in words, for a sentence: "Curadoria" or "Curadoria e
  /// Moderação", in the app's order.
  static String _rolesInWords(Set<PlatformRole> roles) {
    final areas = [
      for (final r in PlatformRole.values)
        if (roles.contains(r)) TeamWords.area(r),
    ];
    if (areas.length < 2) return areas.join();
    final last = areas.removeLast();
    return '${areas.join(', ')} e $last';
  }

  /// A read line: [lines] in body-large, then [muted]; read as one line.
  Widget _lines(List<String> lines, {String? muted}) {
    final text = Theme.of(context).textTheme;
    return ReadLine(
      label: [...lines, ?muted].join(', '),
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) const SizedBox(height: Space.xs),
          Text(line, style: text.bodyLarge),
        ],
        if (muted != null) ...[
          const SizedBox(height: Space.xs),
          Text(muted, style: _muted),
        ],
      ],
    );
  }

  /// A section: its [title] in title-medium, marked as a header, 12 px
  /// (md) over its [content], then its [actions] 16 px (lg) below; 32 px
  /// (xxl) before the next unless it is the [last].
  List<Widget> _section(
    String title,
    List<Widget> content, {
    List<Widget> actions = const [],
    bool last = false,
  }) => [
    Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
    const SizedBox(height: Space.md),
    ...content,
    if (actions.isNotEmpty) ...[const SizedBox(height: Space.lg), ...actions],
    if (!last) const SizedBox(height: Space.xxl),
  ];
}
