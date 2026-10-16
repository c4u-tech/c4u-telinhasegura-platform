import 'dart:async';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import '../access/harness.dart' show json, problem;
import '../family/fixtures.dart';

/// A guardian catalogue item as the API answers it.
Map<String, Object?> familyItem(
  String id,
  String title, {
  String theme = 'bichos',
  String channel = 'Ciência Pequena',
  int seconds = 360,
  bool hidden = false,
  Map<String, int>? approvals = const {'mae-pai': 2, 'pedagogo': 1},
  int reviewedDaysAgo = 3,
}) => {
  'id': id,
  'youtube_id': 'yt-$id',
  'title': title,
  'channel_title': channel,
  'duration_seconds': seconds,
  'theme': theme,
  'min_age_band': 'ate-4',
  'hidden': hidden,
  'provenance': approvals == null
      ? null
      : {
          'approvals': approvals,
          'last_reviewed_at': clock
              .now()
              .subtract(Duration(days: reviewedDaysAgo))
              .toUtc()
              .toIso8601String(),
        },
};

/// A pacotinho of a child's catalogue as the API answers it:
/// [videos] as (id, title, seconds, hidden), in order.
Map<String, Object?> packItem(
  String id,
  String title, {
  String? cover,
  String composer = 'pedagogo',
  required List<(String, String, int, bool)> videos,
  Map<String, int> approvals = const {'mae-pai': 2, 'pedagogo': 1},
  int reviewedDaysAgo = 3,
}) => {
  'id': id,
  'title': title,
  'cover_video_id': cover ?? videos.first.$1,
  'composer_role': composer,
  'videos': [
    for (final (vid, vtitle, seconds, hidden) in videos)
      {
        'id': vid,
        'title': vtitle,
        'duration_seconds': seconds,
        'hidden': hidden,
      },
  ],
  'provenance': {
    'approvals': approvals,
    'last_reviewed_at': clock
        .now()
        .subtract(Duration(days: reviewedDaysAgo))
        .toUtc()
        .toIso8601String(),
  },
};

/// Lia's pacotinhos today: four videos in one, and one of three with the
/// second skipped for her.
final liaPacks = [
  packItem(
    'k1',
    'Bichos da fazenda',
    cover: 'p2',
    videos: [
      ('p1', 'A galinha e os pintinhos', 240, false),
      ('p2', 'O sapo que pulava alto', 360, false),
      ('p3', 'Vaca amarela', 300, false),
      ('p4', 'O cavalo e a ponte', 180, false),
    ],
  ),
  packItem(
    'k2',
    'Hora de dormir',
    composer: 'mae-pai',
    approvals: const {'pedagogo': 2},
    videos: [
      ('d1', 'A lua e o sono', 300, false),
      ('d2', 'Gatinhos no quintal', 240, true),
      ('d3', 'Canção de ninar', 420, false),
    ],
  ),
];

/// One page of a child's catalogue, with [packs] on it.
http.Response page(
  List<Map<String, Object?>> videos, {
  bool more = false,
  List<Map<String, Object?>> packs = const [],
}) => json(200, {'videos': videos, 'has_more': more, 'packs': packs});

/// Lia's catalogue: two Bichos, one hidden, and one Música.
final liaVideos = [
  familyItem('v1', 'O sapo que pulava alto'),
  familyItem(
    'v2',
    'Gatinhos no quintal',
    channel: 'Canal X',
    seconds: 240,
    hidden: true,
  ),
  familyItem('v3', 'A canção das cores', theme: 'musica', seconds: 150),
];

/// The family's catalogue routes: [catalog] answers each read by minor
/// and offset (Lia's one page by default), [write] every hide, unhide
/// and report, and thumbnails answer two JPEG bytes unless [thumb] says
/// otherwise.
FutureOr<http.Response> Function(http.Request) catalogApi({
  FutureOr<http.Response> Function(String minorId, int offset)? catalog,
  FutureOr<http.Response> Function(http.Request)? write,
  FutureOr<http.Response> Function(String videoId)? thumb,
}) => (req) {
  final p = req.url.path;
  final read = RegExp(r'^/v1/family/minors/([^/]+)/catalog$').firstMatch(p);
  if (read != null) {
    final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
    return (catalog ?? (_, _) => page(liaVideos))(read.group(1)!, offset);
  }
  if (p.startsWith('/v1/family/thumbs/')) {
    final id = p.substring('/v1/family/thumbs/'.length);
    return (thumb ??
        (_) => http.Response.bytes(
          [0xFF, 0xD8],
          200,
          headers: {'content-type': 'image/jpeg'},
        ))(id);
  }
  if (write != null) return write(req);
  if (p == '/v1/reports') return http.Response('', 201);
  if (p.contains('/hidden/')) return http.Response('', 204);
  return problem(404, 'not_found');
};

/// Lia (5 to 8), Téo (up to 4) and Nina (9 to 12).
final threeChildren = familyWith([
  minorJson('m1', 'Lia'),
  minorJson('m2', 'Téo', avatar: 'owl', ageBand: 'ate-4'),
  minorJson('m3', 'Nina', avatar: 'cat', ageBand: '9-12'),
]);

/// Lia's catalogue with her pacotinhos on its first page.
http.Response withPacks(String _, int offset) =>
    page(liaVideos, packs: offset == 0 ? liaPacks : const []);
