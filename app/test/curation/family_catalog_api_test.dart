import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/family_catalog_api.dart';
import 'package:telinha_segura/family/family.dart';

import '../access/harness.dart' show Harness;
import '../auth/fakes.dart';
import 'curation_api_test.dart' show rejectionJson, videoJson;

const familyVideoJson = {
  'id': 'v1',
  'youtube_id': 'XqZsoesa55w',
  'title': 'Baby Shark',
  'channel_title': 'Canal Baby Shark',
  'duration_seconds': 300,
  'theme': 'bichos',
  'min_age_band': 'ate-4',
  'hidden': true,
  'provenance': {
    'approvals': {'mae-pai': 2, 'pedagogo': 1},
    'last_reviewed_at': '2026-10-04T12:00:00Z',
  },
};

http.Response familyContract(http.Request req) {
  final p = req.url.path;
  if (p.endsWith('/catalog')) {
    return json(200, {
      'videos': [familyVideoJson],
      'has_more': true,
    });
  }
  if (p.startsWith('/v1/family/thumbs/')) {
    return http.Response.bytes(
      [0xFF, 0xD8],
      200,
      headers: {'content-type': 'image/jpeg'},
    );
  }
  if (p == '/v1/reports') return http.Response('', 201);
  return http.Response('', 204);
}

void main() {
  test('every call hits its contract path', () async {
    final t = build(ClientKind.mobile, familyContract);
    final api = FamilyCatalogApi(t.client);

    await api.minorCatalog('m1');
    await api.minorCatalog('m1', offset: 50);
    await api.hide('m1', 'v1');
    await api.unhide('m1', 'v1');
    await api.report('v1', ReportReason.assustador, note: 'Tem um monstro.');
    await api.report('v1', ReportReason.outro);
    await api.thumbnail('a/b');

    expect(t.calls, [
      'GET /v1/family/minors/m1/catalog?offset=0',
      'GET /v1/family/minors/m1/catalog?offset=50',
      'PUT /v1/family/minors/m1/hidden/v1',
      'DELETE /v1/family/minors/m1/hidden/v1',
      'POST /v1/reports {"video_id":"v1","reason":"assustador","note":"Tem um monstro."}',
      'POST /v1/reports {"video_id":"v1","reason":"outro"}',
      'GET /v1/family/thumbs/a%2Fb',
    ]);
  });

  test('the catalogue parses with provenance', () async {
    final page = await FamilyCatalogApi(
      build(ClientKind.mobile, familyContract).client,
    ).minorCatalog('m1');

    expect(page.hasMore, isTrue);
    final v = page.videos.single;
    expect(v.id, 'v1');
    expect(v.channelTitle, 'Canal Baby Shark');
    // The Guardian Window plays it (family catalogue screens).
    expect(v.youtubeId, 'XqZsoesa55w');
    expect(v.duration, const Duration(minutes: 5));
    expect(v.theme, VideoTheme.bichos);
    expect(v.minAgeBand, AgeBand.upTo4);
    expect(v.hidden, isTrue);
    expect(v.provenance!.approvals, {
      DisplayRole.maePai: 2,
      DisplayRole.pedagogo: 1,
    });
  });

  test('a report says whether it was new', () async {
    final created = build(ClientKind.mobile, (_) => http.Response('', 201));
    final repeated = build(ClientKind.mobile, (_) => http.Response('', 200));
    expect(
      await FamilyCatalogApi(created.client).report('v1', ReportReason.outro),
      isTrue,
    );
    expect(
      await FamilyCatalogApi(repeated.client).report('v1', ReportReason.outro),
      isFalse,
    );
  });

  test('a thumbnail comes back as bytes', () async {
    final api = FamilyCatalogApi(build(ClientKind.web, familyContract).client);
    expect(await api.thumbnail('v1'), [0xFF, 0xD8]);
  });

  test('every problem code surfaces as an ApiError', () async {
    for (final (status, code) in [
      (404, 'not_found'),
      (422, 'validation'),
      (503, 'thumbnail_unavailable'),
    ]) {
      final api = FamilyCatalogApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.minorCatalog('m1'),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', code)),
      );
    }
    final limited = FamilyCatalogApi(
      build(
        ClientKind.mobile,
        (_) => problem(429, 'rate_limited', headers: {'retry-after': '60'}),
      ).client,
    );
    await expectLater(
      limited.report('v1', ReportReason.outro),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'rate_limited')
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(minutes: 1),
            ),
      ),
    );
  });

  test('held videos carry why and their reports', () {
    final held = HeldVideo.fromJson({
      'video': {...videoJson, 'state': 'held'},
      'rejections': [rejectionJson],
      'held_reason': 'reports',
      'reports': {
        'by_reason': {'assustador': 2, 'outro': 1, 'novo-motivo': 1},
        'notes': ['Tem um monstro.'],
      },
    });
    expect(held.video.state, VideoState.held);
    expect(held.rejections.single.reason, 'Tem propaganda.');
    expect(held.rejections.single.displayRole, DisplayRole.cuidador);
    expect(held.heldReason, HeldReason.reports);
    expect(held.reports.byReason, {
      ReportReason.assustador: 2,
      ReportReason.outro: 1,
      ReportReason.unknown: 1,
    });
    expect(held.reports.notes, ['Tem um monstro.']);
  });

  test('an older server\'s held video reads as held by review', () {
    final held = HeldVideo.fromJson({
      'video': {...videoJson, 'state': 'held'},
      'rejections': [rejectionJson],
    });
    expect(held.heldReason, HeldReason.review);
    expect(held.reports.byReason, isEmpty);
    expect(held.reports.notes, isEmpty);
  });

  test('the app services build one FamilyCatalogApi', () {
    expect(Harness().services.familyCatalog, isA<FamilyCatalogApi>());
  });
}
