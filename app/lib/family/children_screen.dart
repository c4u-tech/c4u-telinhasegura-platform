import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'avatars.dart';
import 'family.dart';
import 'family_model.dart';
import 'labels.dart';
import 'reconsent_screen.dart' show needsConsent;
import 'widgets.dart';

const _whatAProfileHolds =
    'Ainda não há crianças cadastradas. Cada perfil guarda um apelido, um '
    'avatar e a faixa de idade, e o que a criança assiste: cada vídeo '
    'assistido some em 30 dias, e os totais de tempo de tela por dia, em 90.';

/// `/familia/criancas`: each child by avatar, nickname and age band, and
/// "Cadastrar criança" while the family has room.
/// [notice] is a calm line brought from a child's screen, such as a
/// profile that no longer exists.
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key, this.notice});

  final String? notice;

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  late final FamilyModel _model;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    // Opened directly, the family is read here; it notifies the router,
    // so the read starts after this build.
    scheduleMicrotask(_model.load);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => FieldLayout(
      title: 'Crianças',
      onBack: () => context.go(Routes.home),
      children: switch (_model.state) {
        FamilyReady(:final family) => _list(family.minors),
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _list(List<Minor> minors) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final full = minors.length >= kMaxMinors;
    return [
      if (widget.notice case final notice?) ...[
        Notice(notice),
        const SizedBox(height: Space.lg),
      ],
      if (minors.isEmpty)
        Text(_whatAProfileHolds, style: text.bodyLarge)
      else
        Doors(
          children: [
            for (final minor in minors)
              DoorRow(
                title: minor.nickname,
                semanticsLabel: [
                  minor.nickname,
                  minor.ageBand.label,
                  if (!minor.consentCurrent) needsConsent,
                ].join(', '),
                leading: AvatarDisc(
                  minor.avatar,
                  size: 56,
                  excludeSemantics: true,
                ),
                // A paused child opens straight on its new authorization.
                onTap: () => context.go(
                  minor.consentCurrent
                      ? Routes.child(minor.id)
                      : Routes.reconsent(minor.id),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(minor.ageBand.label, style: muted),
                    if (!minor.consentCurrent) ...[
                      const SizedBox(height: Space.xs),
                      Text(needsConsent, style: text.bodyMedium),
                    ],
                  ],
                ),
              ),
          ],
        ),
      const SizedBox(height: Space.xl),
      CapacityRow(
        filled: minors.length,
        total: kMaxMinors,
        words: FamilyWords.children(minors.length),
      ),
      const SizedBox(height: Space.xl),
      PrimaryButton(
        label: 'Cadastrar criança',
        onPressed: full ? null : () => context.go(Routes.newChild),
      ),
      if (full) const SubmitHint(Copy.childrenFull),
    ];
  }
}
