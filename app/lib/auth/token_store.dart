/// The mobile session's credentials. Web keeps its session in an
/// HttpOnly cookie that Dart never sees.
class Tokens {
  const Tokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

abstract interface class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}
