import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_error.dart';
import '../auth/auth_api.dart';
import '../shell/routes.dart';
import '../shell/services.dart';

/// The curator, admin and moderation routes' guard:
/// a route none of whose roles the session
/// holds goes home. The moderation routes take a moderator or an admin.
/// Roles not read yet decide nothing; the screen reads them
/// (`FamilyModel.load`) and the router decides again. It only spares a
/// round trip: the server reads the roles on every request.
String? roleRedirect(Set<PlatformRole>? roles, String path) {
  if (roles == null) return null;
  final any = Routes.isCuratorScreen(path)
      ? const {PlatformRole.curator}
      : Routes.isAdminScreen(path)
      ? const {PlatformRole.admin}
      : Routes.isModerationScreen(path)
      ? const {PlatformRole.moderator, PlatformRole.admin}
      : null;
  if (any == null || any.any(roles.contains)) return null;
  return Routes.home;
}

/// Takes a staff call's `not_curator`, `not_admin` or `not_moderator`
/// [error], or the MFA routes' `not_staff`: the role goes from the family
/// model, the session is read again, and the app goes home, where the
/// notice says why and the door is gone. A curator who has not accepted
/// the curator terms (`declaration_required`) is taken to them, to come
/// back to this screen. Returns whether it took [error]; a screen words
/// anything else itself.
bool takeLostRole(BuildContext context, Object error) {
  if (error case ApiError(code: 'declaration_required')) {
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri
        .toString();
    context.go(Routes.curatorTermsFor(then: here));
    return true;
  }
  const lost = {'not_curator', 'not_admin', 'not_moderator', 'not_staff'};
  if (error is! ApiError || !lost.contains(error.code)) {
    return false;
  }
  final model = AppScope.of(context).familyModel;
  unawaited(model.roleLost(error));
  context.go(Routes.home);
  return true;
}
