import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/avatars.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/family_write.dart';
import '../family/profile_fields.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'kid_mode_screen.dart';

const _howToLeave =
    'Escolha quem vai usar este aparelho. Para sair do modo criança, um '
    'adulto segura o canto da tela e digita o PIN.';

/// `/modo-crianca/entregar`: hands this device to a child.
/// The children as a choice of one, none chosen; "Entregar para
/// {apelido}" locks the session, and the router, seeing the mode move,
/// lands on `/crianca` as the band grows into it.
class HandOverScreen extends StatefulWidget {
  const HandOverScreen({super.key});

  @override
  State<HandOverScreen> createState() => _HandOverScreenState();
}

class _HandOverScreenState extends State<HandOverScreen> {
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;
  String? _chosen;

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

  Future<void> _handOver(Minor minor) async {
    await _write.write(
      () => AppScope.of(context).appMode.handOver(minor.id),
      overrides: const {'not_found': Copy.childGone},
      handle: (e) {
        switch (e.code) {
          case 'pin_not_set':
            // The PIN went meanwhile: back to the guide's first step.
            if (mounted) context.go(Routes.kidMode);
            return true;
          case 'not_found':
            setState(() => _chosen = null);
            unawaited(_model.refresh());
        }
        return false;
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => FieldLayout(
      title: 'Entregar este aparelho',
      onBack: () => context.go(Routes.kidMode),
      children: switch (_model.state) {
        FamilyReady(:final family) when family.minors.isEmpty => _noChildren(),
        FamilyReady(:final family) => _choose(family.minors),
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _noChildren() => [
    Text(childFirst, style: Theme.of(context).textTheme.bodyLarge),
    const SizedBox(height: Space.xl),
    PrimaryButton(
      label: 'Cadastrar criança',
      onPressed: () => context.go(Routes.newChild),
    ),
  ];

  List<Widget> _choose(List<Minor> minors) {
    final chosen = minors.where((m) => m.id == _chosen).firstOrNull;
    final busy = _write.busy;
    return [
      Text(_howToLeave, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: Space.xl),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final minor in minors)
            ChildChoice(
              nickname: minor.nickname,
              avatar: minor.avatar,
              selected: minor.id == _chosen,
              onTap: busy
                  ? null
                  : () {
                      _write.clearMessage();
                      setState(() => _chosen = minor.id);
                    },
            ),
        ],
      ),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: chosen == null ? 'Entregar' : 'Entregar para ${chosen.nickname}',
        busy: busy,
        onPressed: chosen == null || _write.blocked
            ? null
            : () => _handOver(chosen),
      ),
      // Its place stays once a child is chosen: nothing moves (fix round).
      SubmitHint(
        'Escolha uma criança acima.',
        visible: chosen == null,
        reserve: true,
      ),
    ];
  }
}

/// One child as a choice of one: the 96 dp avatar with the nickname
/// under it, read as a radio by the nickname. Chosen, the avatar takes
/// the picker's ring.
class ChildChoice extends StatelessWidget {
  const ChildChoice({
    super.key,
    required this.nickname,
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  final String nickname;
  final Avatar avatar;
  final bool selected;
  final VoidCallback? onTap;

  /// The ring's outer size: the avatar, its 2 px gap and 3 px stroke on
  /// each side, held by every tile, chosen or not, so choosing moves
  /// nothing.
  static const ring = KidSizes.avatar + 2 * (3 + 2);

  /// The ring and 3 px on each side.
  static const width = ring + 2 * 3;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ChoiceTarget(
      label: nickname,
      selected: selected,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(
            children: [
              // The ring stands 2 px off the disc, as in the avatar picker.
              SizedBox.square(
                dimension: ring,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(2),
                  decoration: ShapeDecoration(
                    shape: CircleBorder(
                      side: BorderSide(
                        color: selected ? p.action : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: AvatarDisc(
                      avatar,
                      size: KidSizes.avatar,
                      excludeSemantics: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                nickname,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
