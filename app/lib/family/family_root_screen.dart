import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid_mode/kid_mode_door.dart';
import '../shell/list_detail.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'avatars.dart';
import 'family.dart';
import 'family_model.dart';
import 'labels.dart';
import 'widgets.dart';

/// `/familia`, the Família destination's root: the family's areas as
/// doors (Crianças and Responsáveis counted in state modules, Convites
/// for the owner, Modo criança), then leaving or deleting the family,
/// quiet, at the foot. It holds no list itself: a child's time and videos
/// live on the child's page, opened from Crianças.
class FamilyRootScreen extends StatefulWidget {
  const FamilyRootScreen({super.key});

  @override
  State<FamilyRootScreen> createState() => _FamilyRootScreenState();
}

class _FamilyRootScreenState extends State<FamilyRootScreen> {
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
      title: 'Sua família',
      // Inside the navigation the destinations are the way elsewhere;
      // while the family is still being read there is none yet.
      onBack: ShellFrame.maybeOf(context) == null
          ? () => context.go(Routes.home)
          : null,
      children: switch (_model.state) {
        FamilyReady(:final family) => [
          Doors(children: _doors(family)),
          const SizedBox(height: Space.xxl),
          _foot(family),
        ],
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _doors(Family family) {
    final children = family.minors.length;
    final adults = family.members.length + family.pendingInvitations;
    final childWords = FamilyWords.children(children);
    final adultWords = FamilyWords.adults(
      family.members.length,
      family.pendingInvitations,
    );
    final waiting = FamilyWords.invitationsWaiting(family.pendingInvitations);
    return [
      DoorRow(
        title: 'Crianças',
        selected: ShellFrame.isChosen(context, Routes.children),
        semanticsLabel: 'Crianças, $childWords',
        onTap: () => openItem(context, Routes.children),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (family.minors.isNotEmpty) ...[
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final minor in family.minors)
                    AvatarDisc(minor.avatar, excludeSemantics: true),
                ],
              ),
              const SizedBox(height: Space.md),
            ],
            CapacityRow(filled: children, total: kMaxMinors, words: childWords),
          ],
        ),
      ),
      DoorRow(
        title: 'Responsáveis',
        selected: ShellFrame.isChosen(context, Routes.adults),
        semanticsLabel: 'Responsáveis, $adultWords',
        onTap: () => openItem(context, Routes.adults),
        child: CapacityRow(
          filled: adults,
          total: kMaxAdults,
          words: adultWords,
        ),
      ),
      if (family.role == FamilyRole.owner)
        DoorRow(
          title: 'Convites',
          selected: ShellFrame.isChosen(context, Routes.invitations),
          semanticsLabel: 'Convites, $waiting',
          onTap: () => openItem(context, Routes.invitations),
          child: _muted(waiting),
        ),
      // Every member's, owner or not.
      const KidModeDoor(),
    ];
  }

  Widget _muted(String words) => Text(
    words,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted),
  );

  /// Deleting the family (owner) or leaving it (guardian), each on its
  /// own screen.
  Widget _foot(Family family) => family.role == FamilyRole.owner
      ? QuietAction(
          label: 'Excluir família',
          destructive: true,
          onPressed: () => context.go(Routes.deleteFamily),
        )
      : QuietAction(
          label: 'Sair da família',
          onPressed: () => context.go(Routes.adults),
        );
}
