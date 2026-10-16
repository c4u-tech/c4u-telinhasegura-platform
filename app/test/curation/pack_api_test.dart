import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/curation_api.dart';
import 'package:telinha_segura/curation/pack.dart';

import '../auth/fakes.dart';

const packJson = {
  'id': 'p1',
  'state': 'approved',
  'round': 2,
  'theme': 'bichos',
  'title': 'Bichos e musica',
  'cover_video_id': 'v2',
  'composer_role': 'pedagogo',
  'videos': [
    {
      'id': 'v1',
      'title': 'Baby Shark',
      'duration_seconds': 300,
      'state': 'approved',
    },
    {'id': 'v2', 'title': 'Galinha', 'duration_seconds': 240, 'state': 'held'},
    {'id': 'v3', 'title': 'Sapo', 'duration_seconds': 180, 'state': 'approved'},
  ],
  'total_seconds': 720,
  'reviews': [
    {
      'display_role': 'cuidador',
      'decision': 'reject',
      'reason': 'Muito longo.',
      'reviewed_at': '2026-10-06T12:00:00Z',
    },
  ],
  'reviewable': false,
  'provenance': {
    'approvals': {'mae-pai': 1, 'pedagogo': 1},
    'last_reviewed_at': '2026-10-05T12:00:00Z',
  },
};

http.Response packContract(http.Request req) =>
    switch ('${req.method} ${req.url.path}') {
      'POST /v1/curation/packs' => json(201, {
        ...packJson,
        'state': 'pending',
        'round': 1,
        'theme': null,
        'reviews': <Object>[],
        'reviewable': false,
        'provenance': null,
      }),
      'PUT /v1/curation/packs/p1' => json(200, packJson),
      'GET /v1/curation/packs' => json(200, {
        'packs': [packJson],
        'has_more': true,
      }),
      'GET /v1/curation/packs/p1' => json(200, packJson),
      'POST /v1/curation/packs/p1/reviews' => json(201, {
        'review': {
          'display_role': 'mae-pai',
          'decision': 'approve',
          'reason': null,
          'reviewed_at': '2026-10-06T12:00:00Z',
        },
        'state': 'approved',
      }),
      _ => http.Response('', 204),
    };

void main() {
  test('every pack call hits its contract path', () async {
    final t = build(ClientKind.mobile, packContract);
    final api = CurationApi(t.client);
    await api.composePack(
      title: 'Bichos e musica',
      videoIds: ['v1', 'v2', 'v3'],
      coverVideoId: 'v2',
      theme: VideoTheme.bichos,
    );
    await api.composePack(title: 'Sapos', videoIds: ['v1', 'v2', 'v3']);
    await api.recomposePack('p1', title: 'Sapos', videoIds: ['v3', 'v2', 'v1']);
    await api.packs();
    await api.packs(offset: 50);
    await api.pack('p1');
    await api.approvePack('p1');
    await api.rejectPack('p1', 'Muito longo.');
    await api.removePack('a/b');

    expect(t.calls, [
      'POST /v1/curation/packs {"title":"Bichos e musica","video_ids":["v1","v2","v3"],"cover_video_id":"v2","theme":"bichos"}',
      'POST /v1/curation/packs {"title":"Sapos","video_ids":["v1","v2","v3"]}',
      'PUT /v1/curation/packs/p1 {"title":"Sapos","video_ids":["v3","v2","v1"]}',
      'GET /v1/curation/packs',
      'GET /v1/curation/packs?offset=50',
      'GET /v1/curation/packs/p1',
      'POST /v1/curation/packs/p1/reviews {"decision":"approve"}',
      'POST /v1/curation/packs/p1/reviews {"decision":"reject","reason":"Muito longo."}',
      'POST /v1/admin/packs/a%2Fb/remove',
    ]);
  });

  test('pack bodies parse into typed models', () async {
    final api = CurationApi(build(ClientKind.mobile, packContract).client);

    final composed = await api.composePack(
      title: 'Bichos e musica',
      videoIds: ['v1', 'v2', 'v3'],
    );
    expect(composed.state, PackState.pending);
    expect(composed.round, 1);
    expect(composed.theme, isNull);
    expect(composed.reviews, isEmpty);
    expect(composed.provenance, isNull);

    final p = await api.pack('p1');
    expect(p.id, 'p1');
    expect(p.state, PackState.approved);
    expect(p.round, 2);
    expect(p.theme, VideoTheme.bichos);
    expect(p.title, 'Bichos e musica');
    expect(p.coverVideoId, 'v2');
    expect(p.composerRole, DisplayRole.pedagogo);
    expect(p.videos.map((v) => v.id), ['v1', 'v2', 'v3']);
    expect(p.videos.first.duration, const Duration(minutes: 5));
    expect(p.videos[1].state, VideoState.held);
    expect(p.total, const Duration(minutes: 12));
    expect(p.reviews.single.displayRole, DisplayRole.cuidador);
    expect(p.reviews.single.decision, ReviewDecision.reject);
    expect(p.reviews.single.reason, 'Muito longo.');
    expect(p.reviews.single.reviewedAt, DateTime.utc(2026, 10, 6, 12));
    expect(p.reviewable, isFalse);
    expect(p.provenance!.approvals, {
      DisplayRole.maePai: 1,
      DisplayRole.pedagogo: 1,
    });

    final page = await api.packs();
    expect(page.hasMore, isTrue);
    expect(page.packs.single.id, 'p1');

    expect(await api.approvePack('p1'), PackState.approved);
  });

  test('an unknown pack state reads as unknown', () {
    expect(
      Pack.fromJson({...packJson, 'state': 'arquivado'}).state,
      PackState.unknown,
    );
  });

  test('every pack problem code surfaces as an ApiError', () async {
    const codes = {
      'validation': 422,
      'not_found': 404,
      'not_reviewable': 409,
      'already_reviewed': 409,
      'own_composition': 403,
      'state_conflict': 409,
      'not_curator': 403,
      'not_admin': 403,
      'reauth_required': 403,
    };
    for (final MapEntry(key: code, value: status) in codes.entries) {
      final api = CurationApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.approvePack('p1'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.packInvalid, 'packInvalid', isNull),
        ),
      );
    }
  });

  test('pack_invalid carries its reason', () async {
    for (final reason in PackInvalidReason.values.where(
      (r) => r != PackInvalidReason.unknown,
    )) {
      final api = CurationApi(
        build(
          ClientKind.mobile,
          (_) => problem(422, 'pack_invalid', extra: {'reason': reason.wire}),
        ).client,
      );
      await expectLater(
        api.composePack(title: 'x', videoIds: ['v1']),
        throwsA(
          isA<ApiError>().having((e) => e.packInvalid, 'packInvalid', reason),
        ),
      );
    }
    final newer = CurationApi(
      build(
        ClientKind.mobile,
        (_) => problem(422, 'pack_invalid', extra: {'reason': 'novo'}),
      ).client,
    );
    await expectLater(
      newer.composePack(title: 'x', videoIds: ['v1']),
      throwsA(
        isA<ApiError>().having(
          (e) => e.packInvalid,
          'packInvalid',
          PackInvalidReason.unknown,
        ),
      ),
    );
  });
}
