import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/paused_profile.dart';
import 'package:telinha_segura/kid/sleeping_telinha.dart';
import 'package:telinha_segura/screentime/kid_time.dart';

import '../access/harness.dart';
import '../design/pump.dart';
import '../design/tevi_motion_test.dart' show drawn;
import '../parental/parental_api_test.dart' show profileJson;
import 'kid_home_screen_test.dart' show actionable, avatar, nightGround;
import 'kid_mosaic_test.dart' show pixel, twoShelves;
import 'shelf_picture.dart';

/// The day as the catalogue says it.
Map<String, Object?> day(String state, [String? reason]) => {
  'state': state,
  'reason': ?reason,
  'remaining_seconds': 0,
};

/// Two shelves on a day in [state].
Map<String, Object?> shelvesOn(Map<String, Object?> time) => {
  ...twoShelves,
  'time': time,
};

/// A shared kid locked to Lia whose catalogue answers [catalog] (two
/// shelves on a used-up day by default).
Harness sleepy({
  FutureOr<http.Response> Function()? catalog,
  FutureOr<http.Response> Function(http.Request)? other,
}) => Harness(
  signedIn: true,
  api: (req) {
    final path = req.url.path;
    if (path == '/v1/child/profile') return json(200, profileJson);
    if (path == '/v1/child/catalog') {
      return (catalog ?? () => json(200, shelvesOn(day('time_up', 'daily'))))();
    }
    if (path.startsWith('/v1/child/thumbs/')) {
      return http.Response.bytes(pixel, 200);
    }
    return (other ?? (_) => http.Response('', 204))(req);
  },
)..kidMode = {'minor_id': 'm1'};

int catalogReads(Harness h) =>
    h.actions.where((c) => c == 'GET /v1/child/catalog').length;

void main() {
  for (final (state, reason, line) in [
    ('time_up', 'daily', 'Acabou por hoje'),
    ('outside_window', 'window', 'Agora não é hora'),
  ]) {
    testWidgets('a catalogue on a $state day shows the sleeping telinha '
        'with "$line" instead of the shelves', (tester) async {
      final h = sleepy(catalog: () => json(200, shelvesOn(day(state, reason))));
      await h.pump(tester, initial: '/crianca');

      expect(find.byType(SleepingTelinha), findsOneWidget);
      expect(find.text(line), findsOneWidget);
      expect(find.byType(ThemeBlock), findsNothing);
      expect(find.byType(VideoTile), findsNothing);
      expect(find.byType(EmptyShelf), findsNothing);
    });
  }

  test('the lines are the operator\'s words', () {
    expect(SleepingTelinha.timeUp, 'Acabou por hoje');
    expect(SleepingTelinha.outsideWindow, 'Agora não é hora');
  });

  testWidgets('asleep, the home stands on the night\'s dark, the picture '
      'and its muted line centred beneath the strip', (tester) async {
    final h = sleepy();
    await h.pump(tester, initial: '/crianca');

    expect(nightGround(tester), isTrue);
    final picture = tester.getRect(find.byType(SleepingTelinha));
    expect(picture.center.dx, closeTo(390 / 2, .5));
    expect(picture.top, greaterThan(tester.getRect(avatar).bottom));
    final line = find.text(SleepingTelinha.timeUp);
    final style = tester.widget<Text>(line).style;
    final text = Theme.of(tester.element(line)).textTheme;
    expect(style?.fontSize, text.titleLarge?.fontSize);
    expect(style?.color, Palette.kid.muted);
  });

  for (final (size, scale) in [
    (const Size(390, 844), 1.25),
    (const Size(1280, 800), 1.5),
  ]) {
    testWidgets('at ${size.width.toInt()} px the picture stands at '
        '${scale}x, as the empty home\'s', (tester) async {
      final h = sleepy();
      await h.pump(tester, initial: '/crianca', size: size);

      expect(tester.widget<AvatarDisc>(avatar).size, KidMosaic.avatar);
      final picture = expectPerched(
        tester,
        find.byType(SleepingTelinha),
        TeviLook.asleep,
        perch: Perch.wire,
        night: true,
      );
      expect(tester.getSize(picture), ShelfPicture.size * scale);
    });
  }

  testWidgets('asleep, only the exit can be acted on; no YouTube logo, no '
      'minutes shown or read', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = sleepy();
    await h.pump(tester, initial: '/crianca');

    expect(actionable(tester).map((n) => n.label), [HoldToExit.label]);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.textContaining('min'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'\d')), findsNothing);
    // The picture is read by its line.
    expect(find.bySemanticsLabel(SleepingTelinha.timeUp), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the sleeping picture: the mascot asleep in its night colours '
      'on a short wire, thin and dark, no screen and no words of its own', (
    tester,
  ) async {
    final h = sleepy();
    await h.pump(tester, initial: '/crianca');

    final picture = expectPerched(
      tester,
      find.byType(SleepingTelinha),
      TeviLook.asleep,
      perch: Perch.wire,
      night: true,
    );
    expect(
      find.descendant(of: picture, matching: find.byType(Text)),
      findsNothing,
    );
    // The wire runs the picture's screen from start to end, sagging gently.
    final s = ShelfPicture.screen;
    expect(ShelfPicture.wireAt(s.left), ShelfPicture.wireAt(s.right));
    expect(
      ShelfPicture.wireAt(s.center.dx),
      greaterThan(ShelfPicture.wireAt(s.left)),
    );
    expect(
      ShelfPicture.wireAt(s.center.dx) - ShelfPicture.wireAt(s.left),
      lessThan(s.width / 40),
    );
  });

  group('asleep, the home wakes by itself', () {
    testWidgets('every 60 s it reads the catalogue again, and the shelves '
        'come back once the time is ok', (tester) async {
      var time = day('time_up', 'daily');
      final h = sleepy(catalog: () => json(200, shelvesOn(time)));
      await h.pump(tester, initial: '/crianca');
      expect(catalogReads(h), 1);

      await tester.pump(const Duration(seconds: 59));
      expect(catalogReads(h), 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(catalogReads(h), 2);
      expect(find.byType(SleepingTelinha), findsOneWidget);

      time = day('ok');
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(catalogReads(h), 3);
      expect(find.byType(SleepingTelinha), findsNothing);
      expect(find.byType(ThemeBlock), findsNWidgets(2));

      // Awake, it reads no more on its own.
      await tester.pump(const Duration(minutes: 3));
      expect(catalogReads(h), 3);
    });

    testWidgets('back in the foreground it reads the catalogue again', (
      tester,
    ) async {
      var time = day('outside_window', 'window');
      final h = sleepy(catalog: () => json(200, shelvesOn(time)));
      await h.pump(tester, initial: '/crianca');

      time = day('ok');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(catalogReads(h), 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(catalogReads(h), 2);
      expect(find.byType(ThemeBlock), findsNWidgets(2));
    });

    testWidgets('while it reads, and if the read fails, the picture stays: '
        'no loading bars, no error note', (tester) async {
      FutureOr<http.Response> Function() answer = () =>
          json(200, shelvesOn(day('time_up', 'daily')));
      final h = sleepy(catalog: () => answer());
      await h.pump(tester, initial: '/crianca');

      final gate = Completer<http.Response>();
      answer = () => gate.future;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(catalogReads(h), 2);
      expect(find.byType(SleepingTelinha), findsOneWidget);
      expect(find.byType(MosaicLoading), findsNothing);

      gate.complete(problem(503, 'internal'));
      await tester.pumpAndSettle();
      expect(find.byType(SleepingTelinha), findsOneWidget);
      expect(find.byType(ShelvesFailed), findsNothing);

      // And it keeps trying.
      answer = () => json(200, shelvesOn(day('ok')));
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeBlock), findsNWidgets(2));
    });
  });

  group('the day running out while the child watches', () {
    final opened = json(201, {
      'play_id': 'p1',
      'youtube_id': 'yt1',
      'remaining_seconds': 600,
    });

    testWidgets('a play refused with time_up puts the home to sleep, '
        'reading the catalogue again, with no refusal note', (tester) async {
      var time = day('ok');
      final h = sleepy(
        catalog: () => json(200, shelvesOn(time)),
        other: (req) => req.url.path == '/v1/child/plays'
            ? problem(403, 'time_up')
            : http.Response('', 204),
      );
      await h.pump(tester, initial: '/crianca');
      time = day('time_up', 'daily');

      await tester.tap(find.byType(VideoTile).first);
      await tester.pumpAndSettle();

      expect(h.player.opened, isEmpty);
      expect(h.location(tester), '/crianca');
      expect(catalogReads(h), 2);
      expect(find.byType(KidErrorNote), findsNothing);
      expect(find.byType(SleepingTelinha), findsOneWidget);
    });

    testWidgets('a reopen refused with time_up leaves the player for the '
        'sleeping home', (tester) async {
      var time = day('ok');
      var plays = 0;
      final h = sleepy(
        catalog: () => json(200, shelvesOn(time)),
        other: (req) {
          final path = req.url.path;
          if (path == '/v1/child/plays') {
            return plays++ == 0 ? opened : problem(403, 'time_up');
          }
          if (path.endsWith('/beat')) return problem(409, 'play_closed');
          return http.Response('', 204);
        },
      );
      await h.pump(tester, initial: '/crianca');
      await tester.tap(find.byType(VideoTile).first);
      await tester.pumpAndSettle();
      time = day('time_up', 'daily');

      h.player.current!.emit(const PlayerPlaying());
      await tester.pumpAndSettle();

      expect(h.player.current!.closed, isTrue);
      expect(h.location(tester), '/crianca');
      expect(catalogReads(h), 2);
      expect(find.byType(KidErrorNote), findsNothing);
      expect(find.byType(SleepingTelinha), findsOneWidget);
    });

    testWidgets('a player opened without a play, refused with time_up, '
        'lands on the sleeping home with no note', (tester) async {
      var time = day('ok');
      final h = sleepy(
        catalog: () => json(200, shelvesOn(time)),
        other: (req) {
          if (req.url.path != '/v1/child/plays') return http.Response('', 204);
          time = day('time_up', 'daily');
          return problem(403, 'time_up');
        },
      );
      await h.pump(tester, initial: '/crianca/assistir/v2');

      expect(h.player.opened, isEmpty);
      expect(h.location(tester), '/crianca');
      expect(catalogReads(h), 2);
      expect(find.byType(KidErrorNote), findsNothing);
      expect(find.byType(SleepingTelinha), findsOneWidget);
    });

    testWidgets('a beat saying the time is up never stops the video', (
      tester,
    ) async {
      final h = sleepy(
        catalog: () => json(200, shelvesOn(day('ok'))),
        other: (req) {
          final path = req.url.path;
          if (path == '/v1/child/plays') return opened;
          if (path.endsWith('/beat')) {
            return json(200, day('time_up', 'daily'));
          }
          return http.Response('', 204);
        },
      );
      await h.pump(tester, initial: '/crianca');
      await tester.tap(find.byType(VideoTile).first);
      await tester.pumpAndSettle();

      h.player.current!.emit(const PlayerPlaying());
      await tester.pump();
      await tester.pump(const Duration(seconds: 90));

      expect(h.player.current!.calls, isNot(contains('pause')));
      expect(h.player.current!.closed, isFalse);
      expect(h.location(tester), '/crianca/assistir/v1');
    });
  });

  group('back from the player, the home reads the catalogue quietly', () {
    final opened = json(201, {
      'play_id': 'p1',
      'youtube_id': 'yt1',
      'remaining_seconds': 600,
    });

    /// A child watching v1 whose catalogue answers [catalog].
    Future<Harness> watchingWith(
      WidgetTester tester,
      FutureOr<http.Response> Function() catalog,
    ) async {
      final h = sleepy(
        catalog: catalog,
        other: (req) =>
            req.url.path == '/v1/child/plays' ? opened : http.Response('', 204),
      );
      await h.pump(tester, initial: '/crianca');
      await tester.tap(find.byType(VideoTile).first);
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('a video ending past the limit lands on the sleeping home, '
        'the shelves kept while it reads', (tester) async {
      FutureOr<http.Response> Function() answer = () =>
          json(200, shelvesOn(day('ok')));
      final h = await watchingWith(tester, () => answer());
      final gate = Completer<http.Response>();
      answer = () => gate.future;

      h.player.current!.emit(const PlayerEnded());
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');
      expect(catalogReads(h), 2);
      expect(find.byType(ThemeBlock), findsNWidgets(2));
      expect(find.byType(MosaicLoading), findsNothing);

      gate.complete(json(200, shelvesOn(day('time_up', 'daily'))));
      await tester.pumpAndSettle();
      expect(find.byType(SleepingTelinha), findsOneWidget);
    });

    testWidgets('back from the player past the limit sleeps too', (
      tester,
    ) async {
      var time = day('ok');
      final h = await watchingWith(tester, () => json(200, shelvesOn(time)));
      time = day('outside_window', 'window');

      await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
      await tester.pumpAndSettle();

      expect(catalogReads(h), 2);
      expect(find.text(SleepingTelinha.outsideWindow), findsOneWidget);
    });

    testWidgets('with time left the shelves stay where they were, and a '
        'failed read keeps them', (tester) async {
      FutureOr<http.Response> Function() answer = () =>
          json(200, shelvesOn(day('ok')));
      final h = sleepy(
        catalog: () => answer(),
        other: (req) =>
            req.url.path == '/v1/child/plays' ? opened : http.Response('', 204),
      );
      await h.pump(tester, initial: '/crianca');
      final tile = find.byType(VideoTile).at(1);
      final before = tester.getRect(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      answer = () => problem(503, 'internal');
      await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
      await tester.pumpAndSettle();

      expect(catalogReads(h), 2);
      expect(find.byType(ShelvesFailed), findsNothing);
      expect(find.byType(ThemeBlock), findsNWidgets(2));
      expect(tester.getRect(tile), before);
    });
  });

  testWidgets('an empty catalogue on a used-up day sleeps too', (tester) async {
    final h = sleepy(
      catalog: () => json(200, {'themes': [], 'time': day('time_up')}),
    );
    await h.pump(tester, initial: '/crianca');

    expect(find.byType(SleepingTelinha), findsOneWidget);
    expect(find.byType(EmptyShelf), findsNothing);
    expect(find.byType(KidErrorNote), findsNothing);
  });

  group('the resting home\'s mascot falls asleep as it arrives', () {
    const ms = Duration(milliseconds: 1);

    testWidgets('awake at first, it does not blink; after a beat its eye '
        'closes over the sleep\'s length, then the marks show and it stays '
        'still', (tester) async {
      runLoops();
      await pumpOn(
        tester,
        const SleepingTelinha(state: KidTimeState.timeUp),
        ground: Ground.kid,
      );
      expect(drawn(tester), TeviLook.watching, reason: 'awake on arrival');

      await tester.pump(ms * 80);
      expect(drawn(tester), TeviLook.watching, reason: 'no blink');
      await tester.pump(ms * 140);
      expect(drawn(tester), TeviLook.watching, reason: 'still the beat');

      await tester.pump(ms * 300);
      final midway = drawn(tester);
      expect(midway.lid, inExclusiveRange(0, 1), reason: 'closing');
      expect(midway.sleepMarks, isFalse);

      await tester.pump(ms * 300);
      expect(drawn(tester), TeviLook.asleep);
      await tester.pump(ms * 16);
      expect(drawn(tester), TeviLook.asleep);
      expect(tester.hasRunningAnimations, isFalse, reason: 'then still');
    });

    testWidgets('the marks never show before the eyelid is down', (
      tester,
    ) async {
      runLoops();
      await pumpOn(
        tester,
        const SleepingTelinha(state: KidTimeState.outsideWindow),
        ground: Ground.kid,
      );
      for (var t = 0; t < 900; t += 20) {
        final look = drawn(tester);
        if (look.lid < 1) expect(look.sleepMarks, isFalse, reason: '$t ms');
        await tester.pump(ms * 20);
      }
      expect(drawn(tester), TeviLook.asleep);
    });

    testWidgets('a paused profile\'s mascot falls asleep the same way', (
      tester,
    ) async {
      runLoops();
      await pumpOn(tester, const PausedProfile(), ground: Ground.kid);
      expect(drawn(tester), TeviLook.watching);
      await tester.pumpAndSettle();
      expect(drawn(tester), TeviLook.asleep);
    });

    testWidgets('it plays once: a rebuild, another reason to rest or the '
        'paused profile in its place does not wake it again', (tester) async {
      runLoops();
      final key = GlobalKey();
      final reason = ValueNotifier<KidTimeState?>(KidTimeState.timeUp);
      addTearDown(reason.dispose);
      await pumpOn(
        tester,
        ValueListenableBuilder(
          valueListenable: reason,
          builder: (context, state, _) => state == null
              ? PausedProfile(pictureKey: key)
              : SleepingTelinha(state: state, pictureKey: key),
        ),
        ground: Ground.kid,
      );
      await tester.pumpAndSettle();
      expect(drawn(tester), TeviLook.asleep);

      for (final next in [
        KidTimeState.timeUp,
        KidTimeState.outsideWindow,
        null,
        KidTimeState.timeUp,
      ]) {
        reason.value = next;
        // A notifier set to its own value does not rebuild: mark it.
        if (next == KidTimeState.timeUp) {
          tester.element(find.byType(ShelfPicture)).markNeedsBuild();
        }
        await tester.pump();
        expect(drawn(tester), TeviLook.asleep, reason: '$next');
        expect(tester.hasRunningAnimations, isFalse, reason: '$next');
      }
    });

    testWidgets('on the home it ends asleep, and the catalogue read again '
        'each minute never replays it', (tester) async {
      runLoops();
      final h = sleepy();
      await h.pump(tester, initial: '/crianca');
      expect(drawn(tester), TeviLook.asleep);

      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(catalogReads(h), 2);
      expect(drawn(tester), TeviLook.asleep);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('under reduced motion it is asleep from the first frame', (
      tester,
    ) async {
      runLoops();
      await pumpOn(
        tester,
        const SleepingTelinha(state: KidTimeState.timeUp),
        ground: Ground.kid,
        disableAnimations: true,
      );
      expect(drawn(tester), TeviLook.asleep);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with motion still, as in tests, asleep at once too', (
      tester,
    ) async {
      await pumpOn(
        tester,
        const SleepingTelinha(state: KidTimeState.timeUp),
        ground: Ground.kid,
      );
      expect(drawn(tester), TeviLook.asleep);
    });

    testWidgets('the floating note\'s small mascot is asleep at once', (
      tester,
    ) async {
      runLoops();
      await pumpOn(
        tester,
        const KidErrorNote('Agora não.', asleep: true, beside: true),
        ground: Ground.kid,
      );
      expect(drawn(tester), TeviLook.asleep);
    });
  });
}
