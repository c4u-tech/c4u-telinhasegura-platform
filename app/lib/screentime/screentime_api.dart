import '../auth/api_client.dart';
import 'kid_time.dart';
import 'time_zone_source.dart';

/// A child's day as a guardian reads it.
class ScreenTimeToday {
  const ScreenTimeToday({
    required this.used,
    required this.extensionMinutes,
    required this.time,
  });

  factory ScreenTimeToday.fromJson(Map<String, dynamic> j) => ScreenTimeToday(
    used: Duration(seconds: j['used_seconds'] as int),
    extensionMinutes: j['extension_minutes'] as int,
    time: KidTime.fromJson(j),
  );

  final Duration used;
  final int extensionMinutes;
  final KidTime time;
}

/// A child's rules: daily minutes and the window `[windowStart,
/// windowEnd)` as `HH:MM` in the family's zone.
class ScreenTimeRules {
  const ScreenTimeRules({
    required this.dailyMinutes,
    required this.windowStart,
    required this.windowEnd,
    required this.timeZone,
    required this.isDefault,
    required this.today,
  });

  factory ScreenTimeRules.fromJson(Map<String, dynamic> j) => ScreenTimeRules(
    dailyMinutes: j['daily_minutes'] as int,
    windowStart: j['window_start'] as String,
    windowEnd: j['window_end'] as String,
    timeZone: j['time_zone'] as String,
    isDefault: j['is_default'] as bool,
    today: ScreenTimeToday.fromJson(j['today'] as Map<String, dynamic>),
  );

  final int dailyMinutes;
  final String windowStart;
  final String windowEnd;
  final String timeZone;

  /// No rules saved: the band's default.
  final bool isDefault;
  final ScreenTimeToday today;
}

/// What a child watched on one local date.
class DayUsage {
  const DayUsage({required this.date, required this.watched});

  factory DayUsage.fromJson(Map<String, dynamic> j) => DayUsage(
    date: DateTime.parse(j['date'] as String),
    watched: Duration(seconds: j['seconds'] as int),
  );

  final DateTime date;
  final Duration watched;
}

/// The guardian side of screen time, one method per route.
/// Problems surface as `ApiError`: a minor outside the caller's family
/// answers `not_found`, an extension past 240 minutes `over_cap`, bad
/// input `validation`.
class ScreenTimeApi {
  ScreenTimeApi(this._client, this._zone);

  final ApiClient _client;
  final TimeZoneSource _zone;

  static String _path(String minorId) =>
      '/v1/screentime/minors/${Uri.encodeComponent(minorId)}';

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async =>
      await _client.send(method, path, body: body) as Map<String, dynamic>;

  Future<ScreenTimeRules> rules(String minorId) async =>
      ScreenTimeRules.fromJson(await _json('GET', _path(minorId)));

  /// Saves the rules, sending the device's zone: the family's on its
  /// first save, ignored after.
  Future<ScreenTimeRules> saveRules(
    String minorId, {
    required int dailyMinutes,
    required String windowStart,
    required String windowEnd,
  }) async => ScreenTimeRules.fromJson(
    await _json(
      'PUT',
      _path(minorId),
      body: {
        'daily_minutes': dailyMinutes,
        'window_start': windowStart,
        'window_end': windowEnd,
        'time_zone': await _zone.current(),
      },
    ),
  );

  /// 15, 30 or 60 more minutes today, which also open the window.
  Future<KidTime> extend(String minorId, int minutes) async => KidTime.fromJson(
    await _json('POST', '${_path(minorId)}/extend', body: {'minutes': minutes}),
  );

  /// The last seven local days, oldest first, today last.
  Future<List<DayUsage>> usage(String minorId) async => [
    for (final d
        in (await _json('GET', '${_path(minorId)}/usage'))['days']
            as List<dynamic>)
      DayUsage.fromJson(d as Map<String, dynamic>),
  ];
}
