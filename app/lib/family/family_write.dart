import 'dart:async';

import '../access/reauth_write.dart';
import '../auth/api_error.dart';
import 'family_model.dart';

/// One family write's lifecycle, as [ReauthWrite] keeps it (busy, the form message, the rate-limit countdown, `reauth_required` confirmed and retried once),
/// plus the answers every family screen
/// shares: `no_family` and `email_unverified` go to [FamilyModel.absorb],
/// and `not_owner` refreshes the family before its copy
/// shows.
class FamilyWrite extends ReauthWrite {
  FamilyWrite({
    required this._family,
    required super.confirm,
    this.ownerOnly = false,
  });

  final FamilyModel _family;

  /// Writes of an owner-only screen: a `not_owner` takes the guardian
  /// home, so its copy goes along as the home's notice.
  final bool ownerOnly;

  @override
  bool? take(ApiError error) {
    switch (error.code) {
      case 'no_family' || 'email_unverified':
        return _family.absorb(error);
      case 'not_owner':
        unawaited(ownerOnly ? _family.notOwner(error) : _family.refresh());
    }
    return null;
  }
}
