import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/avatars.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/labels.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'kid_mode_status.dart';

/// What `/modo-crianca/pin` hands back to `/modo-crianca` on success (the
/// route's `extra`): a PIN created from the guide goes on to its second
/// step, a PIN changed back to the index.
enum PinSaved { created, changed }

/// Under the first two doors while the family has no children.
const childFirst = 'Primeiro, cadastre uma criança na família.';

const _pinPurpose =
    'O PIN é um número que só os adultos da família sabem. Com o modo '
    'criança ligado, só um adulto com ele sai do modo criança ou troca a '
    'criança de um aparelho.';

/// `/modo-crianca`: the guide while the family has no PIN ("Passo 1 de
/// 2", then "Passo 2 de 2" once the PIN is created), the index once it
/// has one. A saved PIN arrives with the sun rising
/// and the words that the other adults were told.
class KidModeScreen extends StatefulWidget {
  const KidModeScreen({super.key, this.saved});

  final PinSaved? saved;

  @override
  State<KidModeScreen> createState() => _KidModeScreenState();
}

class _KidModeScreenState extends State<KidModeScreen> {
  late final FamilyModel _model;
  bool _started = false;
  KidModeStatus? _status;
  bool _failed = false;
  bool _current = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Back on top after a screen of its own (a hand-over refused, devices
    // unlinked): the PIN and the devices may have changed meanwhile.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_current && _status != null) _read(quiet: true);
    _current = current;
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    scheduleMicrotask(_model.load);
    _read();
  }

  /// A [quiet] read keeps what shows until the answer replaces it, and
  /// keeps it on a failure.
  Future<void> _read({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _status = null;
        _failed = false;
      });
    }
    try {
      final status = await KidModeStatus.read(AppScope.of(context).parental);
      if (mounted) setState(() => _status = status);
    } on Object catch (e) {
      // no_family ends the family area; the router then leaves.
      if (_model.absorb(e) || !mounted || quiet) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => FieldLayout(
      title: 'Modo criança',
      rise: widget.saved != null,
      onBack: () => context.go(Routes.home),
      children: switch ((_model.state, _status)) {
        (FamilyReady(:final family), final status?) => _shape(family, status),
        (FamilyReady(), null) when _failed => [
          const ErrorNote(Copy.genericRetry),
          const SizedBox(height: Space.lg),
          PrimaryButton(label: 'Tentar de novo', onPressed: _read),
        ],
        (FamilyReady(), null) => const [
          FamilyPlaceholder(label: 'Carregando o modo criança'),
        ],
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _shape(Family family, KidModeStatus status) {
    final saved = widget.saved;
    return [
      if (saved != null) ...[
        Notice(_savedWords(saved, family)),
        const SizedBox(height: Space.xl),
      ],
      if (saved == PinSaved.created)
        ..._secondStep(family)
      else if (status.pinSet)
        ..._index(family, status)
      else
        ..._firstStep(),
    ];
  }

  /// The other adults hear of it only when there are some (the
  /// server mails every other guardian).
  String _savedWords(PinSaved saved, Family family) {
    final done = saved == PinSaved.created ? 'PIN criado.' : 'PIN trocado.';
    if (family.members.length < 2) return done;
    return '$done Avisamos por e-⁠mail os outros adultos da família.';
  }

  List<Widget> _firstStep() => [
    const StepMarks(step: 1, of: 2),
    const SizedBox(height: Space.lg),
    Text(_pinPurpose, style: Theme.of(context).textTheme.bodyLarge),
    const SizedBox(height: Space.xl),
    PrimaryButton(
      label: 'Criar o PIN',
      onPressed: () => context.go(Routes.setPin),
    ),
  ];

  List<Widget> _secondStep(Family family) => [
    const StepMarks(step: 2, of: 2),
    const SizedBox(height: Space.lg),
    Doors(children: _moves(family)),
  ];

  List<Widget> _index(Family family, KidModeStatus status) {
    final devices = status.devices.length;
    final words = KidModeWords.capacity(devices);
    return [
      Doors(
        children: [
          ..._moves(family),
          DoorRow(
            title: 'Aparelhos vinculados',
            semanticsLabel: 'Aparelhos vinculados, $words',
            onTap: () => context.go(Routes.devices),
            child: CapacityRow(
              filled: devices,
              total: kMaxDevices,
              words: words,
            ),
          ),
          DoorRow(
            title: 'Trocar o PIN',
            onTap: () => context.go(Routes.setPin),
          ),
        ],
      ),
    ];
  }

  /// "Entregar este aparelho" and "Vincular o aparelho da criança"; with
  /// no children, both send to registering one first.
  List<Widget> _moves(Family family) {
    final minors = family.minors;
    if (minors.isEmpty) {
      Widget first(String title) => DoorRow(
        title: title,
        semanticsLabel: '$title, $childFirst',
        onTap: () => context.go(Routes.newChild),
        child: Text(
          childFirst,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.palette.muted),
        ),
      );
      return [
        first('Entregar este aparelho'),
        first('Vincular o aparelho da criança'),
      ];
    }
    final names = FamilyWords.names([for (final m in minors) m.nickname]);
    return [
      DoorRow(
        title: 'Entregar este aparelho',
        semanticsLabel: 'Entregar este aparelho, para $names',
        onTap: () => context.go(Routes.handOver),
        child: Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final minor in minors)
              AvatarDisc(minor.avatar, excludeSemantics: true),
          ],
        ),
      ),
      DoorRow(
        title: 'Vincular o aparelho da criança',
        onTap: () => context.go(Routes.linkCode),
      ),
    ];
  }
}
