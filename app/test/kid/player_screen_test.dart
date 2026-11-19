import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart' show ErrorNote;
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/paused_profile.dart';
import 'package:telinha_segura/kid/player_keys.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/player_stage.dart';
import 'package:telinha_segura/kid/shelves.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'fake_player.dart';
import 'kid_mosaic_test.dart' show pixel, twoShelves;
import 'shelf_picture.dart';

/// A shared kid whose API answers the catalogue, thumbnails, and a play
/// with [play] (`yt1` by default).
Harness kid({
  FutureOr<http.Response> Function(http.Request)? play,
  FutureOr<http.Response> Function(http.Request)? beat,
}) => Harness(
  signedIn: true,
  api: (req) {
    final path = req.url.path;
    if (path == '/v1/child/profile') return json(200, profileJson);
    if (path == '/v1/child/catalog') return json(200, twoShelves);
    if (path.startsWith('/v1/child/thumbs/')) {
      return http.Response.bytes(pixel, 200);
    }
    if (path.endsWith('/beat')) {
      return (beat ??
          (_) => json(200, {'state': 'ok', 'remaining_seconds': 600}))(req);
    }
    if (path == '/v1/child/plays') {
      return (play ??
          (_) => json(201, {
            'play_id': 'p1',
            'youtube_id': 'yt1',
            'remaining_seconds': 600,
          }))(req);
    }
    return http.Response('', 204);
  },
)..kidMode = {'minor_id': 'm1'};

Finder get firstTile => find.byType(VideoTile).first;

/// Opens the child home and taps the first video.
Future<Harness> watching(
  WidgetTester tester, {
  Harness? harness,
  Size size = const Size(390, 844),
}) async {
  final h = harness ?? kid();
  await h.pump(tester, initial: '/crianca', size: size);
  await tester.tap(firstTile);
  await tester.pumpAndSettle();
  return h;
}

FakePlayback current(Harness h) => h.player.current!;

Finder get playerView => find.byKey(FakePlayback.viewKey);

/// The player's dark room: Noite edge to edge and no small mark; back
/// and play/pause outside [window]; the mascot in its night colours on a
/// thin wire beside the keys, never over the window nor touching it.
/// Where the mascot already stands in the window's place ([inWindow]),
/// the wire stays empty: one mascot on the screen, and the window's place
/// on Noite too.
void expectNightStage(
  WidgetTester tester,
  Finder window, {
  bool inWindow = false,
}) {
  if (inWindow) {
    expect(find.byType(Tevi), findsOneWidget);
    expect(
      find.descendant(of: window, matching: find.byType(Tevi)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PlayerPerch),
        matching: find.byType(Tevi),
      ),
      findsNothing,
    );
    final stage = tester.widget<ColoredBox>(
      find.descendant(of: window, matching: find.byType(ColoredBox)).first,
    );
    expect(stage.color, BrandColors.dark);
  }
  final ground = find
      .descendant(of: find.byType(KidLayout), matching: find.byType(Scaffold))
      .first;
  expect(tester.widget<Scaffold>(ground).backgroundColor, BrandColors.dark);
  expect(
    find.byWidgetPredicate((w) => w is Tevi && w.tier == TeviTier.simplified),
    findsNothing,
  );
  final perch = find.byType(PlayerPerch);
  expect(perch, findsOneWidget);
  if (inWindow) return;
  final figure = find.descendant(of: perch, matching: find.byType(Tevi));
  expect(tester.widget<Tevi>(figure).night, isTrue);
  final w = tester.getRect(window);
  final mascot = tester.getRect(figure);
  // Clear of the window by a margin, so it never seems to stand on it.
  expect(mascot.overlaps(w.inflate(Space.sm)), isFalse, reason: 'mascot');
  expect(tester.getRect(perch).overlaps(w), isFalse, reason: 'wire');
  for (final key in find.byType(PlayerKey).evaluate()) {
    final rect = tester.getRect(find.byWidget(key.widget));
    expect(rect.overlaps(w), isFalse, reason: 'key');
    expect(rect.overlaps(mascot), isFalse, reason: 'mascot beside the keys');
  }
  // Nothing paints above the window: no Stack holds it.
  expect(find.ancestor(of: window, matching: find.byType(Stack)), findsNothing);
}

List<String> plays(Harness h) =>
    h.actions.where((c) => c.startsWith('POST /v1/child/plays')).toList();

void main() {
  List<String> beats(Harness h) =>
      h.actions.where((c) => c.contains('/beat')).toList();

  testWidgets('the player beats while it plays and once when it stops', (
    tester,
  ) async {
    final h = await watching(tester);
    current(h).emit(const PlayerPlaying());
    await tester.pump();
    expect(beats(h), ['POST /v1/child/plays/p1/beat {"playing":true}']);

    await tester.pump(const Duration(seconds: 30));
    expect(beats(h), hasLength(2));

    current(h).emit(const PlayerPaused());
    await tester.pump();
    expect(beats(h).last, 'POST /v1/child/plays/p1/beat {"playing":false}');

    current(h).emit(const PlayerPlaying());
    await tester.pump();
    current(h).emit(const PlayerEnded());
    await tester.pumpAndSettle();
    expect(beats(h).last, 'POST /v1/child/plays/p1/beat {"playing":false}');
    expect(h.location(tester), '/crianca');
  });

  testWidgets('a solo play starts at the beginning and its beats carry no '
      'position', (tester) async {
    final h = await watching(tester);
    expect(current(h).start, 0);
    current(h).at = 42;
    current(h).emit(const PlayerPlaying());
    await tester.pump();
    expect(beats(h), ['POST /v1/child/plays/p1/beat {"playing":true}']);
  });

  testWidgets('a family work opens where it stopped and every beat says '
      'where the video is', (tester) async {
    final h = kid(
      play: (_) => json(201, {
        'play_id': 'p1',
        'youtube_id': 'yt1',
        'remaining_seconds': 600,
        'start_seconds': 754,
      }),
    );
    await watching(tester, harness: h);
    expect(current(h).start, 754);
    current(h).at = 755;
    current(h).emit(const PlayerPlaying());
    await tester.pump();
    current(h).at = 785;
    await tester.pump(const Duration(seconds: 30));
    expect(beats(h), [
      'POST /v1/child/plays/p1/beat {"playing":true,"position_seconds":755}',
      'POST /v1/child/plays/p1/beat {"playing":true,"position_seconds":785}',
    ]);
  });

  testWidgets('leaving a family work sends where it stopped, not the 0 of '
      'a closed player', (tester) async {
    final h = kid(
      play: (_) => json(201, {
        'play_id': 'p1',
        'youtube_id': 'yt1',
        'remaining_seconds': 600,
        'start_seconds': 754,
      }),
    );
    await watching(tester, harness: h);
    current(h).at = 812;
    current(h).emit(const PlayerPlaying());
    await tester.pump();

    await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
    await tester.pumpAndSettle();

    expect(current(h).closed, isTrue);
    expect(
      beats(h).last,
      'POST /v1/child/plays/p1/beat {"playing":false,"position_seconds":812}',
    );
  });

  testWidgets('a family work reopened after a long pause keeps saying where '
      'the video is', (tester) async {
    var opened = 0;
    final h = kid(
      play: (_) => json(201, {
        'play_id': 'p${++opened}',
        'youtube_id': 'yt1',
        'remaining_seconds': 600,
        'start_seconds': 754,
      }),
      beat: (req) => req.url.path.contains('/p1/')
          ? problem(409, 'play_closed')
          : json(200, {'state': 'ok', 'remaining_seconds': 600}),
    );
    await watching(tester, harness: h);
    current(h).at = 900;
    current(h).emit(const PlayerPlaying());
    await tester.pumpAndSettle();
    expect(
      h.actions,
      contains('POST /v1/child/plays {"video_id":"v1","continues":"p1"}'),
    );
    expect(
      beats(h).last,
      'POST /v1/child/plays/p2/beat {"playing":true,"position_seconds":900}',
    );
  });

  testWidgets('a reopen refused for time pauses and returns to the shelves', (
    tester,
  ) async {
    var opened = 0;
    final h = kid(
      play: (_) => opened++ == 0
          ? json(201, {
              'play_id': 'p1',
              'youtube_id': 'yt1',
              'remaining_seconds': 600,
            })
          : problem(403, 'time_up'),
      beat: (_) => problem(409, 'play_closed'),
    );
    await watching(tester, harness: h);
    final playback = current(h);
    playback.emit(const PlayerPlaying());
    await tester.pumpAndSettle();
    expect(playback.closed, isTrue);
    expect(h.location(tester), '/crianca');
  });

  testWidgets('a reopen refused for not fitting pauses and returns to the '
      'shelves with the note', (tester) async {
    var opened = 0;
    final h = kid(
      play: (_) => opened++ == 0
          ? json(201, {
              'play_id': 'p1',
              'youtube_id': 'yt1',
              'remaining_seconds': 600,
            })
          : problem(403, 'does_not_fit'),
      beat: (_) => problem(409, 'play_closed'),
    );
    await watching(tester, harness: h);
    final playback = current(h);
    playback.emit(const PlayerPlaying());
    await tester.pumpAndSettle();
    expect(playback.calls, contains('pause'));
    expect(playback.closed, isTrue);
    expect(h.location(tester), '/crianca');
    expect(find.text(PlayerScreen.doesNotFit), findsOneWidget);
  });

  testWidgets('a thumbnail plays once and opens the player with the video '
      'the server returned', (tester) async {
    final h = await watching(tester);

    expect(plays(h), ['POST /v1/child/plays {"video_id":"v1"}']);
    expect(h.location(tester), '/crianca/assistir/v1');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(h.player.opened, hasLength(1));
    expect(current(h).youtubeId, 'yt1');
    expect(playerView, findsOneWidget);
    // It starts on its own: the screen asks nothing more of it.
    expect(current(h).calls, isEmpty);
  });

  testWidgets('while a play is pending, more taps do nothing', (tester) async {
    final gate = Completer<http.Response>();
    final h = kid(play: (_) => gate.future);
    await h.pump(tester, initial: '/crianca');

    await tester.tap(firstTile);
    await tester.pump();
    await tester.tap(firstTile);
    await tester.tap(find.byType(VideoTile).at(1));
    await tester.pump();
    expect(plays(h), hasLength(1));

    gate.complete(
      json(201, {
        'play_id': 'p1',
        'youtube_id': 'yt1',
        'remaining_seconds': 600,
      }),
    );
    await tester.pumpAndSettle();
    expect(h.player.opened, hasLength(1));
  });

  for (final code in ['video_not_allowed', 'not_found']) {
    testWidgets('a refused play ($code) shows the kid error note and fetches '
        'the shelves again', (tester) async {
      final h = kid(
        play: (_) => problem(code == 'not_found' ? 404 : 403, code),
      );
      await h.pump(tester, initial: '/crianca');
      await tester.tap(firstTile);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/crianca');
      expect(h.player.opened, isEmpty);
      // The kid note: a picture and the line, never the guardian's alarm
      // icon.
      expect(find.byType(KidErrorNote), findsOneWidget);
      // The mascot raises its crest: something did not go as planned.
      // Large in the floating card's night.
      expectNoteFigure(tester, find.byType(KidErrorNote), TeviLook.crestUp);
      expect(find.byType(ErrorNote), findsNothing);
      expect(find.text(PlayerScreen.videoGone), findsOneWidget);
      expect(
        h.actions.where((c) => c == 'GET /v1/child/catalog'),
        hasLength(2),
      );
    });
  }

  test('does_not_fit says the video is longer than the time left', () {
    const e = ApiError(status: 403, code: 'does_not_fit');
    expect(refusalNote(e), PlayerScreen.doesNotFit);
    expect(
      PlayerScreen.doesNotFit,
      'Esse vídeo é mais comprido que o tempo que falta hoje. '
      'Escolha um mais curto.',
    );
    expect(refusesEvery(e), isFalse);
    expect(refetchAfter(refusalNote(e)), isFalse);
  });

  test(
    'a paused profile\'s refusal says so, and the shelves are read again',
    () {
      const paused = ApiError(status: 403, code: 'consent_required');
      expect(refusalNote(paused), PausedProfile.line);
      expect(refetchAfter(refusalNote(paused)), isTrue);
    },
  );

  testWidgets('a play refused as consent_required leaves the shelves for the '
      'paused profile', (tester) async {
    var paused = false;
    final h = Harness(
      signedIn: true,
      api: (req) {
        final path = req.url.path;
        if (path == '/v1/child/catalog') {
          return paused
              ? problem(403, 'consent_required')
              : json(200, twoShelves);
        }
        if (path.startsWith('/v1/child/thumbs/')) {
          return http.Response.bytes(pixel, 200);
        }
        if (path == '/v1/child/plays') {
          paused = true;
          return problem(403, 'consent_required');
        }
        return json(200, profileJson);
      },
    )..kidMode = {'minor_id': 'm1'};
    await h.pump(tester, initial: '/crianca');

    await tester.tap(firstTile);
    await tester.pumpAndSettle();

    expect(h.player.opened, isEmpty);
    expect(find.byType(PausedProfile), findsOneWidget);
    expect(find.text(PausedProfile.line), findsOneWidget);
    expect(find.byType(VideoTile), findsNothing);
  });

  testWidgets('the paused line leaves the shelves once the adult authorizes '
      'again', (tester) async {
    var paused = false;
    final h = Harness(
      signedIn: true,
      api: (req) {
        final path = req.url.path;
        if (path == '/v1/child/catalog') {
          return paused
              ? problem(403, 'consent_required')
              : json(200, twoShelves);
        }
        if (path.startsWith('/v1/child/thumbs/')) {
          return http.Response.bytes(pixel, 200);
        }
        if (path == '/v1/child/plays') {
          paused = true;
          return problem(403, 'consent_required');
        }
        return json(200, profileJson);
      },
    )..kidMode = {'minor_id': 'm1'};
    await h.pump(tester, initial: '/crianca');
    await tester.tap(firstTile);
    await tester.pumpAndSettle();
    expect(find.text(PausedProfile.line), findsOneWidget);

    paused = false;
    await tester.pump(KidHomeScreen.wake);
    await tester.pumpAndSettle();

    expect(find.text(PausedProfile.line), findsNothing);
    expect(find.byType(VideoTile), findsWidgets);
  });

  testWidgets('the controls sit outside the player, nothing is drawn over '
      'it, and no YouTube logo sits beside it', (tester) async {
    await watching(tester);

    expect(find.byType(SvgPicture), findsNothing);
    final player = tester.getRect(playerView);
    for (final control in [
      find.bySemanticsLabel(PlayerScreen.back),
      find.bySemanticsLabel(PlayerScreen.playLabel),
    ]) {
      final rect = tester.getRect(control);
      expect(rect.overlaps(player), isFalse, reason: '$control');
    }
    // Nothing paints above the embed: no Stack holds it.
    expect(
      find.ancestor(of: playerView, matching: find.byType(Stack)),
      findsNothing,
    );
    expect(
      tester.getSize(find.bySemanticsLabel(PlayerScreen.back)),
      const Size.square(KidSizes.target),
    );
    expect(
      tester.getSize(find.bySemanticsLabel(PlayerScreen.playLabel)),
      const Size.square(PlayerStage.toggleSize),
    );
    expect(PlayerStage.toggleSize, greaterThanOrEqualTo(88));
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('at ${size.width.toInt()} × ${size.height.toInt()} the '
        'player stands in a dark room, the mascot on its wire beside the '
        'keys', (tester) async {
      await watching(tester, size: size);
      expectNightStage(tester, playerView);
    });
  }

  testWidgets('upright, back stands at the start and play/pause on the '
      'window\'s centre line, the round keys in the brand\'s colours', (
    tester,
  ) async {
    await watching(tester);
    final window = tester.getRect(playerView);
    final back = tester.getRect(find.bySemanticsLabel(PlayerScreen.back));
    final toggle = tester.getRect(
      find.bySemanticsLabel(PlayerScreen.playLabel),
    );
    expect(toggle.center.dx, closeTo(window.center.dx, .5));
    expect(back.left, window.left + Space.xl);
    expect(back.center.dy, closeTo(toggle.center.dy, .5));
    final keys = tester.widgetList<PlayerKey>(find.byType(PlayerKey)).toList();
    expect(keys.map((k) => (k.glyph, k.size, k.filled)), [
      (PlayerGlyph.back, KidSizes.target, false),
      (PlayerGlyph.play, PlayerStage.toggleSize, true),
    ]);
    // The mascot stands at the end, on the far side from back.
    final mascot = tester.getRect(
      find.descendant(
        of: find.byType(PlayerPerch),
        matching: find.byType(Tevi),
      ),
    );
    expect(mascot.left, greaterThan(toggle.right));
    expect(mascot.right, lessThanOrEqualTo(window.right));
  });

  testWidgets('no gesture of ours lies on the player', (tester) async {
    await watching(tester);

    for (final type in [GestureDetector, RawGestureDetector, InkWell]) {
      expect(
        find.ancestor(of: playerView, matching: find.byType(type)),
        findsNothing,
        reason: '$type',
      );
    }
  });

  for (final size in [
    const Size(360, 640),
    const Size(640, 360),
    const Size(1280, 800),
  ]) {
    testWidgets('at ${size.width.toInt()} × ${size.height.toInt()} the '
        'player keeps at least 200 × 200, at 16:9', (tester) async {
      await watching(tester, size: size);

      final player = tester.getSize(playerView);
      expect(player.width, greaterThanOrEqualTo(200));
      expect(player.height, greaterThanOrEqualTo(200));
      expect(player.width / player.height, closeTo(16 / 9, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('until the player says it plays, the key offers to play: a '
      'browser may hold autoplay', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await watching(tester);

    expect(find.bySemanticsLabel(PlayerScreen.pauseLabel), findsNothing);
    await tester.tap(find.bySemanticsLabel(PlayerScreen.playLabel));
    await tester.pump();
    expect(current(h).calls, ['play']);
    semantics.dispose();
  });

  testWidgets('play/pause toggles the player and says what it will do', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await watching(tester);
    current(h).emit(const PlayerPlaying());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.bySemanticsLabel(PlayerScreen.pauseLabel));
    await tester.pump();
    expect(current(h).calls, ['pause']);
    current(h).emit(const PlayerPaused());
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel(PlayerScreen.pauseLabel), findsNothing);
    await tester.tap(find.bySemanticsLabel(PlayerScreen.playLabel));
    await tester.pump();
    expect(current(h).calls, ['pause', 'play']);
    current(h).emit(const PlayerPlaying());
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel(PlayerScreen.pauseLabel), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('at the end the player goes and the shelves come back; '
      'nothing plays next', (tester) async {
    final h = await watching(tester);

    current(h).emit(const PlayerEnded());
    await tester.pumpAndSettle();

    expect(current(h).closed, isTrue);
    expect(h.location(tester), '/crianca');
    expect(find.byType(ThemeBlock), findsWidgets);
    expect(h.player.opened, hasLength(1));
    expect(plays(h), hasLength(1));
  });

  testWidgets('back stops the player and returns to the shelves', (
    tester,
  ) async {
    final h = await watching(tester);

    await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
    await tester.pumpAndSettle();

    expect(current(h).closed, isTrue);
    expect(h.location(tester), '/crianca');
  });

  testWidgets('going to the background pauses', (tester) async {
    final h = await watching(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(current(h).calls, contains('pause'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('going to the background mid-play beats once with '
      '"playing": false and then stays quiet', (tester) async {
    final h = await watching(tester);
    current(h).emit(const PlayerPlaying());
    await tester.pump();
    expect(beats(h), ['POST /v1/child/plays/p1/beat {"playing":true}']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(beats(h), [
      'POST /v1/child/plays/p1/beat {"playing":true}',
      'POST /v1/child/plays/p1/beat {"playing":false}',
    ]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    // Away, no tick counts time the child is not watching.
    expect(beats(h), hasLength(2));
    expect(current(h).calls, contains('pause'));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 30));
    expect(beats(h), hasLength(2), reason: 'it beats when the video plays');
  });

  testWidgets('a player error reports the video once, shows the kid error '
      'note, then returns to the shelves', (tester) async {
    final h = await watching(tester);
    final player = tester.getRect(playerView);

    current(h).emit(const PlayerFailed());
    current(h).emit(const PlayerFailed());
    await tester.pump(); // the events arrive
    await tester.pump(); // the screen shows them

    expect(h.actions.where((c) => c.contains('/unavailable')), [
      'POST /v1/child/videos/v1/unavailable',
    ]);
    expect(current(h).closed, isTrue);
    expect(playerView, findsNothing);
    expect(find.byType(ErrorNote), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    final note = find.byType(KidErrorNote);
    expect(note, findsOneWidget);
    // In the player's dark room the figure wears its night colours.
    expectPerched(tester, note, TeviLook.crestUp, night: true);
    expect(find.text(PlayerScreen.videoFailed), findsOneWidget);
    // Where the player stood: the note never sat over it.
    expect(tester.getRect(note).overlaps(player), isTrue);

    await tester.pump(PlayerScreen.errorPause);
    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');
  });

  testWidgets('a video other than the one opened is stopped at once '
      '(strayed)', (tester) async {
    final h = await watching(tester);

    current(h).emit(const PlayerStrayed());
    await tester.pumpAndSettle();

    expect(current(h).closed, isTrue);
    expect(h.location(tester), '/crianca');
  });

  testWidgets('opened without a play (a reload, a typed URL) it plays first', (
    tester,
  ) async {
    final h = kid();
    await h.pump(tester, initial: '/crianca/assistir/v2');

    expect(plays(h), ['POST /v1/child/plays {"video_id":"v2"}']);
    expect(h.location(tester), '/crianca/assistir/v2');
    expect(current(h).youtubeId, 'yt1');
  });

  testWidgets('opened without a play that the server refuses, it returns '
      'to the shelves with the note', (tester) async {
    final h = kid(play: (_) => problem(403, 'video_not_allowed'));
    await h.pump(tester, initial: '/crianca/assistir/v2');

    expect(h.player.opened, isEmpty);
    expect(h.location(tester), '/crianca');
    expect(find.text(PlayerScreen.videoGone), findsOneWidget);
  });

  testWidgets('the player sits in the child frame, the exit still in its '
      'corner', (tester) async {
    await watching(tester);
    expect(find.byType(HoldToExit), findsOneWidget);
  });

  test('child-facing copy is one short verb', () {
    expect(PlayerScreen.back, 'Voltar');
    expect(PlayerScreen.pauseLabel, 'Pausar');
    expect(PlayerScreen.playLabel, 'Continuar');
  });
}
