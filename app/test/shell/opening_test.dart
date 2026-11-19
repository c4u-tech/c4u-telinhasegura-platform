import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/shell/splash.dart';

import '../access/harness.dart';
import '../design/pump.dart';
import '../family/fixtures.dart';

/// The opening's mascot, as drawn now.
Tevi mascot(WidgetTester tester) => tester.widget<Tevi>(
  find.descendant(of: find.byType(Splash), matching: find.byType(Tevi)),
);

TeviAssembly assembly(WidgetTester tester) => mascot(tester).assembly;

/// A guardian whose every read answers after [delay].
Harness guardian({Duration delay = Duration.zero}) =>
    Harness(kind: ClientKind.mobile, signedIn: true, sessionDelay: delay)
      ..family = ownerFamily;

/// Starts the app and lets its first frame pass: the opening's clock
/// stands at zero.
Future<void> start(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(h.app());
  await tester.pump();
}

/// Moves the clock to [ms] after the opening started at [from].
Future<int> at(WidgetTester tester, int from, int ms) async {
  await tester.pump(Duration(milliseconds: ms - from));
  return ms;
}

/// Lets the screens' own reads, which wait out the same delay, answer
/// before the test ends.
Future<void> finish(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 5));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(playOpening);

  testWidgets('the mascot assembles from its body over the ink ground, '
      'within the opening\'s length', (tester) async {
    final h = guardian(delay: const Duration(seconds: 2));
    await start(tester, h);

    expect(assembly(tester), TeviAssembly.body);
    expect(
      tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(Splash),
              matching: find.byType(ColoredBox),
            ),
          )
          .first
          .color,
      BrandColors.ink,
    );
    expect(find.bySemanticsLabel('Carregando'), findsOneWidget);

    var now = await at(tester, 0, 250);
    expect(assembly(tester).look, 0, reason: 'the look starts at 260 ms');

    now = await at(tester, now, 400);
    var a = assembly(tester);
    expect(a.look, inExclusiveRange(0, 1));
    expect(a.eye, 0);
    expect(a.legs, 0);
    expect(a.ends, 0);

    now = await at(tester, now, 700);
    a = assembly(tester);
    expect(a.look, 1);
    expect(a.eye, 1);
    expect(a.legs, 1);
    expect(a.ends, greaterThan(0));
    expect(mascot(tester).look.lid, 0);

    now = await at(tester, now, 920);
    expect(assembly(tester).ends, 1);
    expect(mascot(tester).look.lid, greaterThan(.5), reason: 'one blink');

    now = await at(tester, now, 1000);
    expect(assembly(tester), TeviAssembly.whole);
    expect(mascot(tester).look, TeviLook.watching);

    await finish(tester);
  });

  testWidgets('the body stands where the launch screen left it: its '
      'drawing centred, 192 across on Android and iOS alike', (tester) async {
    expect(Opening.markSide, 192);
    for (final (platform, side) in [
      (TargetPlatform.android, 192.0),
      (TargetPlatform.iOS, 192.0),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      final h = guardian(delay: const Duration(seconds: 2));
      await start(tester, h);
      final box = tester.getRect(find.byType(Tevi));
      expect(box.width, moreOrLessEquals(side));
      final centre = box.topLeft + TeviPainter.drawingCentre * side;
      expect(centre.dx, moreOrLessEquals(390 / 2));
      expect(centre.dy, moreOrLessEquals(844 / 2));
      await finish(tester);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a mode known early waits for the assembly, then the ground '
      'lifts away from the first screen within the band\'s length', (
    tester,
  ) async {
    final h = guardian();
    await start(tester, h);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.services.appMode.mode, const Guardian());

    await at(tester, 100, 900);
    expect(find.byType(Splash), findsOneWidget);
    expect(find.byType(FamilyHomeScreen), findsOneWidget, reason: 'beneath');
    expect(tester.getRect(find.byType(Splash)).top, 0);
    final beneath = tester.element(find.byType(FamilyHomeScreen));

    // The assembly ends a frame after its last instant; the lift starts
    // on the frame after that.
    await at(tester, 900, 1000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Splash), findsOneWidget, reason: 'lifting');
    expect(tester.getRect(find.byType(Splash)).top, lessThan(-400));

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(Splash), findsNothing);
    expect(
      tester.element(find.byType(FamilyHomeScreen)),
      same(beneath),
      reason: 'the screen shown is the one built beneath, not a new one',
    );
    expect(
      find.ancestor(
        of: find.byType(FamilyHomeScreen),
        matching: find.byType(Stack),
      ),
      findsNothing,
      reason: 'nothing is left painted over it',
    );
    await finish(tester);
  });

  test('the closing blink takes the scale\'s blink and ends the opening', () {
    final end = Motion.opening.inMilliseconds.toDouble();
    final blink = Motion.blink.inMilliseconds;
    expect(openingAt(end - blink - 1).$2.lid, 0);
    expect(openingAt(end - blink / 2).$2.lid, closeTo(1, 1e-9));
    expect(openingAt(end).$2.lid, 0);
  });

  testWidgets('a mode known during the assembly keeps the ground, and '
      '"Carregando", as they were: nothing is read twice', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = guardian(delay: const Duration(milliseconds: 200));
    await start(tester, h);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.services.appMode.mode, isNull);
    final cover = tester.element(find.byType(Splash));
    final read = tester.getSemantics(find.bySemanticsLabel('Carregando')).id;

    var now = 100;
    while (h.services.appMode.mode == null) {
      now = await at(tester, now, now + 50);
    }
    await tester.pump();
    expect(now, lessThan(900), reason: 'known during the assembly');
    expect(find.byType(FamilyHomeScreen), findsOneWidget, reason: 'beneath');
    expect(tester.element(find.byType(Splash)), same(cover));
    expect(tester.getSemantics(find.bySemanticsLabel('Carregando')).id, read);
    await finish(tester);
    semantics.dispose();
  });

  testWidgets('a mode that takes longer keeps the assembled mascot '
      'searching until it is known', (tester) async {
    final h = guardian(delay: const Duration(milliseconds: 1500));
    await start(tester, h);

    var now = await at(tester, 0, 1000);
    expect(assembly(tester), TeviAssembly.whole);
    await tester.pump(const Duration(milliseconds: 16));
    now += 16;
    expect(h.services.appMode.mode, isNull);
    expect(mascot(tester).searching, isTrue);

    now = await at(tester, now, 1400);
    expect(find.byType(Splash), findsOneWidget);
    expect(mascot(tester).searching, isTrue);

    while (h.services.appMode.mode == null) {
      now = await at(tester, now, now + 100);
    }
    final known = now;
    expect(find.byType(Splash), findsOneWidget, reason: 'it lifts away');
    await at(tester, now, known + 500);
    expect(find.byType(Splash), findsNothing);
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a failed read shows the note and its retry once the '
      'mascot is assembled; the retry plays no second opening', (tester) async {
    final h = guardian()..sessionFailure = 500;
    await start(tester, h);

    final now = await at(tester, 0, 500);
    expect(find.text('Tentar de novo'), findsNothing);
    expect(find.byType(Tevi), findsOneWidget);

    await at(tester, now, 1100);
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(find.byType(Tevi), findsNothing);

    h.sessionFailure = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Tentar de novo'));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(Splash), matching: find.byType(Tevi)),
      findsNothing,
      reason: 'no second assembly',
    );
    await tester.pumpAndSettle();
    expect(h.services.appMode.mode, const Guardian());
    expect(find.byType(Splash), findsNothing);
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  testWidgets('under reduced motion the whole mascot stands still and the '
      'first screen cuts in as soon as the mode is known', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = guardian(delay: const Duration(milliseconds: 300));
    await start(tester, h);

    expect(assembly(tester), TeviAssembly.whole);
    expect(mascot(tester).look, TeviLook.watching);
    expect(find.bySemanticsLabel('Carregando'), findsOneWidget);

    var now = 0;
    while (h.services.appMode.mode == null) {
      expect(assembly(tester), TeviAssembly.whole);
      now = await at(tester, now, now + 50);
    }
    await tester.pump();
    expect(find.byType(Splash), findsNothing);
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('coming back from the background shows no opening', (
    tester,
  ) async {
    final h = guardian();
    await start(tester, h);
    await tester.pumpAndSettle();
    expect(find.byType(Splash), findsNothing);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(find.byType(Splash), findsNothing);
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  testWidgets('a link pushed during the opening opens once it hands off', (
    tester,
  ) async {
    final h = guardian();
    await start(tester, h);

    const codec = JSONMethodCodec();
    ByteData? reply;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      codec.encodeMethodCall(
        const MethodCall('pushRouteInformation', {
          'location': 'telinhasegura://sugerir?texto=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ',
        }),
      ),
      (data) => reply = data,
    );
    expect(codec.decodeEnvelope(reply!), isTrue);

    await tester.pumpAndSettle();
    expect(find.byType(Splash), findsNothing);
    expect(
      h.location(tester),
      '/sugestoes/nova?link=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ',
    );
  });
}
