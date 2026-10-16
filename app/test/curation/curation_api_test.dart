import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/curation_api.dart';
import 'package:telinha_segura/family/family.dart';

import '../access/harness.dart' show Harness;
import '../auth/fakes.dart';

const videoJson = {
  'id': 'v1',
  'youtube_id': 'dQw4w9WgXcQ',
  'title': 'Baby Shark',
  'channel_id': 'UC1',
  'channel_title': 'Canal Baby Shark',
  'duration_seconds': 300,
  'state': 'approved',
  'round': 2,
  'theme': 'bichos',
  'min_age_band': '5-8',
  'last_reviewed_at': '2026-10-04T12:00:00Z',
  'review_due_at': '2027-04-02T12:00:00Z',
  'created_at': '2026-10-04T11:00:00Z',
};

final pendingJson = {
  ...videoJson,
  'state': 'pending',
  'round': 1,
  'theme': null,
  'min_age_band': null,
  'last_reviewed_at': null,
  'review_due_at': null,
};

const reviewJson = {
  'display_role': 'pedagogo',
  'decision': 'approve',
  'theme': 'bichos',
  'min_age_band': '5-8',
  'reason': null,
  'reviewed_at': '2026-10-04T12:00:00Z',
};

const rejectionJson = {
  'display_role': 'cuidador',
  'decision': 'reject',
  'theme': null,
  'min_age_band': null,
  'reason': 'Tem propaganda.',
  'reviewed_at': '2026-10-04T12:00:00Z',
};

http.Response contract(http.Request req) =>
    switch ('${req.method} ${req.url.path}') {
      'POST /v1/suggestions' => json(201, pendingJson),
      'GET /v1/suggestions' => json(200, {
        'suggestions': [
          {
            'video_id': 'v1',
            'title': 'Baby Shark',
            'channel_title': 'Canal Baby Shark',
            'state': 'pending',
            'suggested_at': '2026-10-04T12:00:00Z',
          },
        ],
      }),
      'GET /v1/curation/themes' => json(200, {
        'themes': [
          'bichos',
          'musica',
          'historias',
          'aprender',
          'brincar',
          'natureza',
        ],
      }),
      'GET /v1/curation/queue' => json(200, {
        'videos': [
          {...pendingJson, 'revisit': false},
          {...videoJson, 'revisit': true},
        ],
        'next_offset': 50,
      }),
      'GET /v1/curation/videos/v1' => json(200, {
        'video': videoJson,
        'reviews': [reviewJson],
        'provenance': {
          'approvals': {'mae-pai': 1, 'pedagogo': 1},
          'last_reviewed_at': '2026-10-04T12:00:00Z',
        },
      }),
      'POST /v1/curation/videos/v1/reviews' => json(201, {
        'review': reviewJson,
        'video_state': 'approved',
      }),
      _ => http.Response('', 204),
    };

void main() {
  test('every call hits its contract path', () async {
    final t = build(ClientKind.mobile, contract);
    final api = CurationApi(t.client);
    await api.suggest('https://youtu.be/dQw4w9WgXcQ');
    await api.suggestions();
    await api.themes();
    await api.queue();
    await api.queue(offset: 50);
    await api.video('v1');
    await api.approve(
      'v1',
      theme: VideoTheme.bichos,
      minAgeBand: AgeBand.from5To8,
    );
    await api.reject('v1', 'Muito barulhento');
    expect(t.calls, [
      'POST /v1/suggestions {"url":"https://youtu.be/dQw4w9WgXcQ"}',
      'GET /v1/suggestions',
      'GET /v1/curation/themes',
      'GET /v1/curation/queue',
      'GET /v1/curation/queue?offset=50',
      'GET /v1/curation/videos/v1',
      'POST /v1/curation/videos/v1/reviews {"decision":"approve","theme":"bichos","min_age_band":"5-8"}',
      'POST /v1/curation/videos/v1/reviews {"decision":"reject","reason":"Muito barulhento"}',
    ]);
  });

  test('the bodies parse into typed models', () async {
    final api = CurationApi(build(ClientKind.mobile, contract).client);

    final suggested = await api.suggest('https://youtu.be/dQw4w9WgXcQ');
    expect(suggested.created, isTrue);
    expect(suggested.video.state, VideoState.pending);
    expect(suggested.video.theme, isNull);
    expect(suggested.video.minAgeBand, isNull);
    expect(suggested.video.duration, const Duration(minutes: 5));

    final again = await CurationApi(
      build(ClientKind.mobile, (_) => json(200, pendingJson)).client,
    ).suggest('https://youtu.be/dQw4w9WgXcQ');
    expect(again.created, isFalse);
    expect(again.video.id, 'v1');

    final mine = await api.suggestions();
    expect(mine.single.videoId, 'v1');
    expect(mine.single.state, VideoState.pending);
    expect(mine.single.suggestedAt, DateTime.utc(2026, 10, 4, 12));

    expect(await api.themes(), VideoTheme.values.take(6).toList());

    final page = await api.queue();
    expect(page.videos.map((v) => v.revisit), [false, true]);
    expect(page.nextOffset, 50);

    final detail = await api.video('v1');
    expect(detail.video.theme, VideoTheme.bichos);
    expect(detail.video.minAgeBand, AgeBand.from5To8);
    expect(detail.video.reviewDueAt, DateTime.utc(2027, 4, 2, 12));
    expect(detail.reviews.single.displayRole, DisplayRole.pedagogo);
    expect(detail.reviews.single.decision, ReviewDecision.approve);
    expect(detail.provenance!.approvals, {
      DisplayRole.maePai: 1,
      DisplayRole.pedagogo: 1,
    });

    expect(
      await api.approve(
        'v1',
        theme: VideoTheme.bichos,
        minAgeBand: AgeBand.from5To8,
      ),
      VideoState.approved,
    );
  });

  test('every problem code surfaces as an ApiError', () async {
    const codes = {
      'not_curator': 403,
      'not_admin': 403,
      'invalid_link': 422,
      'video_source_unavailable': 503,
      'not_reviewable': 409,
      'already_reviewed': 409,
      'own_suggestion': 403,
      'account_not_found': 404,
      'email_unverified': 409,
      'already_curator': 409,
      'validation': 422,
      'state_conflict': 409,
    };
    for (final MapEntry(key: code, value: status) in codes.entries) {
      final api = CurationApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.suggest('x'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.refusal, 'refusal', isNull),
        ),
      );
    }
  });

  test('a refused video carries its reason', () async {
    for (final reason in RefusalReason.values.where(
      (r) => r != RefusalReason.unknown,
    )) {
      final api = CurationApi(
        build(
          ClientKind.mobile,
          (_) => problem(422, 'video_refused', extra: {'reason': reason.wire}),
        ).client,
      );
      await expectLater(
        api.suggest('x'),
        throwsA(isA<ApiError>().having((e) => e.refusal, 'refusal', reason)),
      );
    }
  });

  test('the suggestion limit surfaces with its wait', () async {
    final api = CurationApi(
      build(
        ClientKind.mobile,
        (_) => problem(429, 'rate_limited', headers: {'retry-after': '3600'}),
      ).client,
    );
    await expectLater(
      api.suggest('x'),
      throwsA(
        isA<ApiError>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(hours: 1),
        ),
      ),
    );
  });

  test(
    'provenance rides with any state; null only if never published',
    () async {
      const provenance = {
        'approvals': {'mae-pai': 2, 'pedagogo': 1},
        'last_reviewed_at': '2026-10-04T12:00:00Z',
      };
      Future<VideoDetail> detail(Map<String, dynamic> video, Object? prov) =>
          CurationApi(
            build(
              ClientKind.mobile,
              (_) => json(200, {
                'video': video,
                'reviews': <Object>[],
                'provenance': prov,
              }),
            ).client,
          ).video('v1');

      for (final state in ['held', 'pending']) {
        final d = await detail({...videoJson, 'state': state}, provenance);
        expect(d.video.state, VideoState.parse(state));
        expect(d.provenance!.approvals, {
          DisplayRole.maePai: 2,
          DisplayRole.pedagogo: 1,
        });
        expect(d.provenance!.lastReviewedAt, DateTime.utc(2026, 10, 4, 12));
      }

      final never = await detail(pendingJson, null);
      expect(never.provenance, isNull);
    },
  );

  test('unknown displayed roles sum their counts instead of overwriting', () {
    final p = Provenance.fromJson({
      'approvals': {'mae-pai': 1, 'xyz': 2, 'abc': 3},
      'last_reviewed_at': '2026-10-04T12:00:00Z',
    });
    expect(p.approvals, {DisplayRole.maePai: 1, DisplayRole.unknown: 5});
  });

  test('the app services build one CurationApi', () {
    expect(Harness().services.curation, isA<CurationApi>());
  });
}
