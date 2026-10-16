import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../auth/api_error.dart';
import '../auth/auth_api.dart';
import 'child_api.dart';
import 'kid_mode_mark.dart';
import 'parental.dart';
import 'parental_api.dart';

/// Who the app is in front of. The server is the source of truth: a
/// shared device's kid mode is a lock on the session, a linked device's
/// is its device credential.
sealed class AppMode {
  const AppMode();
}

final class Guardian extends AppMode {
  const Guardian();

  @override
  bool operator ==(Object other) => other is Guardian;

  @override
  int get hashCode => (Guardian).hashCode;

  @override
  String toString() => 'Guardian()';
}

/// A guardian's device handed over to a child; [minorId] is null once
/// that child was deleted.
final class SharedKid extends AppMode {
  const SharedKid(this.minorId);

  final String? minorId;

  @override
  bool operator ==(Object other) =>
      other is SharedKid && other.minorId == minorId;

  @override
  int get hashCode => Object.hash(SharedKid, minorId);

  @override
  String toString() => 'SharedKid($minorId)';
}

/// A signed-in session that is not locked on a device that was in kid
/// mode: the guardian area waits for the PIN.
final class PinRequired extends AppMode {
  const PinRequired();

  @override
  bool operator ==(Object other) => other is PinRequired;

  @override
  int get hashCode => (PinRequired).hashCode;

  @override
  String toString() => 'PinRequired()';
}

/// A child's own linked device; [minorId] is null while the server is
/// unreachable.
final class LinkedDevice extends AppMode {
  const LinkedDevice(this.minorId);

  final String? minorId;

  @override
  bool operator ==(Object other) =>
      other is LinkedDevice && other.minorId == minorId;

  @override
  int get hashCode => Object.hash(LinkedDevice, minorId);

  @override
  String toString() => 'LinkedDevice($minorId)';
}

/// Refuses to link a device that holds a guardian session, so a linked
/// device never holds a guardian account.
class SignedInDevice implements Exception {
  const SignedInDevice();
}

/// The app's mode and the moves between modes. The router
/// consumes it.
class AppModeModel extends ChangeNotifier {
  AppModeModel({
    required this._auth,
    required this._parental,
    required this._child,
    required this._client,
    required this._mark,
  }) {
    _client.onKidMode = _resync;
    _client.status.addListener(_onStatus);
  }

  final AuthApi _auth;
  final ParentalApi _parental;
  final ChildApi _child;
  final ApiClient _client;
  final KidModeMark _mark;

  AppMode? _mode;

  /// Null until [restore] settles it.
  AppMode? get mode => _mode;

  void _set(AppMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }

  @visibleForTesting
  void restoreAs(AppMode mode) => _set(mode);

  /// Settles the mode at start-up, after `ApiClient.restoreStatus`.
  ///
  /// - A stored device credential: a linked device, even offline; a
  ///   refused credential falls back to the guardian mode.
  /// - Otherwise a signed-in session's `kid_mode` decides. A failed read
  ///   leaves the mode unknown and rethrows, so the shell can retry rather
  ///   than open the guardian area to a child.
  Future<void> restore() async {
    if (await _child.isLinked()) {
      try {
        _set(LinkedDevice((await _child.profile()).id));
      } on ApiError catch (e) {
        _set(e.status == 401 ? const Guardian() : const LinkedDevice(null));
      } on Object {
        _set(const LinkedDevice(null));
      }
      return;
    }
    if (_client.status.value != AuthStatus.signedIn) {
      _set(const Guardian());
      return;
    }
    final session = await _auth.currentSession();
    final kid = session.kidMode;
    if (kid != null) {
      await _enterKid(session.accountId, kid.minorId);
    } else {
      _set(
        (await _mark.read()).isNotEmpty
            ? const PinRequired()
            : const Guardian(),
      );
    }
  }

  /// [accountId] joins the mark before the mode moves, so a crash in
  /// between cannot leave a kid mode without it; no other account
  /// leaves it.
  Future<void> _enterKid(String accountId, String? minorId) async {
    await _mark.add(accountId);
    _set(SharedKid(minorId));
  }

  Future<void> handOver(String minorId) async {
    final accountId = (await _auth.currentSession()).accountId;
    await _parental.handOver(minorId);
    await _enterKid(accountId, minorId);
  }

  Future<void> unlock(String pin) async {
    // Read first: a family-less unlock ends the session.
    final accountId = (await _auth.currentSession()).accountId;
    await _child.unlock(pin);
    await _mark.remove(accountId);
    _set(const Guardian());
  }

  /// Gives the PIN a sign-in on a kid-mode device owes. A family
  /// without a PIN has none to give; any other
  /// refusal keeps the PIN screen and surfaces. The account removes only
  /// itself from the mark: another account's entry stays.
  Future<void> verifyPin(String pin) async {
    try {
      await _parental.verifyPin(pin);
    } on ApiError catch (e) {
      if (e.code != 'no_family' && e.code != 'pin_not_set') rethrow;
    }
    final accountId = (await _auth.currentSession()).accountId;
    await _mark.remove(accountId);
    _set(const Guardian());
  }

  Future<Profile> redeem({required String code, required String label}) async {
    if (_client.status.value == AuthStatus.signedIn) {
      throw const SignedInDevice();
    }
    final p = await _child.redeem(code: code, label: label);
    _set(LinkedDevice(p.id));
    return p;
  }

  Future<Profile> profile() => _linked(_child.profile);

  Future<List<Profile>> listProfiles(String pin) =>
      _linked(() => _child.profiles(pin));

  Future<Profile> switchProfile({
    required String pin,
    required String minorId,
  }) async {
    final p = await _linked(
      () => _child.switchProfile(pin: pin, minorId: minorId),
    );
    _set(LinkedDevice(p.id));
    return p;
  }

  /// A linked device's 401 means it was unlinked or expired; `ChildApi`
  /// already forgot the credential, and the device is no longer a child's.
  Future<T> _linked<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiError catch (e) {
      if (e.status == 401 && _mode is LinkedDevice) _set(const Guardian());
      rethrow;
    }
  }

  Future<void> _resync() async {
    try {
      final session = await _auth.currentSession();
      final kid = session.kidMode;
      if (kid != null) await _enterKid(session.accountId, kid.minorId);
    } on Object {
      // The next guardian call refuses again and resyncs.
    }
  }

  bool _gating = false;

  void _onStatus() {
    final status = _client.status.value;
    if (status == AuthStatus.signedOut &&
        (_gating || _mode is SharedKid || _mode is PinRequired)) {
      _gating = false;
      _set(const Guardian()); // the mark stays: the next sign-in asks the PIN
    } else if (status == AuthStatus.signedIn) {
      final before = _mode;
      if (before == null || before is SharedKid || before is LinkedDevice) {
        return; // before restore settles the mode, restore decides
      }
      // Unknown, never the guardian area, until the mark is read.
      _gating = true;
      _mode = null;
      notifyListeners();
      unawaited(_gateSignIn());
    }
  }

  /// A sign-in on a device that was in kid mode asks the PIN. A
  /// mark that cannot be read fails closed. A hand-over or a sign-out in
  /// the meantime wins.
  Future<void> _gateSignIn() async {
    bool marked;
    try {
      marked = (await _mark.read()).isNotEmpty;
    } on Object {
      marked = true;
    }
    if (!_gating) return;
    _gating = false;
    if (_mode != null) return; // a hand-over or resync won
    _set(marked ? const PinRequired() : const Guardian());
  }

  @override
  void dispose() {
    _client.status.removeListener(_onStatus);
    if (_client.onKidMode == _resync) _client.onKidMode = null;
    super.dispose();
  }
}
