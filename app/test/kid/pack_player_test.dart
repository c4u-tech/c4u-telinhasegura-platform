import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/pack_player_screen.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/sleeping_telinha.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'fake_player.dart';
import 'kid_shelves_test.dart' show pixel, twoShelves, video;

/// The day's shelves plus one pacotinho of three videos, its cover the
/// second.
final Map<String, Object?> withPack = {
  ...twoShelves,
  'packs': [
    {
      'id': 'k1',
      'title': 'Bichos do mar',
      'cover_video_id': 'v2',
      'videos': [video('v1'), video('v2'), video('v3')],
    },
  ],
};

Map<String, Object?> opened(String videoId) => {
  'play_id': 'p-$videoId',
  'youtube_id': 'yt-$videoId',
  'remaining_seconds': 600,
};

/// A shared kid whose catalogue holds [withPack] (or [catalog]); each play
/// answers [play] for the video asked, or opens it.
Harness packKid({
  Map<String, Object?> Function()? catalog,
  FutureOr<http.Response> Function(String videoId)? play,
}) => Harness(
  signedIn: true,
  api: (req) {
    final path = req.url.path;
    if (path == '/v1/child/profile') return json(200, profileJson);
    if (path == '/v1/child/catalog') {
      return json(200, catalog?.call() ?? withPack);
    }
    if (path.startsWith('/v1/child/thumbs/')) {
      return http.Response.bytes(pixel, 200);
    }
    if (path.endsWith('/beat')) {
      return json(200, {'state': 'ok', 'remaining_seconds': 600});
    }
    if (path == '/v1/child/plays') {
      final id =
          (jsonDecode(req.body) as Map<String, dynamic>)['video_id'] as String;
      return (play ?? (id) => json(201, opened(id)))(id);
    }
    return http.Response('', 204);
  },
)..kidMode = {'minor_id': 'm1'};

Finder get packTile => find.byType(PackTile).first;

List<String> plays(Harness h) => [
  for (final c in h.actions)
    if (c.startsWith('POST /v1/child/plays {'))
      c.split('"video_id":"')[1].split('"').first,
];

FakePlayback current(Harness h) => h.player.current!;

/// Opens the child home and taps the pacotinho.
Future<Harness> inPack(
  WidgetTester tester, {
  Harness? harness,
  Size size = const Size(390, 844),
}) async {
  final h = harness ?? packKid();
  await h.pump(tester, initial: '/crianca', size: size);
  await tester.tap(packTile);
  await tester.pumpAndSettle();
  return h;
}

/// Ends the video playing and lets the breath settle.
Future<void> end(WidgetTester tester, Harness h) async {
  current(h).emit(const PlayerEnded());
  await tester.pumpAndSettle();
}

/// The progress modules' filled count, read as their words.
Finder progress(int k, int n) => find.bySemanticsLabel('Vídeo $k de $n');

void main() {
  testWidgets('a tap on the pacotinho plays its first video once and opens '
      'its player', (tester) async {
    final h = await inPack(tester);

    expect(plays(h), ['v1']);
    expect(h.location(tester), '/crianca/pacotinho/k1');
    expect(find.byType(PackPlayerScreen), findsOneWidget);
    expect(current(h).youtubeId, 'yt-v1');
    expect(find.byKey(FakePlayback.viewKey), findsOneWidget);
    expect(progress(1, 3), findsOneWidget);
    // No YouTube logo in the player (fullscreen design).
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('while the first play is pending, more taps do nothing', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    final h = packKid(play: (_) => gate.future);
    await h.pump(tester, initial: '/crianca');

    await tester.tap(packTile);
    await tester.pump();
    await tester.tap(packTile);
    await tester.tap(find.byType(VideoTile).first);
    await tester.pump();
    expect(plays(h), ['v1']);

    gate.complete(json(201, opened('v1')));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca/pacotinho/k1');
  });

  testWidgets('a first video refused is passed over for the next', (
    tester,
  ) async {
    final h = await inPack(
      tester,
      harness: packKid(
        play: (id) => id == 'v1'
            ? problem(403, 'video_not_allowed')
            : json(201, opened(id)),
      ),
    );
    expect(plays(h), ['v1', 'v2']);
    expect(current(h).youtubeId, 'yt-v2');
    expect(progress(2, 3), findsOneWidget);
  });

  testWidgets('with every video refused the shelves say why', (tester) async {
    final none = packKid(play: (_) => problem(403, 'video_not_allowed'));
    await none.pump(tester, initial: '/crianca');
    await tester.tap(packTile);
    await tester.pumpAndSettle();
    expect(plays(none), ['v1', 'v2', 'v3']);
    expect(none.location(tester), '/crianca');
    expect(find.byType(KidErrorNote), findsOneWidget);
    expect(find.text(PlayerScreen.videoGone), findsOneWidget);
  });

  testWidgets('a first play refused for time sends the home to sleep', (
    tester,
  ) async {
    Map<String, Object?> catalog = withPack;
    final sleepy = packKid(
      catalog: () => catalog,
      play: (_) {
        catalog = {
          ...withPack,
          'time': {'state': 'time_up', 'reason': 'daily'},
        };
        return problem(403, 'time_up');
      },
    );
    await sleepy.pump(tester, initial: '/crianca');
    await tester.tap(packTile);
    await tester.pumpAndSettle();

    expect(sleepy.location(tester), '/crianca');
    expect(find.byType(SleepingTelinha), findsOneWidget);
    expect(find.byType(KidErrorNote), findsNothing);
  });

  testWidgets('opened without its pacotinho it returns to the shelves', (
    tester,
  ) async {
    final h = packKid();
    await h.pump(tester, initial: '/crianca/pacotinho/k1');
    await tester.pumpAndSettle();

    expect(h.location(tester), '/crianca');
    expect(plays(h), isEmpty);
  });

  testWidgets('a video\'s end lets the player go and shows the breath: the '
      'next cover, the Espiadinha, the modules and "Continuar"', (
    tester,
  ) async {
    final h = await inPack(tester);
    final first = current(h);
    await end(tester, h);

    expect(first.closed, isTrue);
    expect(find.byKey(FakePlayback.viewKey), findsNothing);
    expect(find.byType(PackBreath), findsOneWidget);
    expect(progress(1, 3), findsOneWidget);
    expect(find.bySemanticsLabel(PlayerScreen.playLabel), findsOneWidget);
    // No seconds, said or drawn.
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(plays(h), ['v1']);
  });

  testWidgets('the breath continues by itself after 4 s', (tester) async {
    final h = await inPack(tester);
    await end(tester, h);

    await tester.pump(const Duration(seconds: 3));
    expect(plays(h), ['v1']);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(plays(h), ['v1', 'v2']);
    expect(current(h).youtubeId, 'yt-v2');
    expect(find.byType(PackBreath), findsNothing);
    expect(progress(2, 3), findsOneWidget);
  });

  testWidgets('a tap on the breath or on its key continues at once, once', (
    tester,
  ) async {
    final h = await inPack(tester);
    await end(tester, h);

    await tester.tap(find.byType(PackBreath));
    await tester.tap(find.byType(PackBreath), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(plays(h), ['v1', 'v2']);

    await end(tester, h);
    await tester.tap(find.bySemanticsLabel(PlayerScreen.playLabel));
    await tester.pumpAndSettle();
    expect(plays(h), ['v1', 'v2', 'v3']);
    // The pacotinho's own timer is spent with its breath.
    await tester.pump(const Duration(seconds: 5));
    expect(plays(h), ['v1', 'v2', 'v3']);
  });

  testWidgets('in the background the breath does not advance, and starts '
      'over on return', (tester) async {
    final h = await inPack(tester);
    await end(tester, h);

    await tester.pump(const Duration(seconds: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(plays(h), ['v1']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(plays(h), ['v1']);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(plays(h), ['v1', 'v2']);
  });

  testWidgets('time up when the breath ends the pacotinho and the home '
      'sleeps', (tester) async {
    Map<String, Object?> catalog = withPack;
    final h = packKid(
      catalog: () => catalog,
      play: (id) {
        if (id == 'v1') return json(201, opened(id));
        catalog = {
          ...withPack,
          'time': {'state': 'time_up', 'reason': 'daily'},
        };
        return problem(403, 'time_up');
      },
    );
    await inPack(tester, harness: h);
    await end(tester, h);
    await tester.tap(find.byType(PackBreath));
    await tester.pumpAndSettle();

    expect(plays(h), ['v1', 'v2']);
    expect(h.location(tester), '/crianca');
    expect(find.byType(SleepingTelinha), findsOneWidget);
    expect(find.byType(KidErrorNote), findsNothing);
  });

  testWidgets('a video refused for another reason is passed over with no '
      'note', (tester) async {
    final h = await inPack(
      tester,
      harness: packKid(
        play: (id) => id == 'v2'
            ? problem(403, 'video_not_allowed')
            : json(201, opened(id)),
      ),
    );
    await end(tester, h);
    await tester.tap(find.byType(PackBreath));
    await tester.pumpAndSettle();

    expect(plays(h), ['v1', 'v2', 'v3']);
    expect(current(h).youtubeId, 'yt-v3');
    expect(progress(3, 3), findsOneWidget);
    expect(find.byType(KidErrorNote), findsNothing);
  });

  testWidgets('a player failure is reported once and the next video starts '
      'with no note', (tester) async {
    final h = await inPack(tester);
    final first = current(h);
    first.emit(const PlayerFailed());
    await tester.pumpAndSettle();

    expect(h.actions.where((a) => a.contains('/unavailable')), hasLength(1));
    expect(first.closed, isTrue);
    expect(plays(h), ['v1', 'v2']);
    expect(current(h).youtubeId, 'yt-v2');
    expect(find.byType(KidErrorNote), findsNothing);
  });

  testWidgets('with no video left after a refusal, the goodbye', (
    tester,
  ) async {
    final h = await inPack(
      tester,
      harness: packKid(
        play: (id) => id == 'v1'
            ? json(201, opened(id))
            : problem(403, 'video_not_allowed'),
      ),
    );
    await end(tester, h);
    await tester.tap(find.byType(PackBreath));
    await tester.pumpAndSettle();

    expect(plays(h), ['v1', 'v2', 'v3']);
    expect(find.byType(PackGoodbye), findsOneWidget);
  });

  testWidgets('a video other than the pacotinho\'s is stopped at once and '
      'the shelves return', (tester) async {
    final h = await inPack(tester);
    final first = current(h);
    first.emit(const PlayerStrayed());
    await tester.pumpAndSettle();

    expect(first.closed, isTrue);
    expect(h.location(tester), '/crianca');
    expect(plays(h), ['v1']);
  });

  testWidgets('after the last video, the goodbye: every module filled, '
      '"Fim", back only, no logo', (tester) async {
    final h = await inPack(tester);
    for (var i = 0; i < 2; i++) {
      await end(tester, h);
      await tester.tap(find.byType(PackBreath));
      await tester.pumpAndSettle();
    }
    final last = current(h);
    await end(tester, h);

    expect(last.closed, isTrue);
    expect(find.byType(PackGoodbye), findsOneWidget);
    expect(find.text(PackGoodbye.word), findsOneWidget);
    expect(progress(3, 3), findsOneWidget);
    expect(find.bySemanticsLabel(PlayerScreen.back), findsOneWidget);
    expect(find.bySemanticsLabel(PlayerScreen.playLabel), findsNothing);
    expect(find.bySemanticsLabel(PlayerScreen.pauseLabel), findsNothing);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(PackBreath), findsNothing);
  });

  testWidgets('the goodbye returns to the shelves after 3 s, quietly '
      're-reading them, and nothing plays', (tester) async {
    final h = await inPack(tester);
    for (var i = 0; i < 2; i++) {
      await end(tester, h);
      await tester.tap(find.byType(PackBreath));
      await tester.pumpAndSettle();
    }
    await end(tester, h);
    final reads = h.actions.where((a) => a == 'GET /v1/child/catalog').length;

    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(PackGoodbye), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/crianca');
    expect(find.byType(ShelvesLoading), findsNothing);
    expect(
      h.actions.where((a) => a == 'GET /v1/child/catalog').length,
      reads + 1,
    );
    expect(plays(h), ['v1', 'v2', 'v3']);
    await tester.pump(const Duration(seconds: 10));
    expect(plays(h), ['v1', 'v2', 'v3']);
  });

  testWidgets('a tap on the goodbye returns sooner', (tester) async {
    final h = await inPack(
      tester,
      harness: packKid(
        catalog: () => {
          ...twoShelves,
          'packs': [
            {
              'id': 'k1',
              'title': 'Dois',
              'cover_video_id': 'v1',
              'videos': [video('v1'), video('v2')],
            },
          ],
        },
      ),
    );
    await end(tester, h);
    await tester.tap(find.byType(PackBreath));
    await tester.pumpAndSettle();
    await end(tester, h);

    await tester.tap(find.byType(PackGoodbye));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');
  });

  testWidgets('back mid-pacotinho ends it with no goodbye', (tester) async {
    final h = await inPack(tester);
    final first = current(h);
    await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
    await tester.pumpAndSettle();

    expect(first.closed, isTrue);
    expect(h.location(tester), '/crianca');
    expect(find.byType(PackGoodbye), findsNothing);

    // From the breath too, and its timer goes with it.
    await tester.tap(packTile);
    await tester.pumpAndSettle();
    await end(tester, h);
    await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');
    await tester.pump(const Duration(seconds: 5));
    expect(plays(h), ['v1', 'v1']);
  });

  testWidgets('the pacotinho player keeps the frame\'s exit', (tester) async {
    await inPack(tester);
    expect(find.byType(HoldToExit), findsOneWidget);
  });

  testWidgets('outside a pacotinho, nothing plays next', (tester) async {
    final h = packKid();
    await h.pump(tester, initial: '/crianca');
    await tester.tap(
      find
          .descendant(
            of: find.byType(Shelf).first,
            matching: find.byType(VideoTile),
          )
          .first,
    );
    await tester.pumpAndSettle();
    current(h).emit(const PlayerEnded());
    await tester.pumpAndSettle();

    expect(h.location(tester), '/crianca');
    await tester.pump(const Duration(seconds: 10));
    expect(plays(h), ['v1']);
  });

  testWidgets('window states change with no motion when reduce motion is '
      'asked', (tester) async {
    final h = packKid();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await inPack(tester, harness: h);
    current(h).emit(const PlayerEnded());
    await tester.pump();
    await tester.pump();
    expect(find.byKey(FakePlayback.viewKey), findsNothing);
    expect(find.byType(PackBreath), findsOneWidget);
  });
}
