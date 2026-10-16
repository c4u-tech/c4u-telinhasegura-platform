import 'dart:convert';

import 'package:http/http.dart' as http;

/// An RFC 9457 problem from the API. Screens switch on [code], never on
/// [status] or the title.
class ApiError implements Exception {
  const ApiError({
    required this.status,
    required this.code,
    this.reasons = const [],
    this.retryAfter,
    this.details = const {},
  });

  factory ApiError.fromResponse(http.Response response) {
    final headerSeconds = int.tryParse(response.headers['retry-after'] ?? '');
    final retryAfter = headerSeconds == null
        ? null
        : Duration(seconds: headerSeconds);
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // Browsers hide Retry-After unless exposed by CORS; the body mirrors it.
      final bodySeconds = body['retry_after'];
      return ApiError(
        status: response.statusCode,
        code: body['code'] as String? ?? 'unknown',
        reasons:
            (body['reasons'] as List<dynamic>?)?.cast<String>() ?? const [],
        retryAfter:
            retryAfter ??
            (bodySeconds is int ? Duration(seconds: bodySeconds) : null),
        details: body,
      );
    } on Object {
      return ApiError(
        status: response.statusCode,
        code: 'unknown',
        retryAfter: retryAfter,
      );
    }
  }

  final int status;
  final String code;
  final List<String> reasons;
  final Duration? retryAfter;

  /// The whole problem body, for codes that carry data (tickets).
  final Map<String, dynamic> details;

  @override
  String toString() => 'ApiError($status, $code)';
}
