// The system bars over every ground, and the child's mode without them.
//
// On Android 15 and later the app draws behind the navigation bar, and
// the system lays a light scrim behind its buttons unless the app asks
// for none; the icons must then contrast with the ground beneath. The
// navigation bar's style is sampled from the layer at the foot of the
// screen, as the engine does.
//
// While a child holds the device the system bars are hidden (immersive,
// sticky), from the hand-over until an adult gives the PIN.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/shell/system_bars.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../kid/kid_exit_screen_test.dart' show exitGate, submit;
import '../kid/kid_home_screen_test.dart' show kidHome;
import '../kid/player_fullscreen_screen_test.dart'
    show barsShown, immersive, modesAsked, sideways, upright;
import '../kid/player_screen_test.dart' show watching;
import '../kid_mode/hand_over_screen_test.dart' show handOver, pumpUntil, tapOn;

SystemUiOverlayStyle? navigationBarStyle(WidgetTester tester) {
  final view = tester.binding.renderViews.first;
  final foot = Offset(view.size.width / 2, view.size.height - 1);
  return view.debugLayer!.find<SystemUiOverlayStyle>(foot);
}

/// A transparent bar, no scrim, its icons of [icons].
void expectClearBar(WidgetTester tester, {required Brightness icons}) {
  final style = navigationBarStyle(tester)!;
  expect(style.systemNavigationBarColor, const Color(0x00000000));
  expect(style.systemNavigationBarDividerColor, const Color(0x00000000));
  expect(style.systemNavigationBarContrastEnforced, isFalse);
  expect(style.systemNavigationBarIconBrightness, icons);
}

void main() {
  group('the navigation bar', () {
    testWidgets('over a guardian screen in the light theme: clear, dark '
        'icons', (tester) async {
      await Harness().pump(tester, initial: '/entrar');

      expectClearBar(tester, icons: Brightness.dark);
    });

    testWidgets('over a guardian screen in the dark theme: clear, light '
        'icons', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await Harness().pump(tester, initial: '/entrar');

      expectClearBar(tester, icons: Brightness.light);
    });

    testWidgets('over the family home and its navigation: clear, dark '
        'icons', (tester) async {
      final h = Harness(signedIn: true)..family = ownerFamily;
      await h.pump(tester);

      expectClearBar(tester, icons: Brightness.dark);
    });

    testWidgets('over the child\'s home: clear, light icons', (tester) async {
      await kidHome(tester);

      expectClearBar(tester, icons: Brightness.light);
    });

    testWidgets('over a light child\'s ground (a theme\'s world): clear, '
        'dark icons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: KidLayout(ground: BrandColors.sun, child: SizedBox()),
        ),
      );

      expectClearBar(tester, icons: Brightness.dark);
      expect(
        navigationBarStyle(tester)!.statusBarIconBrightness,
        Brightness.dark,
      );
    });

    test('the style asks for no scrim over the status bar either', () {
      final style = barsOver(Brightness.light);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
      expect(style.systemStatusBarContrastEnforced, isFalse);
    });
  });

  group('the child\'s mode', () {
    testWidgets('opened outside it, the app shows the bars, drawn edge to '
        'edge', (tester) async {
      final modes = modesAsked(tester);
      await Harness().pump(tester, initial: '/entrar');

      expect(modes, [barsShown]);
    });

    testWidgets('opened in it, the bars hide', (tester) async {
      final modes = modesAsked(tester);
      await kidHome(tester);

      expect(modes.last, immersive);
    });

    testWidgets('the hand-over hides the bars', (tester) async {
      final modes = modesAsked(tester);
      final h = await handOver(tester);
      expect(modes, [barsShown]);
      await tapOn(tester, find.text('Lia'));

      await tester.tap(find.text('Entregar para Lia'));
      await pumpUntil(tester, () => h.services.appMode.mode is SharedKid);
      await tester.pumpAndSettle();

      expect(modes, [barsShown, immersive]);
    });

    testWidgets('the PIN gate keeps them hidden; the PIN brings them back', (
      tester,
    ) async {
      final modes = modesAsked(tester);
      final h = await exitGate(tester);
      expect(modes.last, immersive);
      final before = modes.length;

      await submit(tester, '2580');
      await pumpUntil(tester, () => h.services.appMode.mode is Guardian);
      await tester.pumpAndSettle();

      expect(modes.sublist(before), [barsShown]);
    });

    testWidgets('the player turned sideways and back keeps them hidden', (
      tester,
    ) async {
      final modes = modesAsked(tester);
      await watching(tester, size: sideways);
      expect(modes, [barsShown, immersive], reason: 'the mode\'s alone');

      tester.view.physicalSize = upright;
      await tester.pumpAndSettle();

      expect(modes, [barsShown, immersive]);
    });

    testWidgets('on iOS the mode leaves the bars to the screens', (
      tester,
    ) async {
      final modes = modesAsked(tester);
      await kidHome(tester);

      expect(modes, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
