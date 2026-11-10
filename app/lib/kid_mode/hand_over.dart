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
/// PIN goes to the guide whose first step creates it. A child the family
/// no longer holds says so, calls [onGone] and reads the family again.
Future<void> handOverTo(
  BuildContext context,
  FamilyWrite write,
  Minor minor, {
  VoidCallback? onGone,
}) async {
  final services = AppScope.of(context);
  await write.write(
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
          if (context.mounted) context.go(Routes.kidMode);
          return true;
        case 'not_found':
          onGone?.call();
          unawaited(services.familyModel.refresh());
      }
      return false;
    },
  );
}
