import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'token_store.dart';

enum ClientKind { web, mobile }

enum AuthStatus { unknown, signedIn, signedOut }

/// Sends API requests with the session credential of the platform.
///
/// - Mobile: a Bearer access token from [TokenStore]. On `unauthenticated`
///   the client refreshes once, sharing one in-flight refresh among
///   concurrent requests, so a refresh token is never presented twice
///   (the server revokes on reuse).
/// - Web: the browser sends the HttpOnly cookie. The CSRF token lives
///   only in memory and is re-fetched from `GET /v1/session` after a
///   reload.
class ApiClient {
  ApiClient({
    required this._baseUrl,
    required this.kind,
    required http.Client httpClient,
    TokenStore? tokens,
  }) : assert(kind == ClientKind.web || tokens != null),
       _http = httpClient,
       _tokens = tokens;

  final ClientKind kind;
  final Uri _baseUrl;
  final http.Client _http;
  final TokenStore? _tokens;
  final ValueNotifier<AuthStatus> status = ValueNotifier(AuthStatus.unknown);

  /// Called on every `403 kid_mode`: this session is locked to a child, so
  /// the app's mode must follow the server's.
  void Function()? onKidMode;

  /// Called on every `403 account_suspended`, before the error is thrown:
  /// the account was suspended, so the app re-reads the session and goes
  /// to the suspended home (suspension screens). A team grant's
  /// `409 account_suspended` is a field error and does not call it.
  void Function()? onSuspended;

  String? _csrf;
  Future<bool>? _refreshing;

  Future<void> saveTokens(Tokens tokens) async {
    await _tokens!.write(tokens);
    status.value = AuthStatus.signedIn;
  }

  void rememberSession({required String csrfToken}) {
    _csrf = csrfToken;
    status.value = AuthStatus.signedIn;
  }

  Future<void> forgetSession() async {
    _csrf = null;
    await _tokens?.clear();
    status.value = AuthStatus.signedOut;
  }

  /// Settles [status] at start-up from what the platform kept.
  ///
  /// - Web: the HttpOnly cookie is invisible here, so `GET /v1/session`
  ///   decides, and its answer seeds the CSRF token.
  /// - Mobile: no stored tokens means signed out, with no request. Stored
  ///   tokens stay signed in unless the server refuses them; an
  ///   unreachable server keeps them (as a failed refresh does).
  Future<void> restoreStatus() async {
    if (kind == ClientKind.mobile && await _tokens!.read() == null) {
      status.value = AuthStatus.signedOut;
      return;
    }
    try {
      final body = await send('GET', '/v1/session') as Map<String, dynamic>;
      if (kind == ClientKind.web) {
        final session = body['session'] as Map<String, dynamic>;
        _csrf = session['csrf_token'] as String?;
      }
      status.value = AuthStatus.signedIn;
    } on ApiError catch (e) {
      if (e.status == 401) {
        await forgetSession();
      } else {
        status.value = kind == ClientKind.mobile
            ? AuthStatus.signedIn
            : AuthStatus.signedOut;
      }
    } on Object {
      status.value = kind == ClientKind.mobile
          ? AuthStatus.signedIn
          : AuthStatus.signedOut;
    }
  }

  /// Returns the decoded JSON body, or null for an empty one. Throws
  /// [ApiError] for any problem response.
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final response = await sendResponse(method, path, body: body, auth: auth);
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  /// Like [send], for a caller that also needs the success status (a 200
  /// and a 201 mean different things). Throws [ApiError] likewise.
  Future<http.Response> sendResponse(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    var response = await _send(method, path, body, auth);
    if (kind == ClientKind.mobile &&
        auth &&
        response.statusCode == 401 &&
        ApiError.fromResponse(response).code == 'unauthenticated') {
      if (await _refreshOnce()) {
        response = await _send(method, path, body, auth);
      } else {
        await forgetSession();
        throw ApiError.fromResponse(response);
      }
    }
    if (kind == ClientKind.web &&
        auth &&
        method != 'GET' &&
        response.statusCode == 403 &&
        ApiError.fromResponse(response).code == 'csrf_failed') {
      // The in-memory token went stale (another tab rotated the session):
      // fetch the current one and retry once; a second refusal surfaces.
      _csrf = await _fetchCsrf();
      response = await _send(method, path, body, auth);
    }
    if (response.statusCode >= 400) {
      final error = ApiError.fromResponse(response);
      if (error.code == 'kid_mode') onKidMode?.call();
      if (error.status == 403 && error.code == 'account_suspended') {
        onSuspended?.call();
      }
      throw error;
    }
    return response;
  }

  /// Sends with [bearer] in place of the session credential: no refresh,
  /// no CSRF token, and a 401 leaves the session alone. A linked child
  /// device uses it with its device token.
  Future<Object?> sendAs(
    String bearer,
    String method,
    String path, {
    Object? body,
  }) async {
    final response = await sendAsResponse(bearer, method, path, body: body);
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  /// Like [sendAs], for a caller that needs the raw response: a
  /// thumbnail's bytes. Throws [ApiError]
  /// likewise.
  Future<http.Response> sendAsResponse(
    String bearer,
    String method,
    String path, {
    Object? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $bearer',
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    final request = http.Request(method, _url(path))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode >= 400) throw ApiError.fromResponse(response);
    return response;
  }

  Future<http.Response> _send(
    String method,
    String path,
    Object? body,
    bool auth,
  ) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (auth && kind == ClientKind.mobile) {
      final tokens = await _tokens!.read();
      if (tokens != null) headers['Authorization'] = 'Bearer ${tokens.access}';
    }
    if (auth && kind == ClientKind.web && method != 'GET') {
      _csrf ??= await _fetchCsrf();
      if (_csrf != null) headers['X-CSRF-Token'] = _csrf!;
    }
    final request = http.Request(method, _url(path))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    return http.Response.fromStream(await _http.send(request));
  }

  /// Appends [path] (with its query) to the base URL's own path, so an API
  /// mounted under a prefix (`https://h/api`) keeps it; `Uri.resolve`
  /// would replace it.
  Uri _url(String path) {
    final relative = Uri.parse(path);
    final prefix = _baseUrl.path.endsWith('/')
        ? _baseUrl.path.substring(0, _baseUrl.path.length - 1)
        : _baseUrl.path;
    return _baseUrl.replace(
      path: '$prefix${relative.path}',
      query: relative.hasQuery ? relative.query : null,
    );
  }

  Future<String?> _fetchCsrf() async {
    final response = await _send('GET', '/v1/session', null, true);
    if (response.statusCode != 200) return null;
    final session =
        (jsonDecode(response.body) as Map<String, dynamic>)['session']
            as Map<String, dynamic>;
    return session['csrf_token'] as String?;
  }

  Future<bool> _refreshOnce() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    final tokens = await _tokens!.read();
    if (tokens == null) return false;
    final response = await _send('POST', '/v1/session/refresh', {
      'refresh_token': tokens.refresh,
    }, false);
    // Only a refused token ends the session; a rate limit, a 5xx or a
    // dropped connection must not sign the user out.
    if (response.statusCode == 400 || response.statusCode == 401) return false;
    if (response.statusCode != 200) throw ApiError.fromResponse(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await saveTokens(
      Tokens(
        access: body['access_token'] as String,
        refresh: body['refresh_token'] as String,
      ),
    );
    return true;
  }
}
