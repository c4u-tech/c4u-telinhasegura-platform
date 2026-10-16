import 'dart:async';

import '../access/reauth_write.dart';
import '../auth/api_error.dart';

/// One account write's lifecycle, as [ReauthWrite] keeps it (busy, the form message, the rate-limit countdown, `reauth_required` confirmed and retried once),
/// plus the answer
/// every account screen shares: `unauthenticated` signs the app out, and
/// the router lands on the entry screen. The web client has no
/// refresh to try first, so the screen does it.
class AccountWrite extends ReauthWrite {
  AccountWrite({
    required super.confirm,
    super.elevate,
    super.enroll,
    required this.signOut,
  });

  /// Forgets the session. Usually `services.client.forgetSession`.
  final Future<void> Function() signOut;

  @override
  bool? take(ApiError error) {
    if (error.code != 'unauthenticated') return null;
    unawaited(signOut());
    return true;
  }
}
