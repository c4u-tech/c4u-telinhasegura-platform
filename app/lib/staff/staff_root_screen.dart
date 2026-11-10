import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_api.dart' show PlatformRole;
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';

/// One door per platform role in [roles]: "Curadoria" and "Pacotinhos"
/// for a curator, "Moderação" for a moderator who is not an admin,
/// "Administração" for an admin. A role the server drops goes on the
/// next session read.
List<DoorRow> staffDoors(BuildContext context, Set<PlatformRole> roles) {
  final admin = roles.contains(PlatformRole.admin);
  DoorRow door(String title, String line, String path) => DoorRow(
    title: title,
    semanticsLabel: '$title, $line',
    onTap: () => context.go(path),
    child: Text(
      line,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted),
    ),
  );
  return [
    if (roles.contains(PlatformRole.curator)) ...[
      door('Curadoria', 'Fila de revisão', Routes.curation),
      door('Pacotinhos', 'Montar e revisar', Routes.packs),
    ],
    // The admin reaches the held videos from Administração.
    if (roles.contains(PlatformRole.moderator) && !admin)
      door('Moderação', 'Vídeos retidos', Routes.heldVideos),
    if (admin)
      door('Administração', 'Contas, equipe, vídeos e auditoria', Routes.admin),
  ];
}

/// `/equipe`: the staff areas the session's platform roles open, the
/// Equipe destination's root. The router lets only a role holder in;
/// staff need no family, so without one it stands outside the
/// navigation, with a back control to the home.
class StaffRootScreen extends StatefulWidget {
  const StaffRootScreen({super.key});

  @override
  State<StaffRootScreen> createState() => _StaffRootScreenState();
}

class _StaffRootScreenState extends State<StaffRootScreen> {
  late final FamilyModel _model;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    // The roles come with the account's read; it notifies the router, so
    // after this build.
    scheduleMicrotask(_model.load);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => FieldLayout(
      title: 'Equipe',
      onBack: ShellFrame.maybeOf(context) == null
          ? () => context.go(Routes.home)
          : null,
      children: [
        switch (_model.roles) {
          final roles? => Doors(children: staffDoors(context, roles)),
          null => const FamilyPlaceholder(label: 'Carregando a equipe'),
        },
      ],
    ),
  );
}
