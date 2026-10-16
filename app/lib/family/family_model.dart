import 'dart:async';

import 'package:flutter/foundation.dart';

import '../access/copy.dart';
import '../auth/api_client.dart';
import '../auth/api_error.dart';
import '../auth/auth_api.dart';
import 'family.dart';
import 'family_api.dart';

/// What the family area shows for the signed-in account.
sealed class FamilyState {
  const FamilyState();
}

final class FamilyLoading extends FamilyState {
  const FamilyLoading();
}

final class FamilyReady extends FamilyState {
  const FamilyReady(this.family);

  final Family family;
}

/// The first use: the account belongs to no family. [invitations] are the
/// pending invitations to its email, read after this state shows; empty
/// until then, or when that read fails.
final class NoFamily extends FamilyState {
  const NoFamily([this.invitations = const []]);

  final List<ReceivedInvitation> invitations;
}

/// The family waits on a confirmed email; [email] is where to resend.
final class EmailUnverified extends FamilyState {
  const EmailUnverified(this.email);

  final String email;
}

/// The first read failed (network or 5xx); `refresh` retries.
final class FamilyFailed extends FamilyState {
  const FamilyFailed();
}

/// The caller's family, read once and shared by every family screen.
/// Screens write through [FamilyApi] and then [refresh]; a problem that
/// ends the family area goes to [absorb]. Signing out forgets it all.
class FamilyModel extends ChangeNotifier {
  FamilyModel({
    required this._auth,
    required this._api,
    required ValueListenable<AuthStatus> status,
  }) {
    status.addListener(() {
      if (status.value == AuthStatus.signedOut) _reset();
    });
  }

  final AuthApi _auth;
  final FamilyApi _api;

  FamilyState _state = const FamilyLoading();
  String? _email;
  String? _accountId;
  Set<PlatformRole>? _roles;
  AccountStatus _status = AccountStatus.active;
  bool _verified = false;
  Future<void>? _reading;
  bool _read = false;
  String? _notice;
  bool _rise = false;
  int _account = 0;

  FamilyState get state => _state;

  /// The signed-in account's email, once read.
  String? get email => _email;

  /// The signed-in account's id, once read: the team sheet tells the
  /// caller's own roles apart by it.
  String? get accountId => _accountId;

  /// The account's platform roles as its session was last read; null
  /// until then. The home's role doors and the curator, moderator and
  /// admin routes follow them;
  /// the server still decides.
  Set<PlatformRole>? get roles => _roles;

  /// Whether the account is suspended, as its session was last read
  /// (suspension screens): the home becomes the suspended
  /// home and the router keeps to its routes. False until read.
  bool get suspended => _status == AccountStatus.suspended;

  /// A call answered `403 account_suspended`: the account is
  /// taken as suspended at once, so the router goes home, and the session
  /// is read again after any read in flight, which may predate it.
  Future<void> accountSuspended() async {
    _status = AccountStatus.suspended;
    notifyListeners();
    await _reading;
    await refresh();
  }

  /// The calm line the family home shows once, saying why the caller was
  /// sent there: the family lost on another screen, or an owner's
  /// action refused because ownership passed elsewhere.
  String? get notice => _notice;

  /// The [notice], cleared as the home takes it.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  /// Reads the account and the family once; later calls reuse them.
  Future<void> load() => _read ? _reading ?? Future.value() : refresh();

  /// Reads the session and the family again. A failure keeps a family
  /// already shown.
  Future<void> refresh() {
    _read = true;
    return _reading ??= _readAll().whenComplete(() => _reading = null);
  }

  Future<void> _readAll() async {
    // A sign-out while reading makes the answer someone else's.
    final account = _account;
    if (_state is! FamilyReady) _set(const FamilyLoading());
    try {
      // Every read reads the session, so a suspension or a reinstatement
      // shows on the next one (suspension screens).
      final session = await _auth.currentSession();
      if (account != _account) return;
      _email = session.email;
      _accountId = session.accountId;
      _roles = session.roles;
      _status = session.status;
      _verified = session.emailVerified;
      if (!_verified) return _set(EmailUnverified(session.email));
      final family = await _api.load();
      if (account == _account) _set(FamilyReady(family));
    } on Object catch (e) {
      if (account != _account) return;
      if (absorb(e, notice: _state is FamilyReady)) return;
      if (_state is! FamilyReady) _set(const FamilyFailed());
    }
  }

  /// Starts the caller's family, the caller as its owner. Throws
  /// the `ApiError` the screen words, after showing the verify prompt
  /// for `email_unverified`.
  Future<void> create() async {
    final account = _account;
    try {
      final family = await _api.create();
      if (account != _account) return;
      _set(FamilyReady(family));
    } on ApiError catch (e) {
      if (account != _account) rethrow;
      // Started elsewhere meanwhile: show the family the account has.
      if (e.code == 'already_in_family') return refresh();
      absorb(e);
      rethrow;
    }
  }

  /// Takes the pending invitation [id]: the
  /// home greets the family with the rise, as after the emailed link.
  /// Throws the `ApiError` the screen words; `invitation_unavailable` and
  /// `limit_reached` read the list again first.
  Future<void> acceptById(String id) async {
    final account = _account;
    try {
      final family = await _api.acceptInvitationById(id);
      if (account != _account) return;
      joined(family);
    } on ApiError catch (e) {
      if (account != _account) rethrow;
      if (e.code == 'already_in_family') return refresh();
      if (e.code == 'invitation_unavailable' || e.code == 'limit_reached') {
        await _readInvitations();
      }
      absorb(e);
      rethrow;
    }
  }

  /// Takes the problems that end the family area wherever they arrive:
  /// `no_family` (removed, or the family deleted)
  /// and `email_unverified`. Returns whether it took
  /// [error]; the router then leaves the family screens.
  bool absorb(Object error, {bool notice = true}) {
    if (error is! ApiError) return false;
    switch (error.code) {
      case 'no_family':
        _notice = notice ? Copy.forError(error) : null;
        _set(const NoFamily());
        unawaited(_readInvitations());
        return true;
      case 'email_unverified':
        _verified = false;
        _set(EmailUnverified(_email ?? ''));
        return true;
    }
    return false;
  }

  /// Reads the invitations a no-family account may take. The answer is
  /// dropped once the state left the first use or the account changed,
  /// and a failure keeps the plain first use.
  /// A suspended account's session cannot read them, so nothing
  /// is asked (suspension screens).
  Future<void> _readInvitations() async {
    if (suspended) return;
    final account = _account;
    try {
      final invitations = await _api.pendingInvitations();
      if (account == _account && _state is NoFamily) {
        _set(NoFamily(invitations));
      }
    } on Object {
      // The first use stays as it is: the emailed link still works.
    }
  }

  /// An owner's action answered `not_owner` [error]: the family is read
  /// again and, the caller no longer its owner, the router leaves the
  /// owner's screen for the home, which says why.
  Future<void> notOwner(ApiError error) async {
    _notice = Copy.forError(error);
    await refresh();
    if (_state case FamilyReady(:final family)
        when family.role == FamilyRole.owner) {
      _notice = null;
    }
  }

  /// A staff call answered `not_curator`, `not_admin` or `not_moderator`
  /// [error]: the role goes at once, so its door goes and its routes send
  /// home, where the copy shows; then the session is read again.
  /// `not_moderator` means the account
  /// holds neither moderator nor admin (a moderation route accepts either),
  /// so both go; curator stays. `not_staff`, from the MFA routes, means
  /// no role is left: all go, and the notice is the one of the highest
  /// role held. Any other code is left alone.
  Future<void> roleLost(ApiError error) async {
    final held = _roles ?? const {};
    final code = switch (error.code) {
      'not_staff' when held.contains(PlatformRole.admin) => 'not_admin',
      'not_staff' when held.contains(PlatformRole.moderator) => 'not_moderator',
      'not_staff' => 'not_curator',
      final code => code,
    };
    final lost = switch (error.code) {
      'not_staff' => PlatformRole.values.toSet(),
      'not_curator' => {PlatformRole.curator},
      'not_admin' => {PlatformRole.admin},
      'not_moderator' => {PlatformRole.moderator, PlatformRole.admin},
      _ => null,
    };
    if (lost == null) return;
    final account = _account;
    _notice = Copy.forError(ApiError(status: error.status, code: code));
    _roles = {...?_roles}..removeAll(lost);
    notifyListeners();
    try {
      final session = await _auth.currentSession();
      if (account != _account) return;
      _roles = session.roles;
      _status = session.status;
      notifyListeners();
    } on Object {
      // The role stays dropped: the server already said so.
    }
  }

  /// The caller left or deleted the family on purpose.
  void left() {
    _notice = null;
    _set(const NoFamily());
    unawaited(_readInvitations());
  }

  /// An accepted invitation: the family home greets it with the rise.
  void joined(Family family) {
    _rise = true;
    _set(FamilyReady(family));
  }

  /// Whether the home should play "o sol sobe", once.
  bool takeRise() {
    final rise = _rise;
    _rise = false;
    return rise;
  }

  void _set(FamilyState state) {
    _state = state;
    notifyListeners();
  }

  void _reset() {
    _account++;
    _state = const FamilyLoading();
    _email = null;
    _accountId = null;
    _roles = null;
    _status = AccountStatus.active;
    _verified = false;
    _read = false;
    _notice = null;
    _rise = false;
    notifyListeners();
  }
}
