import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/screentime/kid_time.dart';
import 'package:telinha_segura/screentime/screentime_api.dart';
import 'package:telinha_segura/screentime/time_zone_source.dart';

import '../auth/fakes.dart';

class FixedTimeZone implements TimeZoneSource {
  const FixedTimeZone(this.name);
  final String name;
  @override
  Future<String> current() async => name;
}

const rulesJson = {
  'daily_minutes': 90,
  'window_start': '08:00',
  'window_end': '19:30',
  'time_zone': 'America/Sao_Paulo',
  'is_default': true,
  'today': {
    'used_seconds': 1200,
    'extension_minutes': 15,
    'state': 'ok',
    'remaining_seconds': 5100,
  },
};

http.Response screenTimeContract(http.Request req) {
  final p = req.url.path;
  if (p == '/v1/screentime/minors/m1' && req.method == 'GET') {
    return json(200, rulesJson);
  }
  if (p == '/v1/screentime/minors/m1' && req.method == 'PUT') {
    return json(200, {...rulesJson, 'daily_minutes': 45, 'is_default': false});
  }
  if (p == '/v1/screentime/minors/m1/extend') {
    return json(200, {'state': 'ok', 'remaining_seconds': 1800});
  }
  if (p == '/v1/screentime/minors/m1/usage') {
    return json(200, {
      'days': [
        for (var d = 1; d <= 7; d++) {'date': '2026-10-0$d', 'seconds': d * 60},
      ],
    });
  }
  return problem(404, 'not_found');
}

void main() {
  test('one method per route, the zone from the device', () async {
    final t = build(ClientKind.mobile, screenTimeContract);
    final api = ScreenTimeApi(t.client, const FixedTimeZone('America/Manaus'));

    final rules = await api.rules('m1');
    expect(rules.dailyMinutes, 90);
    expect(rules.windowStart, '08:00');
    expect(rules.isDefault, isTrue);
    expect(rules.today.used, const Duration(minutes: 20));
    expect(rules.today.extensionMinutes, 15);
    expect(rules.today.time.state, KidTimeState.ok);

    final saved = await api.saveRules(
      'm1',
      dailyMinutes: 45,
      windowStart: '07:00',
      windowEnd: '18:00',
    );
    expect(saved.dailyMinutes, 45);
    expect(saved.isDefault, isFalse);

    expect((await api.extend('m1', 30)).remaining, const Duration(minutes: 30));
    final usage = await api.usage('m1');
    expect(usage, hasLength(7));
    expect(usage.last.date, DateTime(2026, 10, 7));
    expect(usage.last.watched, const Duration(minutes: 7));

    expect(t.calls, [
      'GET /v1/screentime/minors/m1',
      'PUT /v1/screentime/minors/m1 {"daily_minutes":45,"window_start":"07:00",'
          '"window_end":"18:00","time_zone":"America/Manaus"}',
      'POST /v1/screentime/minors/m1/extend {"minutes":30}',
      'GET /v1/screentime/minors/m1/usage',
    ]);
  });

  for (final (status, code) in [
    (404, 'not_found'),
    (422, 'over_cap'),
    (422, 'validation'),
  ]) {
    test('a $code surfaces as its ApiError', () async {
      final t = build(ClientKind.mobile, (_) => problem(status, code));
      final api = ScreenTimeApi(t.client, const FixedTimeZone('UTC'));
      await expectLater(
        api.extend('m1', 15),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', code)),
      );
    });
  }
}
