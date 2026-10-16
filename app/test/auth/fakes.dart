import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/auth_api.dart';
import 'package:telinha_segura/auth/token_store.dart';

class MemoryTokenStore implements TokenStore {
  Tokens? tokens;

  @override
  Future<Tokens?> read() async => tokens;

  @override
  Future<void> write(Tokens t) async => tokens = t;

  @override
  Future<void> clear() async => tokens = null;
}

final baseUrl = Uri.parse('https://api.test');

http.Response json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response problem(
  int status,
  String code, {
  List<String>? reasons,
  int? retryAfterBody,
  Map<String, Object> extra = const {},
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode({
    'type': 'urn:telinhasegura:problem:$code',
    'title': 'x',
    'status': status,
    'code': code,
    'reasons': ?reasons,
    'retry_after': ?retryAfterBody,
    ...extra,
  }),
  status,
  headers: {'content-type': 'application/problem+json', ...headers},
);

/// Each call as "METHOD /path?query body": a string, so `expect` compares
/// it by value (records holding Maps would compare by identity).
({AuthApi api, ApiClient client, List<String> calls, MemoryTokenStore store})
build(
  ClientKind kind,
  http.Response Function(http.Request) answer, {
  bool seedCsrf = true,
  List<http.Request>? seen,
}) {
  final calls = <String>[];
  final store = MemoryTokenStore();
  final client = ApiClient(
    baseUrl: baseUrl,
    kind: kind,
    tokens: kind == ClientKind.mobile ? store : null,
    httpClient: MockClient((req) async {
      final path = req.url.toString().substring(baseUrl.toString().length);
      seen?.add(req);
      calls.add('${req.method} $path ${req.body}'.trimRight());
      return answer(req);
    }),
  );
  if (kind == ClientKind.web && seedCsrf) {
    client.rememberSession(csrfToken: 'c');
  }
  return (api: AuthApi(client), client: client, calls: calls, store: store);
}

http.Response noContent(http.Request _) => http.Response('', 204);
