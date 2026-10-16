import 'dart:async';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import '../access/harness.dart';
import '../staff/accounts_api_test.dart' show sheetJson;
import 'curation_api_test.dart' show pendingJson;

/// [line] as the curation screens print it: a non-breaking space before
/// each dot and inside each duration, so neither breaks at 200 % text.
String nb(String line) => line
    .replaceAll(' · ', '\u00A0· ')
    .replaceAllMapped(RegExp(r'(\d+) (h|min)\b'), (m) => '${m[1]}\u00A0${m[2]}')
    .replaceAllMapped(RegExp(r'(\u00A0h) (\d)'), (m) => '${m[1]}\u00A0${m[2]}');

/// One of the guardian's suggestions as the wire carries it, suggested
/// [daysAgo] calendar days before the test's clock.
Map<String, Object?> suggestionJson(
  String id,
  String title, {
  String channel = 'Canal Bichos',
  String state = 'pending',
  int daysAgo = 0,
}) => {
  'video_id': id,
  'title': title,
  'channel_title': channel,
  'state': state,
  'suggested_at': clock
      .now()
      .subtract(Duration(days: daysAgo))
      .toUtc()
      .toIso8601String(),
};

/// The suggestion routes: [suggestions] answers the list (an empty one by
/// default), [suggest] the form's `POST` (a new video by default).
FutureOr<http.Response> Function(http.Request) suggestionApi({
  FutureOr<http.Response> Function()? suggestions,
  FutureOr<http.Response> Function(http.Request)? suggest,
}) =>
    (req) => switch ('${req.method} ${req.url.path}') {
      'GET /v1/suggestions' =>
        suggestions?.call() ?? json(200, {'suggestions': <Object>[]}),
      'POST /v1/suggestions' => suggest?.call(req) ?? json(201, pendingJson),
      _ => http.Response('', 204),
    };

/// One queued video as the wire carries it: pending, round 1, 4 minutes
/// long unless said otherwise.
Map<String, Object?> queuedJson(
  String id,
  String title, {
  String channel = 'Canal Bichos',
  int seconds = 240,
  bool revisit = false,
}) => {
  ...pendingJson,
  'id': id,
  'youtube_id': 'yt-$id',
  'title': title,
  'channel_title': channel,
  'duration_seconds': seconds,
  if (revisit) ...{
    'state': 'approved',
    'round': 2,
    'theme': 'bichos',
    'min_age_band': '5-8',
    'last_reviewed_at': '2026-03-03T12:00:00Z',
  },
  'revisit': revisit,
};

/// One page of the queue; [next] is the next page's offset.
http.Response queuePage(List<Map<String, Object?>> videos, {int? next}) =>
    json(200, {'videos': videos, 'next_offset': next});

/// One video's review detail: [video] and this round's [reviews].
http.Response detailOf(
  Map<String, Object?> video, {
  List<Map<String, Object?>> reviews = const [],
}) => json(200, {'video': video, 'reviews': reviews, 'provenance': null});

/// The curator's routes: [queue] answers each queue read (an empty page
/// by default), [video] the review's read of one video (the queued
/// "Baby Shark" by default), [review] each review sent (a held video by
/// default).
FutureOr<http.Response> Function(http.Request) curatorApi({
  FutureOr<http.Response> Function(http.Request)? queue,
  FutureOr<http.Response> Function(String id)? video,
  FutureOr<http.Response> Function(http.Request)? review,
}) => (req) {
  final path = req.url.path;
  const videos = '/v1/curation/videos/';
  if (req.method == 'GET' && path == '/v1/curation/queue') {
    return queue?.call(req) ?? queuePage([]);
  }
  if (req.method == 'POST' && path.endsWith('/reviews')) {
    return review?.call(req) ?? json(201, {'video_state': 'held'});
  }
  if (req.method == 'GET' && path.startsWith(videos)) {
    final id = Uri.decodeComponent(path.substring(videos.length));
    return video?.call(id) ??
        detailOf(queuedJson(id, 'Baby Shark', channel: 'Canal Baby Shark'));
  }
  return http.Response('', 204);
};

/// One held video as the wire carries it: [video] with its [rejections],
/// [reason] and reports by reason with their [notes].
Map<String, Object?> heldOf(
  Map<String, Object?> video, {
  List<Map<String, Object?>> rejections = const [],
  String? reason = 'review',
  Map<String, int> reports = const {},
  List<String> notes = const [],
}) => {
  'video': {...video, 'state': 'held'},
  'rejections': rejections,
  'held_reason': ?reason,
  'reports': {'by_reason': reports, 'notes': notes},
};

/// The held videos' list.
http.Response heldList(List<Map<String, Object?>> videos) =>
    json(200, {'videos': videos});

/// A curator's role as the staff routes carry it: a verified pedagogue
/// unless said otherwise.
Map<String, Object?> curatorRole({
  String role = 'pedagogo',
  bool verified = true,
  String at = '2026-03-03T12:00:00Z',
}) => {
  'role': 'curator',
  'granted_at': at,
  'display_role': role,
  'verified_professional': verified,
};

Map<String, Object?> moderatorRole({String at = '2026-04-10T12:00:00Z'}) => {
  'role': 'moderator',
  'granted_at': at,
};

Map<String, Object?> adminRole({String at = '2026-01-01T12:00:00Z'}) => {
  'role': 'admin',
  'granted_at': at,
};

/// One team member as the staff routes carry it.
Map<String, Object?> memberOf(
  String id,
  String email,
  List<Map<String, Object?>> roles,
) => {'account_id': id, 'email': email, 'roles': roles};

/// The caller's own row: the harness's account, an admin.
final selfMember = memberOf('a', 'ana@example.com', [adminRole()]);

/// The team's list.
http.Response staffList(List<Map<String, Object?>> staff) =>
    json(200, {'staff': staff});

/// The platform's totals as `GET /v1/admin/metrics` answers them, three
/// suppressed.
const metricsJson = <String, Object?>{
  'accounts': 1240,
  'families': 412,
  'minors': null,
  'active_devices': 38,
  'published_videos': 12500,
  'published_packs': null,
  'reports_7d': null,
  'suppressed_below': 5,
};

/// One page of the staff audit log.
http.Response auditPage(List<Map<String, Object?>> actions, {int? next}) =>
    json(200, {'actions': actions, 'next_offset': next});

/// The admin's routes: [staff] answers each team read (the caller, an
/// admin, then bia, a curator, by default), [grant] the appoint, [revise]
/// a curator's change (bia as read), [revoke] a role's removal (bia with
/// none left); and the moderation routes: [held] each held list read
/// (none by default), [settle] a held video's `reopen` or `remove`; and
/// the account directory's: [metrics] each totals read ([metricsJson] by
/// default), [audit] each audit log page (empty by default), [lookup]
/// each search ([sheetJson] by default) and [support] each support
/// action on a sheet (by default [sheetJson] with its sessions gone after
/// a revoke, its devices after an unlink, as it was after a reset).
FutureOr<http.Response> Function(http.Request) adminApi({
  FutureOr<http.Response> Function()? staff,
  FutureOr<http.Response> Function(http.Request)? grant,
  FutureOr<http.Response> Function(http.Request)? revise,
  FutureOr<http.Response> Function(http.Request)? revoke,
  FutureOr<http.Response> Function()? held,
  FutureOr<http.Response> Function(http.Request)? settle,
  FutureOr<http.Response> Function()? metrics,
  FutureOr<http.Response> Function(http.Request)? audit,
  FutureOr<http.Response> Function(http.Request)? lookup,
  FutureOr<http.Response> Function(http.Request)? support,
}) => (req) {
  final path = req.url.path;
  const accounts = '/v1/admin/accounts/';
  if (req.method == 'POST' && path == '${accounts}lookup') {
    return lookup?.call(req) ?? json(200, sheetJson);
  }
  if (req.method == 'POST' && path.startsWith(accounts)) {
    return support?.call(req) ??
        json(200, {
          ...sheetJson,
          if (path.endsWith('/sessions/revoke')) 'sessions': <Object>[],
          if (path.endsWith('/unlink')) 'devices': <Object>[],
        });
  }
  if (req.method == 'GET' && path == '/v1/admin/metrics') {
    return metrics?.call() ?? json(200, metricsJson);
  }
  if (req.method == 'GET' && path == '/v1/admin/audit') {
    return audit?.call(req) ?? auditPage([]);
  }
  const staffPath = '/v1/admin/staff';
  if (path == staffPath) {
    if (req.method == 'GET') {
      return staff?.call() ??
          staffList([
            selfMember,
            memberOf('a2', 'bia@example.com', [curatorRole()]),
          ]);
    }
    return grant?.call(req) ??
        json(201, memberOf('a3', 'caio@example.com', [moderatorRole()]));
  }
  if (path.startsWith('$staffPath/')) {
    if (req.method == 'PATCH') {
      return revise?.call(req) ??
          json(200, memberOf('a2', 'bia@example.com', [curatorRole()]));
    }
    return revoke?.call(req) ??
        json(200, memberOf('a2', 'bia@example.com', []));
  }
  if (req.method == 'GET' && path == '/v1/moderation/videos') {
    return held?.call() ?? heldList([]);
  }
  if (path.startsWith('/v1/moderation/videos/')) {
    return settle?.call(req) ?? http.Response('', 204);
  }
  return http.Response('', 204);
};

/// One pacotinho video as the curator routes carry it: approved, 4
/// minutes long unless said otherwise.
Map<String, Object?> packVideoJson(
  String id,
  String title, {
  String channel = 'Canal Bichos',
  int seconds = 240,
  String state = 'approved',
}) => {
  'id': id,
  'title': title,
  'channel_title': channel,
  'duration_seconds': seconds,
  'state': state,
};

/// One pacotinho as the curator routes carry it: pending in round 1,
/// composed by a mãe ou pai, of three 4-minute videos unless said
/// otherwise.
Map<String, Object?> packOf(
  String id,
  String title, {
  String state = 'pending',
  int round = 1,
  bool reviewable = false,
  String? theme,
  String composer = 'mae-pai',
  List<Map<String, Object?>>? videos,
  List<Map<String, Object?>> reviews = const [],
  Map<String, Object?>? provenance,
}) {
  final vs =
      videos ??
      [
        packVideoJson('v1', 'Galinha Pintadinha'),
        packVideoJson('v2', 'Sapo Cururu'),
        packVideoJson('v3', 'Pato Pateta'),
      ];
  return {
    'id': id,
    'state': state,
    'round': round,
    'theme': theme,
    'title': title,
    'cover_video_id': vs.first['id'],
    'composer_role': composer,
    'videos': vs,
    'total_seconds': vs.fold<int>(
      0,
      (t, v) => t + (v['duration_seconds']! as int),
    ),
    'reviews': reviews,
    'reviewable': reviewable,
    'provenance': provenance,
  };
}

/// One page of pacotinhos.
http.Response packPage(
  List<Map<String, Object?>> packs, {
  bool hasMore = false,
}) => json(200, {'packs': packs, 'has_more': hasMore});

/// The pacotinho routes, curator and admin alike: [list] answers each
/// list read (an empty page by default), [pack] each read of one ("Hora
/// do banho", reviewable, by default), [videos] each picker read (none
/// by default), [limits] the limits (3 to 5, 20 min), [write] every
/// `POST` or `PUT` (the pack as composed by default). Thumbnails are not
/// found, so covers stand hollow.
FutureOr<http.Response> Function(http.Request) packApi({
  FutureOr<http.Response> Function(http.Request)? list,
  FutureOr<http.Response> Function(String id)? pack,
  FutureOr<http.Response> Function(http.Request)? videos,
  FutureOr<http.Response> Function()? limits,
  FutureOr<http.Response> Function(http.Request)? write,
}) => (req) {
  final path = req.url.path;
  if (req.method == 'GET') {
    if (path == '/v1/curation/packs' || path == '/v1/admin/packs') {
      return list?.call(req) ?? packPage([]);
    }
    if (path == '/v1/curation/packs/limits') {
      return limits?.call() ??
          json(200, {'min_videos': 3, 'max_videos': 5, 'max_seconds': 1200});
    }
    if (path == '/v1/curation/videos') {
      return videos?.call(req) ?? queuePage([]);
    }
    const one = '/v1/curation/videos/';
    if (path.startsWith(one)) {
      final id = Uri.decodeComponent(path.substring(one.length));
      return detailOf(queuedJson(id, 'Sapo Cururu', channel: 'Canal Sapo'));
    }
    for (final prefix in ['/v1/curation/packs/', '/v1/admin/packs/']) {
      if (path.startsWith(prefix)) {
        final id = Uri.decodeComponent(path.substring(prefix.length));
        return pack?.call(id) ??
            json(200, packOf(id, 'Hora do banho', reviewable: true));
      }
    }
    if (path.startsWith('/v1/family/thumbs/')) return http.Response('', 404);
  }
  if (req.method == 'POST' || req.method == 'PUT') {
    return write?.call(req) ?? json(201, packOf('p9', 'Hora do banho'));
  }
  return http.Response('', 204);
};
