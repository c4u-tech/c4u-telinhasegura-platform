import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'confirm.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'labels.dart';
import 'widgets.dart';

/// Under the owner's list: the owner cannot leave.
const ownerLeaves =
    'Para sair da família, torne antes outro responsável titular: toque no '
    'e-\u2060mail dele e escolha "Tornar titular".';

/// The same, for an owner with nobody to hand the family to.
const ownerAlone =
    'Por enquanto, só você cuida desta família. Para sair dela, convide '
    'outro adulto e torne essa pessoa titular, ou exclua a família.';

String _plain(String address) => address;

/// `/familia/responsaveis`: every adult by email, the owner marked
/// "titular" and the caller "você". The owner
/// removes a guardian or hands the family over; a guardian
/// leaves.
class AdultsScreen extends StatefulWidget {
  const AdultsScreen({super.key});

  @override
  State<AdultsScreen> createState() => _AdultsScreenState();
}

class _AdultsScreenState extends State<AdultsScreen> {
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;

  /// The guardian a write is about, whose row shows the progress.
  String? _pending;

  /// The calm line after a write went through, with its address set by
  /// the given function: break marks to show, plain to read.
  String Function(String Function(String) set)? _done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(family: _model, confirm: () => confirmItsYou(context));
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  bool _isCaller(Member member) =>
      member.email.toLowerCase() == _model.email?.toLowerCase();

  /// The member's marks, in words: "titular", "responsável", "você".
  List<String> _marks(Member member) => [
    switch (member.role) {
      FamilyRole.owner => 'titular',
      FamilyRole.guardian => 'responsável',
      FamilyRole.unknown => 'adulto da família',
    },
    if (_isCaller(member)) 'você',
  ];

  /// Runs a write about [member], refreshing the family after it. A
  /// problem stays on the screen; the roles are read again when they may
  /// have moved (`not_found`: the guardian already left).
  Future<void> _act(
    Member member,
    Future<void> Function() action,
    String Function(String Function(String) set) done,
  ) async {
    setState(() {
      _pending = member.accountId;
      _done = null;
    });
    final ok = await _write.write(action, handle: _refreshOn('not_found'));
    if (ok) await _model.refresh();
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (ok) _done = done;
    });
  }

  bool Function(ApiError) _refreshOn(String code) => (e) {
    if (e.code == code) unawaited(_model.refresh());
    return false;
  };

  Future<void> _openGuardian(Member member) async {
    final action = await showDialog<GuardianAction>(
      context: context,
      useSafeArea: false,
      barrierColor: BrandColors.dark.withValues(alpha: 0.6),
      builder: (_) => GuardianActions(email: member.email),
    );
    if (!mounted) return;
    switch (action) {
      case GuardianAction.transfer:
        await _transfer(member);
      case GuardianAction.remove:
        await _remove(member);
      case null:
    }
  }

  Future<void> _remove(Member member) async {
    final api = AppScope.of(context).family;
    final email = member.email;
    // The address shown with its break marks, read plain.
    String title(String Function(String) set) => 'Remover ${set(email)}?';
    List<String> body(String Function(String) set) => [
      '${set(email)} deixa de fazer parte da família: não vê mais os perfis '
          'das crianças e não cuida mais deles.',
      'Avisamos essa pessoa por e-\u2060mail. Para voltar, ela vai precisar '
          'de um novo convite.',
    ];
    final confirmed = await confirmDestructive(
      context,
      title: title(addressBreaks),
      titleSemanticsLabel: title(_plain),
      body: body(addressBreaks),
      bodySemanticsLabels: body(_plain),
      action: 'Remover',
    );
    if (!confirmed || !mounted) return;
    await _act(
      member,
      () => api.removeGuardian(member.accountId),
      (set) => 'Removemos ${set(email)} da família.',
    );
  }

  Future<void> _transfer(Member member) async {
    final api = AppScope.of(context).family;
    final email = member.email;
    // The address shown with its break marks, read plain.
    String title(String Function(String) set) =>
        'Tornar ${set(email)} titular?';
    List<String> body(String Function(String) set) => [
      '${set(email)} passa a ser a pessoa titular: é quem convida adultos, '
          'cancela convites, remove responsáveis e pode excluir a família.',
      'Você passa a ser responsável, como os outros adultos, e continua '
          'cuidando das crianças.',
      'Avisamos as duas contas por e-\u2060mail.',
    ];
    final confirmed = await confirmDestructive(
      context,
      title: title(addressBreaks),
      titleSemanticsLabel: title(_plain),
      body: body(addressBreaks),
      bodySemanticsLabels: body(_plain),
      action: 'Tornar titular',
    );
    if (!confirmed || !mounted) return;
    await _act(
      member,
      () => api.transferOwnership(member.accountId),
      (set) => '${set(email)} agora é titular da família.',
    );
  }

  Future<void> _leave() async {
    final api = AppScope.of(context).family;
    final confirmed = await confirmDestructive(
      context,
      title: 'Sair da família?',
      body: const [
        'Você deixa de ver os perfis das crianças desta família e de cuidar '
            'deles.',
        'Para voltar, você vai precisar de um novo convite de quem é '
            'titular.',
      ],
      action: 'Sair da família',
    );
    if (!confirmed || !mounted) return;
    setState(() => _done = null);
    // The owner cannot leave: the roles moved since this screen read them.
    final ok = await _write.write(
      api.leave,
      handle: _refreshOn('owner_must_transfer'),
    );
    if (!ok || !mounted) return;
    _model.left();
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => FieldLayout(
      title: 'Responsáveis',
      onBack: () => context.go(Routes.home),
      children: switch (_model.state) {
        FamilyReady(:final family) => _list(family),
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _list(Family family) {
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    final owner = family.role == FamilyRole.owner;
    final adults = family.members.length + family.pendingInvitations;
    final alone = family.members.length == 1;
    // A suspended owner reaches only the transfer, the step its erasure
    // asks for: no removal, no leaving, no invitations.
    final suspended = _model.suspended;
    return [
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_done case final done?) ...[
        Notice(done(addressBreaks), semanticsLabel: done(_plain)),
        const SizedBox(height: Space.lg),
      ],
      Doors(
        children: [
          for (final member in family.members)
            if (owner && member.role == FamilyRole.guardian)
              DoorRow(
                title: addressBreaks(member.email),
                semanticsLabel: [member.email, ..._marks(member)].join(', '),
                busy: _write.busy && _pending == member.accountId,
                onTap: () =>
                    suspended ? _transfer(member) : _openGuardian(member),
                child: Text(_marks(member).join(' · '), style: muted),
              )
            else
              _MemberRow(email: member.email, marks: _marks(member)),
        ],
      ),
      const SizedBox(height: Space.xl),
      CapacityRow(
        filled: adults,
        total: kMaxAdults,
        words: FamilyWords.adults(
          family.members.length,
          family.pendingInvitations,
        ),
      ),
      if (!suspended) ...[
        const SizedBox(height: Space.xl),
        if (owner) ...[
          PrimaryButton(
            label: 'Convidar responsável',
            onPressed: () => context.go(Routes.invitations),
          ),
          const SizedBox(height: Space.xl),
          Text(alone ? ownerAlone : ownerLeaves, style: muted),
        ] else ...[
          const SizedBox(height: Space.lg),
          QuietAction(
            label: 'Sair da família',
            destructive: true,
            busy: _write.busy,
            onPressed: _write.blocked ? null : _leave,
          ),
        ],
      ],
    ];
  }
}

/// An adult nobody acts on from here: the caller, the owner, or anyone
/// when the caller is a guardian. Same height and rhythm as a door row.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.email, required this.marks});

  final String email;
  final List<String> marks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: [email, ...marks].join(', '),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressText(email, style: text.titleMedium),
                const SizedBox(height: Space.sm),
                Text(
                  marks.join(' · '),
                  style: text.bodyMedium?.copyWith(
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum GuardianAction { transfer, remove }

/// What the owner can do about one guardian, as a whole task screen over
/// the list: hand the family over, or (quiet, in clay, at the foot)
/// remove them. Each answer then asks for its own confirmation.
class GuardianActions extends StatelessWidget {
  const GuardianActions({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    void close(GuardianAction? action) => Navigator.of(context).pop(action);
    final text = Theme.of(context).textTheme;
    return Dialog.fullscreen(
      backgroundColor: context.palette.ground,
      child: FieldLayout(
        title: 'Responsável',
        onBack: () => close(null),
        children: [
          AddressText(email, style: text.titleMedium),
          const SizedBox(height: Space.md),
          Text(
            'Cuida das crianças da família com você. Você pode passar a '
            'titularidade para essa pessoa, ou removê-la da família.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: Space.xl),
          OutlinedButton(
            onPressed: () => close(GuardianAction.transfer),
            child: const Text('Tornar titular'),
          ),
          const SizedBox(height: Space.xxl),
          QuietAction(
            label: 'Remover',
            destructive: true,
            onPressed: () => close(GuardianAction.remove),
          ),
        ],
      ),
    );
  }
}
