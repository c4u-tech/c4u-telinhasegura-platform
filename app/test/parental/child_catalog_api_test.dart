import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/kid_catalog.dart';
import 'package:telinha_segura/parental/child_api.dart';
import 'package:telinha_segura/screentime/kid_time.dart';

import '../auth/fakes.dart';
import 'fakes.dart';

const catalogJson = {
  'themes': [
    {
      'theme': 'bichos',
      'videos': [
        {'id': 'v1', 'title': 'Baby Shark', 'duration_seconds': 300},
      ],
    },
    {
      // A theme a newer server knows and this app has no picture for.
      'theme': 'espaco',
      'videos': [
        {'id': 'v2', 'title': 'Foguete', 'duration_seconds': 120},
      ],
    },
  ],
  'time': {
    'state': 'outside_window',
    'reason': 'window',
    'remaining_seconds': 0,
  },
};

http.Response catalogContract(http.Request req) {
  final p = req.url.path;
  if (p == '/v1/child/catalog') return json(200, catalogJson);
  if (p.startsWith('/v1/child/thumbs/')) {
    return http.Response.bytes(
      [0xFF, 0xD8, 0x01],
      200,
      headers: {'content-type': 'image/jpeg'},
    );
  }
  if (p == '/v1/child/plays') {
    return json(201, {
      'play_id': 'p1',
      'youtube_id': 'dQw4w9WgXcQ',
      'remaining_seconds': 600,
    });
  }
  if (p == '/v1/child/plays/p1/beat') {
    return json(200, {
      'state': 'time_up',
      'reason': 'daily',
      'remaining_seconds': 0,
    });
  }
  if (p == '/v1/child/time/extend') {
    return json(200, {'state': 'ok', 'remaining_seconds': 900});
  }
  return http.Response('', 202);
}

void main() {
  test('the catalogue carries the time; a missing one reads as ok', () async {
    final t = build(ClientKind.mobile, catalogContract);
    final api = ChildApi(t.client, devices: MemoryDeviceCredentialStore('d'));
    final catalog = await api.catalog();
    expect(catalog.time.state, KidTimeState.outsideWindow);
    expect(catalog.time.reason, 'window');

    final older = KidCatalog.fromJson({'themes': <Object>[]});
    expect(older.time.state, KidTimeState.ok);
  });

  test('a beat and an extension answer the time', () async {
    final t = build(ClientKind.mobile, catalogContract);
    final api = ChildApi(t.client, devices: MemoryDeviceCredentialStore('d'));
    final beat = await api.beat('p1', playing: true);
    expect(beat.state, KidTimeState.timeUp);
    expect(beat.reason, 'daily');
    final ext = await api.extend(pin: '2580', minutes: 15);
    expect(ext.state, KidTimeState.ok);
    expect(ext.remaining, const Duration(minutes: 15));
    expect(t.calls, [
      'POST /v1/child/plays/p1/beat {"playing":true}',
      'POST /v1/child/time/extend {"pin":"2580","minutes":15}',
    ]);
  });

  test('a time_up play surfaces its code and reason', () async {
    final t = build(
      ClientKind.mobile,
      (_) => problem(403, 'time_up', extra: {'reason': 'window'}),
    );
    final api = ChildApi(t.client, devices: MemoryDeviceCredentialStore('d'));
    await expectLater(
      api.play('v1'),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'time_up')
            .having((e) => e.details['reason'], 'reason', 'window'),
      ),
    );
  });

  test(
    'a linked device reaches every catalogue route with its token',
    () async {
      final seen = <http.Request>[];
      final t = build(ClientKind.mobile, catalogContract, seen: seen);
      final api = ChildApi(
        t.client,
        devices: MemoryDeviceCredentialStore('dev-token'),
      );

      final catalog = await api.catalog();
      expect(catalog.shelves.single.theme, VideoTheme.bichos);
      final video = catalog.shelves.single.videos.single;
      expect(video.id, 'v1');
      expect(video.title, 'Baby Shark');
      expect(video.duration, const Duration(minutes: 5));
      expect(await api.thumbnail('v1'), [0xFF, 0xD8, 0x01]);
      final play = await api.play('v1');
      expect(play.playId, 'p1');
      expect(play.youtubeId, 'dQw4w9WgXcQ');
      expect(play.remaining, const Duration(minutes: 10));
      await api.reportUnavailable('v1');

      expect(t.calls, [
        'GET /v1/child/catalog',
        'GET /v1/child/thumbs/v1',
        'POST /v1/child/plays {"video_id":"v1"}',
        'POST /v1/child/videos/v1/unavailable',
      ]);
      expect(
        seen.map((r) => r.headers['Authorization']),
        everyElement('Bearer dev-token'),
      );
    },
  );

  test('without a device token the bytes ride the web session', () async {
    final seen = <http.Request>[];
    final t = build(ClientKind.web, catalogContract, seen: seen);
    final api = ChildApi(t.client, devices: MemoryDeviceCredentialStore());

    expect(await api.thumbnail('v1'), [0xFF, 0xD8, 0x01]);
    await api.reportUnavailable('v1');

    expect(seen.first.headers['Authorization'], isNull);
    expect(seen.last.headers['X-CSRF-Token'], 'c');
  });

  test('a 401 on a thumbnail forgets the device token', () async {
    final t = build(ClientKind.mobile, (_) => problem(401, 'unauthenticated'));
    final devices = MemoryDeviceCredentialStore('dev-token');
    await expectLater(
      ChildApi(t.client, devices: devices).thumbnail('v1'),
      throwsA(isA<ApiError>()),
    );
    expect(devices.token, isNull);
  });

  test('IDs are encoded into the path', () async {
    final t = build(ClientKind.mobile, catalogContract);
    final api = ChildApi(
      t.client,
      devices: MemoryDeviceCredentialStore('dev-token'),
    );
    await api.thumbnail('a/b');
    expect(t.calls, ['GET /v1/child/thumbs/a%2Fb']);
  });

  test('catalogue problems surface as ApiError codes', () async {
    for (final (status, code) in [
      (403, 'video_not_allowed'),
      (410, 'profile_gone'),
      (503, 'thumbnail_unavailable'),
    ]) {
      final t = build(ClientKind.mobile, (_) => problem(status, code));
      final api = ChildApi(
        t.client,
        devices: MemoryDeviceCredentialStore('dev-token'),
      );
      await expectLater(
        api.thumbnail('v1'),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', code)),
      );
      await expectLater(
        api.play('v1'),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', code)),
      );
    }
  });
}
