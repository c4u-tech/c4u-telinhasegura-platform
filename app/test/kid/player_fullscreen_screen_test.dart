import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/pack_player_screen.dart';
import 'package:telinha_segura/kid/player_keys.dart';

import 'pack_player_test.dart' as pack;
import 'player_screen_test.dart';

/// A phone turned sideways.
const sideways = Size(844, 390);

/// An upright phone.
const upright = Size(390, 844);

/// The system UI modes the app asked for, in order.
List<String> modesAsked(WidgetTester tester) {
  final modes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        modes.add(call.arguments as String);
      }
      // The manual mode with every overlay: the bars as the app booted.
      if (call.method == 'SystemChrome.setEnabledSystemUIOverlays' &&
          (call.arguments as List).length == SystemUiOverlay.values.length) {
        modes.add(barsShown);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return modes;
}

const immersive = 'SystemUiMode.immersiveSticky';

/// Flutter's own default, the mode the app boots in on every Android.
const barsShown = 'bars shown';

Finder get mark => find.bySemanticsLabel('Telinha Segura');

/// Nothing but the window: no strip, no mark, no exit, no keys.
void expectOnlyTheVideo(WidgetTester tester) {
  expect(playerView, findsOneWidget);
  expect(find.byType(HoldToExit), findsNothing);
  expect(mark, findsNothing);
  expect(find.byType(PlayerKey), findsNothing);
}

void main() {
  group('the single player on a phone turned sideways (fullscreen design)', () {
    testWidgets('only the video shows: no strip, mark, exit or keys', (
      tester,
    ) async {
      modesAsked(tester);
      await watching(tester, size: sideways);

      expectOnlyTheVideo(tester);
    });

    testWidgets('the window is whole at 16:9, centred, as tall as the screen, '
        'nothing over it and no gesture of ours on it', (tester) async {
      modesAsked(tester);
      await watching(tester, size: sideways);

      final window = tester.getRect(playerView);
      expect(window.height, sideways.height);
      expect(window.width / window.height, closeTo(16 / 9, 0.01));
      expect(window.center.dx, closeTo(sideways.width / 2, 0.5));
      expect(window.center.dy, closeTo(sideways.height / 2, 0.5));
      for (final type in [
        Stack,
        GestureDetector,
        RawGestureDetector,
        InkWell,
      ]) {
        expect(
          find.ancestor(of: playerView, matching: find.byType(type)),
          findsNothing,
          reason: '$type',
        );
      }
    });

    testWidgets('the window stays inside the safe area, clear of a notch', (
      tester,
    ) async {
      modesAsked(tester);
      tester.view.padding = const FakeViewPadding(
        left: 47,
        right: 47,
        bottom: 21,
      );
      addTearDown(tester.view.resetPadding);
      await watching(tester, size: sideways);

      final window = tester.getRect(playerView);
      expect(window.left, greaterThanOrEqualTo(47));
      expect(window.right, lessThanOrEqualTo(sideways.width - 47));
      expect(window.bottom, lessThanOrEqualTo(sideways.height - 21));
      // Centred on the screen: the home indicator's band above it too.
      expect(window.top, greaterThanOrEqualTo(21));
      expect(window.height, sideways.height - 42);
      expect(window.center.dy, closeTo(sideways.height / 2, 0.5));
    });

    testWidgets('the system bars hide while fullscreen, and come back '
        'upright, the video playing on, never reopened', (tester) async {
      final modes = modesAsked(tester);
      final h = await watching(tester, size: sideways);
      expect(modes, [immersive]);

      tester.view.physicalSize = upright;
      await tester.pumpAndSettle();

      expect(modes, [immersive, barsShown]);
      expect(find.byType(HoldToExit), findsOneWidget);
      expect(find.byType(PlayerKey), findsNWidgets(2));
      expect(h.player.opened, hasLength(1));
      expect(current(h).closed, isFalse);
      expect(current(h).calls, isEmpty);
    });

    testWidgets('upright first, the bars are never touched; turned, they '
        'hide', (tester) async {
      final modes = modesAsked(tester);
      await watching(tester, size: upright);
      expect(modes, isEmpty);

      tester.view.physicalSize = sideways;
      await tester.pumpAndSettle();

      expect(modes, [immersive]);
      expectOnlyTheVideo(tester);
    });

    testWidgets('the video\'s end brings the shelves and the bars back', (
      tester,
    ) async {
      final modes = modesAsked(tester);
      final h = await watching(tester, size: sideways);

      current(h).emit(const PlayerEnded());
      await tester.pumpAndSettle();

      expect(h.location(tester), '/crianca');
      expect(modes, [immersive, barsShown]);
    });

    testWidgets('a video that does not play leaves fullscreen: the note in '
        'the window\'s place, the strip and back beside it', (tester) async {
      final modes = modesAsked(tester);
      final h = await watching(tester, size: sideways);

      current(h).emit(const PlayerFailed());
      await tester.pump();
      await tester.pump();

      expect(find.byType(KidErrorNote), findsOneWidget);
      expect(find.byType(HoldToExit), findsOneWidget);
      expect(find.byType(PlayerKey), findsOneWidget);
      expect(modes, [immersive, barsShown]);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('on iOS too', (tester) async {
      final modes = modesAsked(tester);
      await watching(tester, size: sideways);

      expectOnlyTheVideo(tester);
      expect(modes, [immersive]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a tablet in landscape keeps the strip and the rail, the '
        'bars untouched', (tester) async {
      final modes = modesAsked(tester);
      await watching(tester, size: const Size(1280, 800));

      expect(find.byType(HoldToExit), findsOneWidget);
      expect(find.byType(PlayerKey), findsNWidgets(2));
      expect(modes, isEmpty);
    });

    testWidgets('a desktop platform keeps the rail at a phone\'s size', (
      tester,
    ) async {
      final modes = modesAsked(tester);
      await watching(tester, size: sideways);

      expect(find.byType(PlayerKey), findsNWidgets(2));
      expect(modes, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  group('a pacotinho on a phone turned sideways (fullscreen design)', () {
    testWidgets('its video shows alone: no progress, no keys', (tester) async {
      final modes = modesAsked(tester);
      await pack.inPack(tester, size: sideways);

      expectOnlyTheVideo(tester);
      expect(pack.progress(1, 3), findsNothing);
      expect(modes, [immersive]);
    });

    testWidgets('the breath keeps the strip, the rail and the progress, the '
        'bars back; the next video is fullscreen again', (tester) async {
      final modes = modesAsked(tester);
      final h = await pack.inPack(tester, size: sideways);

      await pack.end(tester, h);
      expect(find.byType(PackBreath), findsOneWidget);
      expect(find.byType(HoldToExit), findsOneWidget);
      expect(find.byType(PlayerKey), findsNWidgets(2));
      expect(pack.progress(1, 3), findsOneWidget);
      expect(modes, [immersive, barsShown]);

      await tester.tap(find.byType(PackBreath));
      await tester.pumpAndSettle();

      expectOnlyTheVideo(tester);
      expect(modes, [immersive, barsShown, immersive]);
    });

    testWidgets('the goodbye keeps the strip and back', (tester) async {
      final modes = modesAsked(tester);
      final h = await pack.inPack(tester, size: sideways);
      for (var i = 0; i < 2; i++) {
        await pack.end(tester, h);
        await tester.tap(find.byType(PackBreath));
        await tester.pumpAndSettle();
      }

      await pack.end(tester, h);

      expect(find.byType(PackGoodbye), findsOneWidget);
      expect(find.byType(HoldToExit), findsOneWidget);
      expect(find.byType(PlayerKey), findsOneWidget);
      expect(modes.last, barsShown);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });
}
