import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_error.dart';
import '../curation/role_gate.dart';
import '../design/field_layout.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'challenge.dart';

/// What assistive technology hears while the gate reads the status.
const checkingAccess = 'Carregando';

/// The admin and moderation routes' second-factor gate,
/// around each of their screens, so a door, a direct URL and a
/// refresh all pass through it. Before [child] is built, and so before its
/// own read, it reads `MfaStatus`: required and not enrolled opens the
/// enrollment, which comes back here; required and not elevated, the
/// challenge; otherwise [child]. A cancel goes home. While the session is
/// known to be elevated ([ElevationNote]) it opens at once, so moving
/// inside the area asks nothing. Screens stacked by a deep URL share one
/// read and one challenge. It only spares a round trip: the server
/// refuses regardless, and the screens then ask.
class StaffGate extends StatefulWidget {
  const StaffGate({super.key, required this.title, required this.child});

  /// The screen's title, over the placeholder while the gate reads.
  final String title;
  final Widget child;

  @override
  State<StaffGate> createState() => _StaffGateState();
}

/// The key screens stacked by one URL share their check under.
const _checking = #staffGate;

class _StaffGateState extends State<StaffGate> {
  FamilyModel? _model;
  bool _started = false;
  bool _asked = false;
  late bool _open;

  /// This gate's own route, which a redirect may already have left.
  late String _path;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _open = services.elevation.holds;
    if (_open) return;
    _path = GoRouterState.of(context).uri.path;
    // The screen is not built yet, so the gate reads the roles: the
    // router sends a session without the area's role home first.
    final model = _model = services.familyModel;
    scheduleMicrotask(model.load);
    model.addListener(_rolesRead);
    _rolesRead();
  }

  @override
  void dispose() {
    _model?.removeListener(_rolesRead);
    super.dispose();
  }

  GoRouter get _router => GoRouter.of(context);

  String get _location =>
      _router.routerDelegate.currentConfiguration.uri.toString();

  void _rolesRead() {
    final roles = _model?.roles;
    if (_asked || roles == null) return;
    if (roleRedirect(roles, _path) != null) return;
    _asked = true;
    scheduleMicrotask(_check);
  }

  Future<void> _check() async {
    if (!mounted) return;
    final open = await AppScope.of(context).elevation.once(_checking, _decide);
    if (open && mounted) setState(() => _open = true);
  }

  /// Whether the route may open; when not, the gate has gone elsewhere.
  Future<bool> _decide() async {
    final services = AppScope.of(context);
    final router = _router;
    final then = _location;
    try {
      final status = await services.mfa.status();
      if (!status.mfaRequired) {
        services.elevation.notAsked();
        return true;
      }
      if (status.elevatedUntil case final until?
          when until.isAfter(clock.now())) {
        services.elevation.elevated(until);
        return true;
      }
      if (!status.enrolled) {
        router.go(Routes.mfaEnrollment(then: then));
        return false;
      }
    } on Object catch (e) {
      if (e is ApiError && e.code == 'unauthenticated') {
        unawaited(services.client.forgetSession());
        return false;
      }
      if (!mounted || takeLostRole(context, e)) return false;
      // Unread, the route opens: its screens meet the server's refusal.
      return true;
    }
    if (!mounted) return false;
    if (await askChallenge(context)) return true;
    router.go(Routes.home);
    return false;
  }

  @override
  Widget build(BuildContext context) => _open
      ? widget.child
      : FieldLayout(
          title: widget.title,
          onBack: () => context.go(Routes.home),
          children: const [FamilyPlaceholder(label: checkingAccess)],
        );
}
