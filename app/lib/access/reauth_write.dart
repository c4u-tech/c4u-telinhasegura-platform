import 'package:flutter/foundation.dart';

import '../auth/api_error.dart';
import 'submission.dart';

/// A write that may ask for a recent confirmation: as [Submission] keeps
/// it (busy, the form message, the rate-limit countdown; input is never
/// cleared), plus `reauth_required`, which asks the guardian to [confirm]
/// and retries the write once. With
/// [elevate], `elevation_required` likewise asks for the MFA challenge
/// and retries once; a write may ask for both, each once, in the order
/// the server asks. With [enroll],
/// `mfa_enrollment_required` runs the enrollment and retries once the
/// same way. A cancelled prompt leaves the screen as it was,
/// with no message.
///
/// Subclasses take the codes their area shares in [take].
class ReauthWrite extends Submission {
  ReauthWrite({required this.confirm, this.elevate, this.enroll});

  /// Opens the re-authentication prompt; true once the guardian
  /// confirmed. Usually `() => confirmItsYou(context)`.
  final Future<bool> Function() confirm;

  /// Opens the MFA challenge; true once passed. Without it,
  /// `elevation_required` is left to the screen like any other code.
  final Future<bool> Function()? elevate;

  /// Opens the MFA enrollment; true once done, the session elevated.
  /// Without it, `mfa_enrollment_required` is left to the screen.
  final Future<bool> Function()? enroll;

  /// The answer to an error this area takes itself: true when placed
  /// (no form message), false when not shown at all, null to leave it to
  /// the screen's `handle` and then to the form message.
  @protected
  bool? take(ApiError error) => null;

  /// Runs [action], returning whether it succeeded. [overrides] and
  /// [handle] work as in [Submission.run], for the codes not taken here.
  Future<bool> write(
    Future<void> Function() action, {
    Map<String, String> overrides = const {},
    bool Function(ApiError error)? handle,
  }) async {
    final prompts = <String, Future<bool> Function()>{
      'reauth_required': confirm,
      'elevation_required': ?elevate,
      'mfa_enrollment_required': ?enroll,
    };
    final asked = <String>{};
    while (true) {
      Future<bool> Function()? prompt;
      final ok = await run(
        action,
        overrides: overrides,
        handle: (e) {
          if (prompts[e.code] case final p? when asked.add(e.code)) {
            prompt = p;
            return true;
          }
          return take(e) ?? handle?.call(e) ?? false;
        },
      );
      if (ok || prompt == null || !await prompt!()) return ok;
    }
  }
}
