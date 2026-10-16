/// The identity providers the API accepts; [name] is the wire value.
enum IdentityProvider { google, apple }

/// How a guardian may confirm linking a provider to an existing account.
enum LinkOption {
  password('password'),
  clearPassword('clear_password');

  const LinkOption(this.wire);

  final String wire;
}

/// The outcome of offering a provider ID token to the API.
sealed class ProviderSignInResult {
  const ProviderSignInResult();
}

/// The identity was linked; the session is stored.
final class SignedIn extends ProviderSignInResult {
  const SignedIn();
}

/// No account has this email: confirm the adult declaration with [ticket].
final class SignupRequired extends ProviderSignInResult {
  const SignupRequired({required this.ticket, required this.email});

  final String ticket;
  final String email;
}

/// An account has this email: confirm the link with [ticket], using one of
/// [options].
final class LinkRequired extends ProviderSignInResult {
  const LinkRequired({
    required this.ticket,
    required this.email,
    required this.options,
  });

  final String ticket;
  final String email;
  final Set<LinkOption> options;
}
