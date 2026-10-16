import 'api_client.dart';
import 'api_error.dart';
import 'provider_sign_in.dart';
import 'token_store.dart';

/// A platform role, independent
/// of the family role: the admin, curator and moderation areas open only
/// for it.
enum PlatformRole {
  admin,
  curator,
  moderator;

  /// The known roles in [wire]. An unknown role is skipped, and a missing
  /// or null list reads as none.
  static Set<PlatformRole> parseAll(Object? wire) => {
    if (wire is List)
      for (final r in wire)
        for (final v in values)
          if (v.name == r) v,
  };
}

/// An account's standing: a suspended account's
/// session reaches only its export, its erasure and signing out.
enum AccountStatus {
  active,
  suspended;

  /// An unknown or missing status reads as active. The server refuses
  /// what a suspended session cannot reach, whatever the app believes.
  static AccountStatus parse(Object? wire) =>
      wire == 'suspended' ? suspended : active;
}

class CurrentSession {
  const CurrentSession({
    required this.accountId,
    required this.email,
    required this.emailVerified,
    required this.sessionId,
    this.kidMode,
    this.roles = const {},
    this.status = AccountStatus.active,
  });

  final String accountId;
  final String email;
  final bool emailVerified;
  final String sessionId;

  /// Set while this session is locked to a child; `minorId` is null once
  /// that child was deleted.
  final ({String? minorId})? kidMode;

  /// The account's platform roles; empty for a guardian without one.
  final Set<PlatformRole> roles;

  /// The account's standing; `suspended` until an admin reinstates it.
  final AccountStatus status;
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.client,
    required this.deviceLabel,
    required this.createdAt,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  final String id;
  final String client;
  final String deviceLabel;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool isCurrent;
}

/// The guardian auth contract, one method per endpoint.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  Future<void> signUp({
    required String email,
    required String password,
    required bool adultDeclaration,
  }) => _client.send(
    'POST',
    '/v1/accounts',
    auth: false,
    body: {
      'email': email,
      'password': password,
      'adult_declaration': adultDeclaration,
    },
  );

  Future<void> resendVerification(String email) => _client.send(
    'POST',
    '/v1/email-verifications',
    auth: false,
    body: {'email': email},
  );

  Future<void> confirmEmail(String token) => _client.send(
    'POST',
    '/v1/email-verifications/confirm',
    auth: false,
    body: {'token': token},
  );

  Future<void> signIn({
    required String email,
    required String password,
    String deviceLabel = '',
  }) => _startSession('/v1/sessions', {
    'email': email,
    'password': password,
  }, deviceLabel);

  /// Offers a provider ID token. Signup and link confirmations come back
  /// as results, not errors; every other problem throws [ApiError].
  Future<ProviderSignInResult> signInWithProvider(
    IdentityProvider provider,
    String idToken, {
    String deviceLabel = '',
  }) => _providerSession('/v1/sessions/provider', {
    'provider': provider.name,
    'id_token': idToken,
  }, deviceLabel);

  /// Confirms a signup ticket. If an account took the ticket's email
  /// meanwhile, the answer is a [LinkRequired] with a new ticket.
  Future<ProviderSignInResult> completeProviderSignup(
    String ticket, {
    required bool adultDeclaration,
    String deviceLabel = '',
  }) => _providerSession('/v1/sessions/provider/signup', {
    'ticket': ticket,
    'adult_declaration': adultDeclaration,
  }, deviceLabel);

  /// Starts a session, turning a 409 confirmation into a result.
  Future<ProviderSignInResult> _providerSession(
    String path,
    Map<String, Object?> fields,
    String deviceLabel,
  ) async {
    try {
      await _startSession(path, fields, deviceLabel);
      return const SignedIn();
    } on ApiError catch (e) {
      final ticket = e.details['ticket'] as String?;
      final email = e.details['email'] as String?;
      if (ticket == null || email == null) rethrow;
      switch (e.code) {
        case 'signup_required':
          return SignupRequired(ticket: ticket, email: email);
        case 'link_required':
          final wires =
              (e.details['options'] as List<dynamic>?)?.cast<String>() ??
              const <String>[];
          return LinkRequired(
            ticket: ticket,
            email: email,
            options: {
              for (final o in LinkOption.values)
                if (wires.contains(o.wire)) o,
            },
          );
      }
      rethrow;
    }
  }

  Future<void> linkProvider(
    String ticket, {
    required String password,
    String deviceLabel = '',
  }) => _startSession('/v1/sessions/provider/link', {
    'ticket': ticket,
    'password': password,
  }, deviceLabel);

  /// Links while removing the account's password and ending every other
  /// session: the choice that evicts whoever set that password.
  Future<void> linkProviderClearingPassword(
    String ticket, {
    String deviceLabel = '',
  }) => _startSession('/v1/sessions/provider/link', {
    'ticket': ticket,
    'clear_password': true,
  }, deviceLabel);

  /// Every sign-in endpoint answers alike: tokens on mobile, the CSRF
  /// token on the web.
  Future<void> _startSession(
    String path,
    Map<String, Object?> fields,
    String deviceLabel,
  ) async {
    final body = await _client.send(
      'POST',
      path,
      auth: false,
      body: {
        ...fields,
        'client': _client.kind.name,
        'device_label': deviceLabel,
      },
    ) as Map<String, dynamic>;
    if (_client.kind == ClientKind.mobile) {
      await _client.saveTokens(
        Tokens(
          access: body['access_token'] as String,
          refresh: body['refresh_token'] as String,
        ),
      );
    } else {
      _client.rememberSession(csrfToken: body['csrf_token'] as String);
    }
  }

  Future<CurrentSession> currentSession() async {
    final body =
        await _client.send('GET', '/v1/session') as Map<String, dynamic>;
    final account = body['account'] as Map<String, dynamic>;
    final session = body['session'] as Map<String, dynamic>;
    final kid = body['kid_mode'] as Map<String, dynamic>?;
    return CurrentSession(
      accountId: account['id'] as String,
      email: account['email'] as String,
      emailVerified: account['email_verified'] as bool,
      sessionId: session['id'] as String,
      kidMode: kid == null ? null : (minorId: kid['minor_id'] as String?),
      roles: PlatformRole.parseAll(body['roles']),
      status: AccountStatus.parse(account['status']),
    );
  }

  /// Forgets the local session even if the server cannot be reached.
  /// Ends the session, and forgets it even when the server fails or is
  /// unreachable. A session in kid mode is refused (`403 kid_mode`) and
  /// kept: only the PIN leaves kid mode.
  Future<void> signOut() async {
    var forget = true;
    try {
      await _client.send('DELETE', '/v1/session');
    } on ApiError catch (e) {
      forget = e.code != 'kid_mode';
      rethrow;
    } finally {
      if (forget) await _client.forgetSession();
    }
  }

  Future<void> reauthenticate(String password) =>
      _client.send('POST', '/v1/session/reauth', body: {'password': password});

  Future<void> reauthenticateWithProvider(
    IdentityProvider provider,
    String idToken,
  ) => _client.send(
    'POST',
    '/v1/session/reauth',
    body: {'provider': provider.name, 'id_token': idToken},
  );

  Future<List<SessionSummary>> listSessions() async {
    final body =
        await _client.send('GET', '/v1/sessions') as Map<String, dynamic>;
    return [
      for (final s
          in (body['sessions'] as List<dynamic>).cast<Map<String, dynamic>>())
        SessionSummary(
          id: s['id'] as String,
          client: s['client'] as String,
          deviceLabel: s['device_label'] as String,
          createdAt: DateTime.parse(s['created_at'] as String),
          lastSeenAt: DateTime.parse(s['last_seen_at'] as String),
          isCurrent: s['current'] as bool,
        ),
    ];
  }

  Future<void> revokeSession(String id) =>
      _client.send('DELETE', '/v1/sessions/${Uri.encodeComponent(id)}');

  /// Ends the other sessions, or every session including this one.
  Future<void> revokeSessions({required bool includeCurrent}) async {
    await _client.send(
      'DELETE',
      '/v1/sessions?scope=${includeCurrent ? 'all' : 'others'}',
    );
    if (includeCurrent) await _client.forgetSession();
  }

  Future<void> changePassword({
    required String current,
    required String next,
  }) => _client.send(
    'POST',
    '/v1/account/password',
    body: {'current_password': current, 'new_password': next},
  );

  Future<void> requestEmailChange(String newEmail) =>
      _client.send('POST', '/v1/account/email', body: {'new_email': newEmail});

  Future<void> requestPasswordReset(String email) => _client.send(
    'POST',
    '/v1/password-resets',
    auth: false,
    body: {'email': email},
  );

  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) => _client.send(
    'POST',
    '/v1/password-resets/confirm',
    auth: false,
    body: {'token': token, 'new_password': newPassword},
  );
}
