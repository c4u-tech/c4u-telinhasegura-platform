import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid_mode/hand_over.dart';
import '../kid_mode/hand_over_screen.dart';
import '../kid_mode/kid_mode_screen.dart' show pinPurpose;
import '../kid_mode/set_pin_screen.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'avatars.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'new_child_screen.dart';
import 'widgets.dart';

/// The steps of the first run.
const firstRunSteps = 3;

/// `/comecar`: a new family's first hand-over as one walk of three steps,
/// "Passo n de 3": registering a child (the child form, profile then
/// consent), creating the PIN (the PIN pad and its confirmation), then
/// "Tudo pronto", handing the device to the child. The step shown is the
/// first one the family has not met, so a family that already has a child
/// starts at the PIN. Every step offers "Fazer depois", back to Início.
class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key, this.child});

  /// The child the path registered, when it comes back to its last step.
  final String? child;

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;

  /// Whether the family has a PIN: null until read.
  bool? _pinSet;
  bool _readFailed = false;

  /// The child registered on this path, handed the device at its end.
  late String? _registered = widget.child;

  /// The child chosen at the end, when the family has several and the
  /// path registered none of them.
  String? _chosen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(family: _model, confirm: () => confirmItsYou(context));
    scheduleMicrotask(_model.load);
    _read();
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() => _readFailed = false);
    try {
      final set = await AppScope.of(context).parental.pinIsSet();
      if (mounted) setState(() => _pinSet = set);
    } on Object catch (e) {
      // no_family ends the family area; the router then leaves.
      if (_model.absorb(e) || !mounted) return;
      setState(() => _readFailed = true);
    }
  }

  void _later() => context.go(Routes.home);

  List<Widget> get _foot => [
    const SizedBox(height: Space.xxl),
    QuietAction(label: 'Fazer depois', onPressed: _later),
  ];

  Future<void> _give(Minor minor) async {
    _write.clearMessage();
    await handOverTo(
      context,
      _write,
      minor,
      onGone: () => setState(() {
        _registered = null;
        _chosen = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => switch ((_model.state, _pinSet)) {
      (FamilyReady(:final family), _) when family.minors.isEmpty =>
        NewChildScreen(
          key: const ValueKey('first-run-child'),
          step: (1, firstRunSteps),
          onBack: _later,
          onCreated: (minor) => setState(() => _registered = minor.id),
          foot: _foot,
        ),
      (FamilyReady(), false) => SetPinScreen(
        key: const ValueKey('first-run-pin'),
        step: (2, firstRunSteps),
        lead: pinPurpose,
        onBack: _later,
        onSaved: () => setState(() => _pinSet = true),
        foot: _foot,
      ),
      (FamilyReady(:final family), true) => _ready(family.minors),
      (FamilyReady(), null) => FieldLayout(
        title: 'Sua família',
        onBack: _later,
        children: _readFailed
            ? [
                const ErrorNote(Copy.genericRetry),
                const SizedBox(height: Space.lg),
                PrimaryButton(label: 'Tentar de novo', onPressed: _read),
              ]
            : const [FamilyPlaceholder(label: 'Carregando o PIN')],
      ),
      _ => FieldLayout(
        title: 'Sua família',
        onBack: _later,
        children: familyPending(_model),
      ),
    },
  );

  /// "Tudo pronto": the child the path registered (or the family's only
  /// child) with its hand-over, or the children as a choice of one; then
  /// linking the child's own device, as a quiet way.
  Widget _ready(List<Minor> minors) {
    final text = Theme.of(context).textTheme;
    final named = minors.where((m) => m.id == _registered).firstOrNull;
    final single = named ?? (minors.length == 1 ? minors.single : null);
    final chosen = single ?? minors.where((m) => m.id == _chosen).firstOrNull;
    final busy = _write.busy;
    return FieldLayout(
      key: const ValueKey('first-run-ready'),
      title: 'Tudo pronto',
      onBack: _later,
      children: [
        const StepMarks(step: 3, of: firstRunSteps),
        const SizedBox(height: Space.xl),
        if (single != null) ...[
          _ChildMark(single),
          const SizedBox(height: Space.xl),
          Text(howToLeave, style: text.bodyLarge),
        ] else ...[
          Text(chooseAndLeave, style: text.bodyLarge),
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
        ],
        const SizedBox(height: Space.xl),
        if (_write.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        PrimaryButton(
          label: chosen == null
              ? 'Entregar'
              : 'Entregar para ${chosen.nickname}',
          busy: busy,
          onPressed: chosen == null || _write.blocked
              ? null
              : () => _give(chosen),
        ),
        if (single == null)
          SubmitHint(
            'Escolha uma criança acima.',
            visible: chosen == null,
            reserve: true,
          ),
        const SizedBox(height: Space.xl),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'A criança tem o próprio aparelho?',
              style: text.bodyLarge?.copyWith(color: context.palette.muted),
            ),
            const SizedBox(width: Space.xs),
            QuietAction(
              label: 'Vincular',
              semanticsLabel: 'Vincular o aparelho da criança',
              inline: true,
              onPressed: busy
                  ? null
                  : () => context.go(
                      Routes.linkCodeFrom(
                        Routes.firstRunFor(child: chosen?.id ?? _registered),
                      ),
                    ),
            ),
          ],
        ),
        ..._foot,
      ],
    );
  }
}

/// The child about to be handed the device: the 96 dp avatar with the
/// nickname under it, read as the nickname.
class _ChildMark extends StatelessWidget {
  const _ChildMark(this.minor);

  final Minor minor;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AvatarDisc(minor.avatar, size: KidSizes.avatar, excludeSemantics: true),
        const SizedBox(height: Space.sm),
        Text(minor.nickname, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
