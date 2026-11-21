import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/shell/splash.dart';

import '../access/harness.dart';
import '../design/pump.dart';
import '../family/fixtures.dart';
import '../kid/kid_mosaic_test.dart' show pixel, sixThemes;
import '../parental/parental_api_test.dart' show profileJson;

const screen = Size(390, 844);

/// Where the opening's mascot stands: its drawing centred on the screen.
final opening =
    (screen.center(Offset.zero) -
        TeviPainter.drawingCentre * Opening.markSide) &
    const Size.square(Opening.markSide);

/// The mascot the opening draws now.
Finder get traveller =>
    find.descendant(of: find.byType(Splash), matching: find.byType(Tevi));

Tevi travelling(WidgetTester tester) => tester.widget<Tevi>(traveller.first);

/// The look a mascot found by [finder] is drawn with now.
TeviLook drawnBy(WidgetTester tester, Finder finder) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: finder,
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TeviPainter)
        .look;

/// Whether the mascot found by [finder] is painted, rather than held back
/// unseen.
bool painted(WidgetTester tester, Finder finder) => tester
    .widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )
    .every((o) => o.opacity > 0);

/// The ground's outline, as clipped now.
RRect groundShape(WidgetTester tester) =>
    (tester
                .widget<ClipPath>(
                  find.descendant(
                    of: find.byType(Splash),
                    matching: find.byType(ClipPath),
                  ),
                )
                .clipper!
            as BandClipper)
        .rrect;

void expectRect(Rect actual, Rect expected, {double within = 1}) {
  for (final (a, e) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(a, closeTo(e, within), reason: '$actual against $expected');
  }
}

const field = Rect.fromLTWH(20, 100, 350, 72);
const box = Rect.fromLTWH(40, 40, 72, 72);
final fieldKey = GlobalKey();
const landingKey = Key('landing');

/// A first screen with its own mascot standing on an ink field.
Widget perched({
  TeviLook look = TeviLook.crestUp,
  bool night = false,
  bool blinks = false,
}) => Stack(
  children: [
    Positioned.fromRect(
      rect: field,
      child: ColoredBox(key: fieldKey, color: BrandColors.ink),
    ),
    Positioned.fromRect(
      rect: box,
      child: TeviLanding(
        look: look,
        night: night,
        field: fieldKey,
        fieldCorner: 24,
        child: Tevi(
          key: landingKey,
          size: box.width,
          look: look,
          night: night,
          blinks: blinks,
        ),
      ),
    ),
  ],
);

Future<void> pumpOpening(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: (context, child) => Opening(ready: true, child: child!),
      home: Scaffold(body: home),
    ),
  );
  await tester.pump();
}

/// Plays the assembly; the lift starts on the frame after its end.
Future<void> toLift(WidgetTester tester) async {
  await tester.pump(Motion.opening);
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump();
}

void main() {
  setUp(playOpening);

  testWidgets('the opening\'s mascot travels onto the first screen\'s own, '
      'which shows only as it lands, in the same box and look', (tester) async {
    await pumpOpening(tester, perched());
    final landing = find.byKey(landingKey);
    final assembling = tester.element(traveller.first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(painted(tester, landing), isFalse, reason: 'beneath the ground');

    await toLift(tester);
    expect(tester.element(traveller.first), same(assembling));
    final leaving = tester.getRect(traveller.first);
    expect(leaving.width, lessThanOrEqualTo(opening.width));
    expect(leaving.width, greaterThan(opening.width * .8), reason: 'just off');

    await tester.pump(const Duration(milliseconds: 200));
    final midway = tester.getRect(traveller.first);
    expect(midway.width, inExclusiveRange(box.width, Opening.markSide));
    expect(midway.top, inExclusiveRange(box.top, opening.top));
    expect(painted(tester, landing), isFalse, reason: 'the travelling one');

    await tester.pump(const Duration(milliseconds: 170));
    expectRect(tester.getRect(traveller.first), box);
    expect(
      drawnBy(tester, traveller.first).crest,
      closeTo(TeviLook.crestUp.crest, .01),
      reason: 'it arrives with the look it lands on',
    );

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(Splash), findsNothing);
    expect(painted(tester, landing), isTrue);
    expect(tester.getRect(landing), box);
    expect(drawnBy(tester, landing), TeviLook.crestUp);
  });

  testWidgets('the ground closes onto the field the mascot stands on', (
    tester,
  ) async {
    await pumpOpening(tester, perched());
    await toLift(tester);
    final full = groundShape(tester);
    expectRect(full.outerRect, Offset.zero & screen);

    await tester.pump(const Duration(milliseconds: 200));
    final midway = groundShape(tester).outerRect;
    expect(midway.top, inExclusiveRange(0, field.top));
    expect(midway.height, inExclusiveRange(field.height, screen.height));

    await tester.pump(const Duration(milliseconds: 170));
    final last = groundShape(tester);
    expectRect(last.outerRect, field, within: 2);
    expect(last.tlRadiusX, closeTo(24, .5));
  });

  testWidgets('with no mascot on the first screen, the mascot rides the '
      'ground away', (tester) async {
    await pumpOpening(tester, const SizedBox.expand());
    await toLift(tester);
    await tester.pump(const Duration(milliseconds: 200));
    final mascot = tester.getRect(traveller.first);
    expect(mascot.width, moreOrLessEquals(Opening.markSide));
    final lifted = opening.top - mascot.top;
    expect(lifted, greaterThan(screen.height / 2));
    expectRect(groundShape(tester).outerRect, Offset.zero & screen);
    final ground = tester.getRect(
      find
          .descendant(
            of: find.byType(Splash),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(ground.top, closeTo(-lifted, 1), reason: 'they go together');
  });

  testWidgets('to a mascot standing on no field, the mascot travels while '
      'the ground lifts away', (tester) async {
    await pumpOpening(
      tester,
      Stack(
        children: [
          Positioned.fromRect(
            rect: box,
            child: TeviLanding(
              look: TeviLook.watching,
              night: false,
              child: Tevi(key: landingKey, size: box.width),
            ),
          ),
        ],
      ),
    );
    await toLift(tester);
    await tester.pump(const Duration(milliseconds: 200));
    final ground = tester.getRect(
      find
          .descendant(
            of: find.byType(Splash),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(ground.top, lessThan(-screen.height / 2), reason: 'lifting');
    expect(
      tester.getRect(traveller.first).width,
      inExclusiveRange(box.width, Opening.markSide),
    );
  });

  testWidgets('to a mascot in the night colours, the travelling one turns '
      'to them on the way', (tester) async {
    await pumpOpening(tester, perched(night: true));
    await toLift(tester);
    expect(
      tester.widgetList<Tevi>(traveller).map((t) => t.night),
      isNot(contains(true)),
    );

    await tester.pump(const Duration(milliseconds: 200));
    final night = find.descendant(
      of: find.byType(Splash),
      matching: find.byWidgetPredicate((w) => w is Tevi && w.night),
    );
    expect(night, findsOneWidget);
    final fade = tester.widget<Opacity>(
      find.ancestor(of: night, matching: find.byType(Opacity)).first,
    );
    expect(fade.opacity, inExclusiveRange(0, 1));
    expectRect(tester.getRect(night), tester.getRect(traveller.first));
  });

  testWidgets('the first screen\'s mascot plays its arrival once it has '
      'landed, not under the ground', (tester) async {
    await pumpOpening(tester, perched(look: TeviLook.watching, blinks: true));
    final landing = find.byKey(landingKey);
    await toLift(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(drawnBy(tester, landing).lid, 0, reason: 'held back');

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(Splash), findsNothing);
    await tester.pump(Motion.blink ~/ 2);
    expect(drawnBy(tester, landing).lid, greaterThan(.5), reason: 'one blink');
    await tester.pumpAndSettle();
    expect(drawnBy(tester, landing).lid, 0);
  });

  testWidgets('under reduced motion the first screen cuts in with its '
      'mascot shown', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpOpening(tester, perched());
    expect(find.byType(Splash), findsNothing);
    expect(painted(tester, find.byKey(landingKey)), isTrue);
  });

  group('the app\'s first screens', () {
    Future<void> handOff(WidgetTester tester, Finder own) async {
      // The mode is known early: the assembly plays, then the lift.
      await tester.pump(const Duration(milliseconds: 900));
      expect(own, findsOneWidget, reason: 'beneath the ground');
      expect(painted(tester, own), isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(painted(tester, own), isFalse, reason: 'the travelling one');
      await tester.pump(const Duration(milliseconds: 170));
      expectRect(tester.getRect(traveller.first), tester.getRect(own));
      expect(
        drawnBy(tester, traveller.first),
        isA<TeviLook>().having(
          (l) => l.crest,
          'crest',
          closeTo(drawnBy(tester, own).crest, .01),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(Splash), findsNothing);
      expect(painted(tester, own), isTrue);
    }

    testWidgets('the guardian\'s home: onto the mascot on its band, the '
        'ground becoming the band', (tester) async {
      final h = Harness(kind: ClientKind.mobile, signedIn: true)
        ..family = ownerFamily;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(h.app());
      await tester.pump();
      final own = find.descendant(
        of: find.byType(FamilyHomeScreen),
        matching: find.byType(Tevi),
      );
      await tester.pump(const Duration(milliseconds: 900));
      final band = tester.getRect(find.byKey(FieldLayout.fieldKey));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 370));
      expectRect(groundShape(tester).outerRect, band, within: 2);
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(Splash), findsNothing);
      expect(painted(tester, own), isTrue);

      // And again from the start, the mascot's own path.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(h.app());
      await tester.pump();
      await handOff(tester, own);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 5));
      }
    });

    testWidgets('the child\'s home: onto the mascot on its highlight', (
      tester,
    ) async {
      final h = Harness(
        kind: ClientKind.mobile,
        signedIn: true,
        api: (req) => switch (req.url.path) {
          '/v1/child/profile' => json(200, profileJson),
          '/v1/child/catalog' => json(200, sixThemes),
          final p when p.startsWith('/v1/child/thumbs/') => http.Response.bytes(
            pixel,
            200,
          ),
          _ => http.Response('', 204),
        },
      )..kidMode = {'minor_id': 'm1'};
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(h.app(initial: '/crianca'));
      await tester.pump();
      final own = find.descendant(
        of: find.byType(KidMosaic),
        matching: find.byType(Tevi),
      );
      await handOff(tester, own);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 5));
      }
    });
  });
}
