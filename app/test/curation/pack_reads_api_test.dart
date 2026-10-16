import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/curation_api.dart';
import 'package:telinha_segura/curation/pack.dart';

import '../auth/fakes.dart';
import 'curation_api_test.dart' show videoJson;
import 'pack_api_test.dart' show packJson;

final _packWithChannels = {
  ...packJson,
  'videos': [
    for (final v in packJson['videos']! as List<Object?>)
      {...v! as Map<String, Object?>, 'channel_title': 'Canal'},
  ],
};

http.Response readsContract(http.Request req) =>
    switch ('${req.method} ${req.url.path}') {
      'GET /v1/curation/videos' => json(200, {
        'videos': [videoJson],
        'next_offset': 50,
      }),
      'GET /v1/curation/packs/limits' => json(200, {
        'min_videos': 3,
        'max_videos': 5,
        'max_seconds': 1200,
      }),
      'GET /v1/admin/packs' => json(200, {
        'packs': [_packWithChannels],
        'has_more': false,
      }),
      'GET /v1/admin/packs/p1' => json(200, _packWithChannels),
      _ => http.Response('', 404),
    };

void main() {
  test('every read hits its contract path', () async {
    final t = build(ClientKind.mobile, readsContract);
    final api = CurationApi(t.client);
    await api.approvedVideos(VideoTheme.bichos);
    await api.approvedVideos(VideoTheme.musica, offset: 50);
    await api.packLimits();
    await api.adminPacks();
    await api.adminPacks(offset: 50);
    await api.adminPack('p1');

    expect(t.calls, [
      'GET /v1/curation/videos?theme=bichos',
      'GET /v1/curation/videos?theme=musica&offset=50',
      'GET /v1/curation/packs/limits',
      'GET /v1/admin/packs',
      'GET /v1/admin/packs?offset=50',
      'GET /v1/admin/packs/p1',
    ]);
  });

  test('the reads parse into typed models', () async {
    final api = CurationApi(build(ClientKind.mobile, readsContract).client);

    final page = await api.approvedVideos(VideoTheme.bichos);
    expect(page.videos.single.id, videoJson['id']);
    expect(page.nextOffset, 50);

    final limits = await api.packLimits();
    expect(limits.minVideos, 3);
    expect(limits.maxVideos, 5);
    expect(limits.maxDuration, const Duration(minutes: 20));

    final packs = await api.adminPacks();
    expect(packs.hasMore, isFalse);
    expect(packs.packs.single.videos.first.channelTitle, 'Canal');

    final p = await api.adminPack('p1');
    expect(p.id, 'p1');
    expect(p.videos.map((v) => v.channelTitle), ['Canal', 'Canal', 'Canal']);
  });

  test('a pack video without channel_title reads as empty', () {
    expect(Pack.fromJson(packJson).videos.first.channelTitle, '');
  });

  test('the reads surface their problem codes', () async {
    const codes = {'validation': 422, 'not_found': 404, 'not_curator': 403};
    for (final MapEntry(key: code, value: status) in codes.entries) {
      final api = CurationApi(
        build(ClientKind.mobile, (_) => problem(status, code)).client,
      );
      await expectLater(
        api.approvedVideos(VideoTheme.bichos),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', code)),
      );
    }
    final admin = CurationApi(
      build(ClientKind.mobile, (_) => problem(403, 'not_admin')).client,
    );
    await expectLater(
      admin.adminPack('p1'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'not_admin')),
    );
  });
}
