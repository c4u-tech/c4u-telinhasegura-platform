import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/family/family_session_api.dart';

import '../auth/fakes.dart';

void main() {
  test('a session starts with the video, the PIN and the extension', () async {
    final t = build(
      ClientKind.mobile,
      (_) => json(201, {'session_id': 's1', 'start_seconds': 754}),
    );
    final api = FamilySessionApi(t.client);

    final started = await api.start(
      minorId: 'm1',
      videoId: 'v1',
      pin: '2580',
      extendMinutes: 30,
    );
    expect(started.sessionId, 's1');
    expect(started.startSeconds, 754);

    final plain = await api.start(minorId: 'm1', videoId: 'v1', pin: '2580');
    expect(plain.startSeconds, 754);

    expect(t.calls, [
      'POST /v1/family/minors/m1/sessions '
          '{"video_id":"v1","pin":"2580","extend_minutes":30}',
      'POST /v1/family/minors/m1/sessions {"video_id":"v1","pin":"2580"}',
    ]);
  });

  test('a session missing its start reads as from the beginning', () async {
    final t = build(ClientKind.mobile, (_) => json(201, {'session_id': 's1'}));
    final started = await FamilySessionApi(t.client)
        .start(minorId: 'm1', videoId: 'v1', pin: '2580');
    expect(started.startSeconds, 0);
  });

  test('does_not_fit surfaces with what is left of the day', () async {
    final t = build(
      ClientKind.mobile,
      (_) => problem(403, 'does_not_fit', extra: {'remaining_seconds': 1800}),
    );
    await expectLater(
      FamilySessionApi(t.client)
          .start(minorId: 'm1', videoId: 'v1', pin: '2580'),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'does_not_fit')
            .having(
              (e) => e.details['remaining_seconds'],
              'remaining_seconds',
              1800,
            ),
      ),
    );
  });

  for (final (status, code) in [
    (403, 'invalid_pin'),
    (403, 'video_not_allowed'),
    (409, 'pin_not_set'),
    (422, 'over_cap'),
    (403, 'consent_required'),
    (404, 'not_found'),
  ]) {
    test('a $code surfaces as its ApiError', () async {
      final t = build(ClientKind.mobile, (_) => problem(status, code));
      await expectLater(
        FamilySessionApi(t.client)
            .start(minorId: 'm1', videoId: 'v1', pin: '2580'),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', code)),
      );
    });
  }

  test('rate_limited carries the wait; time_up its reason', () async {
    final limited = build(
      ClientKind.mobile,
      (_) => problem(429, 'rate_limited', retryAfterBody: 60),
    );
    await expectLater(
      FamilySessionApi(limited.client)
          .start(minorId: 'm1', videoId: 'v1', pin: '0000'),
      throwsA(
        isA<ApiError>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 60),
        ),
      ),
    );

    final up = build(
      ClientKind.mobile,
      (_) => problem(403, 'time_up', extra: {'reason': 'window'}),
    );
    await expectLater(
      FamilySessionApi(up.client).start(minorId: 'm1', videoId: 'v1', pin: '1'),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'time_up')
            .having((e) => e.details['reason'], 'reason', 'window'),
      ),
    );
  });
}
