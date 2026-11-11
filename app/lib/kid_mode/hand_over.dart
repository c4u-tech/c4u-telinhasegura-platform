import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../family/family.dart';
import '../family/family_write.dart';
import '../shell/routes.dart';
import '../shell/services.dart';

/// Hands this device to [minor] through [write]: the session locks, and
/// the router, seeing the mode move, lands on the child home as the band
/// grows into it. A child whose consent must be renewed takes the adult to
/// that authorization first, returning to the hand-over; a family with no
/// PIN goes to the first run, which creates it and then hands the device
/// to the same child. A child the family
/// no longer holds says so, calls [onGone] and reads the family again.
///
/// With [then], a place on the child's side, the device lands there
/// instead of the child home once handed over: the player a guardian
/// started a long work in.
Future<void> handOverTo(
  BuildContext context,
  FamilyWrite write,
  Minor minor, {
  VoidCallback? onGone,
  String? then,
}) async {
  final services = AppScope.of(context);
  // Taken now: the screen that asked goes as the mode moves.
  final router = GoRouter.of(context);
  final ok = await write.write(
    () => services.appMode.handOver(minor.id),
    overrides: const {'not_found': Copy.childGone},
    handle: (e) {
      switch (e.code) {
        case 'consent_required':
          if (context.mounted) {
            context.go(Routes.reconsent(minor.id, then: Routes.handOver));
          }
          return true;
        case 'pin_not_set':
          if (context.mounted) {
            context.go(Routes.firstRunFor(child: minor.id));
          }
          return true;
        case 'not_found':
          onGone?.call();
          unawaited(services.familyModel.refresh());
      }
      return false;
    },
  );
  if (ok && then != null) router.go(then);
}
