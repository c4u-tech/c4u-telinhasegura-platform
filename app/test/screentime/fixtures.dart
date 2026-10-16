import 'dart:async';

import 'package:http/http.dart' as http;

import '../access/harness.dart';

/// A child's rules as `GET /v1/screentime/minors/:id` answers them.
Map<String, Object?> rulesJson({
  int dailyMinutes = 90,
  String start = '08:00',
  String end = '19:30',
  String zone = 'America/Sao_Paulo',
  bool isDefault = false,
  int usedSeconds = 40 * 60,
  int extension = 0,
  String state = 'ok',
}) => {
  'daily_minutes': dailyMinutes,
  'window_start': start,
  'window_end': end,
  'time_zone': zone,
  'is_default': isDefault,
  'today': {
    'used_seconds': usedSeconds,
    'extension_minutes': extension,
    'state': state,
    if (state != 'ok') 'reason': state == 'time_up' ? 'daily' : 'window',
    'remaining_seconds': 0,
  },
};

/// The last seven days as the server sends them, oldest first, today
/// (2026-10-05, a Monday) last; [minutes] lists them today first.
Map<String, Object?> usageJson([
  List<int> minutes = const [45, 70, 0, 0, 0, 0, 0],
]) => {
  'days': [
    for (var i = 6; i >= 0; i--)
      {
        'date': DateTime.utc(
          2026,
          10,
          5 - i,
        ).toIso8601String().substring(0, 10),
        'seconds': minutes[i] * 60,
      },
  ],
};

/// The screen-time routes: [rules] by child id, with [usage], [extend]
/// and [save] answering the rest. Anything else answers 204.
FutureOr<http.Response> Function(http.Request) screenTimeApi({
  Map<String, FutureOr<http.Response> Function()> rules = const {},
  FutureOr<http.Response> Function()? usage,
  FutureOr<http.Response> Function(http.Request)? extend,
  FutureOr<http.Response> Function(http.Request)? save,
}) => (req) {
  final path = req.url.path;
  const base = '/v1/screentime/minors/';
  if (!path.startsWith(base)) return http.Response('', 204);
  final rest = path.substring(base.length).split('/');
  if (rest.length == 2 && rest[1] == 'usage') {
    return (usage ?? () => json(200, usageJson()))();
  }
  if (rest.length == 2 && rest[1] == 'extend') {
    return (extend ??
        (_) => json(200, {'state': 'ok', 'remaining_seconds': 1800}))(req);
  }
  if (req.method == 'PUT') {
    return (save ?? (_) => json(200, rulesJson()))(req);
  }
  return (rules[rest.first] ?? () => json(200, rulesJson()))();
};
