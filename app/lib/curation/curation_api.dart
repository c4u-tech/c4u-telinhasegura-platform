import 'dart:convert';

import '../auth/api_client.dart';
import '../family/family.dart' show AgeBand;
import 'curation.dart';
import 'pack.dart';

/// The curation contract, one method per route.
/// Problems surface as `ApiError`; a `video_refused` carries its
/// `refusal`. Pacotinhos compose, review and come down through the pack
/// methods; a broken composition surfaces as `pack_invalid` with its
/// `packInvalid` reason. The curator routes answer `not_curator` and the
/// admin ones `not_admin` to a session without the role. The team's
/// routes are `StaffApi`'s.
class CurationApi {
  CurationApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async =>
      await _client.send(method, path, body: body) as Map<String, dynamic>;

  static String _id(String id) => Uri.encodeComponent(id);

  /// The list every review answers, with its version.
  Future<Checklist> checklist() async =>
      Checklist.fromJson(await _json('GET', '/v1/curation/checklist'));

  /// The curator terms in force; every other curator route answers
  /// `declaration_required` until they are accepted.
  Future<CuratorTerms> declaration() async =>
      CuratorTerms.fromJson(await _json('GET', '/v1/curation/declaration'));

  /// Accepts the terms of [version], the one shown; another answers
  /// `declaration_outdated`.
  Future<CuratorTerms> acceptDeclaration(String version) async =>
      CuratorTerms.fromJson(
        await _json(
          'POST',
          '/v1/curation/declaration',
          body: {'version': version},
        ),
      );

  /// Suggests a YouTube link; the video, and whether this suggestion
  /// created it (201) or it was already in the catalogue (200).
  Future<({Video video, bool created})> suggest(String url) async {
    final r = await _client.sendResponse(
      'POST',
      '/v1/suggestions',
      body: {'url': url},
    );
    return (
      video: Video.fromJson(jsonDecode(r.body) as Map<String, dynamic>),
      created: r.statusCode == 201,
    );
  }

  Future<List<Suggestion>> suggestions() async => [
    for (final s
        in (await _json('GET', '/v1/suggestions'))['suggestions']
            as List<dynamic>)
      Suggestion.fromJson(s as Map<String, dynamic>),
  ];

  Future<List<VideoTheme>> themes() async => [
    for (final t
        in (await _json('GET', '/v1/curation/themes'))['themes']
            as List<dynamic>)
      VideoTheme.parse(t),
  ];

  /// The calling curator's queue, oldest first, 50 at a time. Offsets
  /// shift as reviewed videos leave the caller's queue, so after a review
  /// refetch from offset 0 rather than resuming at `nextOffset`.
  Future<QueuePage> queue({int offset = 0}) async => QueuePage.fromJson(
    await _json(
      'GET',
      offset == 0 ? '/v1/curation/queue' : '/v1/curation/queue?offset=$offset',
    ),
  );

  Future<VideoDetail> video(String id) async => VideoDetail.fromJson(
    await _json('GET', '/v1/curation/videos/${_id(id)}'),
  );

  /// Approves with every answer of the checklist [version]; the video's
  /// state after the review. A doubt, or an answer that asks for the team,
  /// holds the video instead, with [note].
  /// Refused with `checklist_outdated`, `checklist_refuses`,
  /// `checklist_band`, `checklist_invalid_reason` or `conflict_of_interest`.
  Future<VideoState> approve(
    String id, {
    required VideoTheme theme,
    required AgeBand minAgeBand,
    required String version,
    required Map<String, ChecklistAnswer> answers,
    String? note,
  }) => _review(id, {
    'decision': 'approve',
    'theme': theme.wire,
    'min_age_band': minAgeBand.wire,
    'checklist_version': version,
    'answers': {for (final e in answers.entries) e.key: e.value.wire},
    'note': ?note,
  });

  /// Rejects with a reason of 1 to 500 characters; the video is held.
  Future<VideoState> reject(String id, String reason) =>
      _review(id, {'decision': 'reject', 'reason': reason});

  Future<VideoState> _review(String id, Map<String, Object> body) async =>
      VideoState.parse(
        (await _json(
          'POST',
          '/v1/curation/videos/${_id(id)}/reviews',
          body: body,
        ))['video_state'],
      );

  static Map<String, Object> _composition(
    String title,
    List<String> videoIds,
    String? coverVideoId,
    VideoTheme? theme,
  ) => {
    'title': title,
    'video_ids': videoIds,
    'cover_video_id': ?coverVideoId,
    'theme': ?theme?.wire,
  };

  /// Composes a pacotinho of 3 to 5 approved videos; it waits for other
  /// curators' approvals.
  Future<Pack> composePack({
    required String title,
    required List<String> videoIds,
    String? coverVideoId,
    VideoTheme? theme,
  }) async => Pack.fromJson(
    await _json(
      'POST',
      '/v1/curation/packs',
      body: _composition(title, videoIds, coverVideoId, theme),
    ),
  );

  /// Opens a new round with this composition; an approved pacotinho keeps
  /// playing its published one until the new round is approved.
  Future<Pack> recomposePack(
    String id, {
    required String title,
    required List<String> videoIds,
    String? coverVideoId,
    VideoTheme? theme,
  }) async => Pack.fromJson(
    await _json(
      'PUT',
      '/v1/curation/packs/${_id(id)}',
      body: _composition(title, videoIds, coverVideoId, theme),
    ),
  );

  /// Every pacotinho that is not removed, 50 at a time.
  Future<PackPage> packs({int offset = 0}) async => PackPage.fromJson(
    await _json(
      'GET',
      offset == 0 ? '/v1/curation/packs' : '/v1/curation/packs?offset=$offset',
    ),
  );

  Future<Pack> pack(String id) async =>
      Pack.fromJson(await _json('GET', '/v1/curation/packs/${_id(id)}'));

  /// The approved videos of [theme], by title, 50 at a time: what a
  /// pacotinho is composed from.
  Future<QueuePage> approvedVideos(VideoTheme theme, {int offset = 0}) async =>
      QueuePage.fromJson(
        await _json(
          'GET',
          offset == 0
              ? '/v1/curation/videos?theme=${theme.wire}'
              : '/v1/curation/videos?theme=${theme.wire}&offset=$offset',
        ),
      );

  Future<PackLimits> packLimits() async =>
      PackLimits.fromJson(await _json('GET', '/v1/curation/packs/limits'));

  /// Approves the current round; the pacotinho's state after the review.
  Future<PackState> approvePack(String id) =>
      _reviewPack(id, {'decision': 'approve'});

  /// Rejects with a reason of 1 to 500 characters.
  Future<PackState> rejectPack(String id, String reason) =>
      _reviewPack(id, {'decision': 'reject', 'reason': reason});

  Future<PackState> _reviewPack(String id, Map<String, Object> body) async =>
      PackState.parse(
        (await _json(
          'POST',
          '/v1/curation/packs/${_id(id)}/reviews',
          body: body,
        ))['state'],
      );

  /// Every pacotinho that is not removed, for an admin who need not be a
  /// curator; never reviewable from here.
  Future<PackPage> adminPacks({int offset = 0}) async => PackPage.fromJson(
    await _json(
      'GET',
      offset == 0 ? '/v1/admin/packs' : '/v1/admin/packs?offset=$offset',
    ),
  );

  Future<Pack> adminPack(String id) async =>
      Pack.fromJson(await _json('GET', '/v1/admin/packs/${_id(id)}'));

  /// Takes a pacotinho down for good; needs a re-authentication within
  /// 5 minutes.
  Future<void> removePack(String id) =>
      _client.send('POST', '/v1/admin/packs/${_id(id)}/remove');
}
