import '../auth/api_client.dart';

/// A family session a guardian started: its id and the second the work
/// resumes at.
class FamilySessionStart {
  const FamilySessionStart({
    required this.sessionId,
    required this.startSeconds,
  });

  factory FamilySessionStart.fromJson(Map<String, dynamic> j) =>
      FamilySessionStart(
        sessionId: j['session_id'] as String,
        startSeconds: (j['start_seconds'] as num?)?.floor() ?? 0,
      );

  final String sessionId;
  final int startSeconds;
}

/// Starts a long work the child watches with the family, behind the
/// parents' PIN. Problems surface as `ApiError`: `invalid_pin`,
/// `rate_limited` (with its wait), `pin_not_set`, `video_not_allowed`,
/// `time_up` (with its reason), `does_not_fit` (with the
/// `remaining_seconds` left), `over_cap`, `consent_required`, `not_found`.
class FamilySessionApi {
  FamilySessionApi(this._client);

  final ApiClient _client;

  /// Opens a session for [videoId]; [extendMinutes] adds time to the day
  /// in the same call, for a work longer than what is left.
  Future<FamilySessionStart> start({
    required String minorId,
    required String videoId,
    required String pin,
    int? extendMinutes,
  }) async => FamilySessionStart.fromJson(
    await _client.send(
      'POST',
      '/v1/family/minors/${Uri.encodeComponent(minorId)}/sessions',
      body: {'video_id': videoId, 'pin': pin, 'extend_minutes': ?extendMinutes},
    ) as Map<String, dynamic>,
  );
}
