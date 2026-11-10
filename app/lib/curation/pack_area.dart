import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_api.dart' show PlatformRole;
import '../design/field_layout.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/staff_gate.dart';

/// One screen of the pacotinhos' single area, built for the session's
/// roles: [curator] for a curator (an admin among them too), who reads
/// through the curators' routes; [admin] for an admin who is not a
/// curator, who reads through the admin's routes and so passes the
/// second factor's gate first. Until the roles are read, the placeholder
/// under [title].
class PackArea extends StatefulWidget {
  const PackArea({
    super.key,
    required this.title,
    required this.path,
    required this.curator,
    required this.admin,
  });

  final String title;

  /// The location the route was built for.
  final String path;
  final Widget curator;
  final Widget admin;

  @override
  State<PackArea> createState() => _PackAreaState();
}

class _PackAreaState extends State<PackArea> {
  late final FamilyModel _model;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    scheduleMicrotask(_model.load);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => switch (_model.roles) {
      null => FieldLayout(
        title: widget.title,
        onBack: () => context.go(Routes.staffHome),
        children: const [FamilyPlaceholder(label: checkingAccess)],
      ),
      final roles when roles.contains(PlatformRole.curator) => widget.curator,
      _ => StaffGate(
        title: widget.title,
        path: widget.path,
        child: widget.admin,
      ),
    },
  );
}
