import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';

import 'pump.dart' show brandAssets;

Tevi figure(WidgetTester tester) => tester.widget<Tevi>(find.byType(Tevi));

/// The mascot's drawn body and legs on screen: from the body's top to the
/// legs' end, from the body's start to its end.
Rect bodyOf(WidgetTester tester) {
  final box = tester.getRect(find.byType(Tevi));
  final size = box.width;
  return Rect.fromLTRB(
    box.left + TeviPainter.body.left * size,
    box.top + TeviPainter.body.top * size,
    box.left + TeviPainter.body.right * size,
    box.top + TeviPainter.perchY * size,
  );
}

void main() {
  wideAtLargeText();
  wordmarkInTheField();
  perchedOnTheField();
  winkToConfirm();
}

Future<void> pumpWide(WidgetTester tester, FieldSize size, double scale) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(1280, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: FieldLayout(title: 'Título', size: size, children: const []),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void wideAtLargeText() {
  group('the wide panel at large text sizes behaves as the narrow field', () {
    testWidgets('at 100 % the panel carries the promise', (tester) async {
      await pumpWide(tester, FieldSize.band, 1);
      expect(find.text(promiseLine), findsOneWidget);
    });

    testWidgets('a task screen at 200 %: the panel carries no promise, as '
        'the band carries none, so nothing is clipped at its foot', (
      tester,
    ) async {
      await pumpWide(tester, FieldSize.band, 2);
      expect(find.text(promiseLine), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hero screen at 200 %: the promise moves under the title, '
        'as on the compact narrow hero', (tester) async {
      await pumpWide(tester, FieldSize.hero, 2);
      expect(find.text(promiseLine), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(promiseLine)).dy,
        greaterThan(tester.getBottomLeft(find.text('Título')).dy),
      );
      expect(
        tester.getTopLeft(find.text(promiseLine)).dx,
        greaterThan(1280 * 0.46),
        reason: 'in the task column, not the panel',
      );
    });
  });
}

// The mascot stands above the ink field, so the field carries the
// wordmark alone, as its name plate: starting under the mascot's body, on
// the edge the text below it keeps, and never the smallest text in it.
void wordmarkInTheField() {
  group('the field carries the wordmark, not a second mark', () {
    for (final (name, size, width, back, floor, direction) in [
      ('narrow band', FieldSize.band, 390.0, false, 20.0, TextDirection.ltr),
      (
        'narrow band with a back control',
        FieldSize.band,
        320.0,
        true,
        20.0,
        TextDirection.ltr,
      ),
      ('narrow hero', FieldSize.hero, 390.0, false, 26.0, TextDirection.ltr),
      (
        'narrow hero with a back control',
        FieldSize.hero,
        320.0,
        true,
        26.0,
        TextDirection.ltr,
      ),
      ('wide panel', FieldSize.hero, 1280.0, false, 26.0, TextDirection.ltr),
      (
        'narrow band, right to left',
        FieldSize.band,
        390.0,
        false,
        20.0,
        TextDirection.rtl,
      ),
      (
        'narrow band with a back control, right to left',
        FieldSize.band,
        320.0,
        true,
        20.0,
        TextDirection.rtl,
      ),
      (
        'narrow hero, right to left',
        FieldSize.hero,
        390.0,
        false,
        26.0,
        TextDirection.rtl,
      ),
    ]) {
      testWidgets('the $name starts the wordmark under the mascot, at '
          'least $floor tall, clear of it', (tester) async {
        await pumpField(
          tester,
          size: size,
          width: width,
          back: back,
          direction: direction,
        );

        final assets = brandAssets(tester, find.byType(FieldLayout));
        expect(assets.map((a) => a.$1), [
          'assets/brand/telinha-segura-wordmark-color-on-dark.svg',
        ]);
        final wordmark = find.byType(SvgPicture);
        expect(tester.getSize(wordmark).height, greaterThanOrEqualTo(floor));
        final rtl = direction == TextDirection.rtl;
        final plate = tester.getRect(wordmark);
        // The edge a line starts from: the left, or the right mirrored.
        double start(Rect r) => rtl ? r.right : r.left;
        // How far [r] starts past [edge], read in the line's direction.
        double past(Rect r, double edge) =>
            rtl ? edge - start(r) : start(r) - edge;
        final field = tester.getRect(find.byKey(FieldLayout.fieldKey));
        final box = tester.getRect(find.byType(Tevi));
        final bodyStart = rtl
            ? box.right - TeviPainter.body.left * box.width
            : box.left + TeviPainter.body.left * box.width;
        if (size == FieldSize.band && back) {
          // On a band the back control keeps the start; the name plate
          // follows its target at the band's own spacing.
          final control = tester.getRect(
            find.ancestor(
              of: find.byTooltip('Voltar'),
              matching: find.byType(IconButton),
            ),
          );
          expect(
            past(plate, rtl ? control.left : control.right),
            moreOrLessEquals(Space.sm, epsilon: .01),
          );
          expect(control.overlaps(plate), isFalse);
        } else {
          expect(
            start(plate),
            moreOrLessEquals(bodyStart, epsilon: .01),
            reason: 'the name plate starts under the mascot\'s body',
          );
          expect(
            past(plate, start(field)),
            moreOrLessEquals(TeviPainter.perchInset, epsilon: .01),
            reason: 'on the field content\'s inset',
          );
        }
        if (find.text(promiseLine).evaluate().isNotEmpty) {
          expect(
            start(tester.getRect(find.text(promiseLine))),
            moreOrLessEquals(start(plate), epsilon: .01),
            reason: 'the promise below keeps the same edge',
          );
        }
        expect(
          bodyOf(tester).overlaps(plate),
          isFalse,
          reason: 'the mascot stands above the name plate',
        );
        expect(find.bySemanticsLabel('Telinha Segura'), findsOneWidget);
        if (back) {
          final control = tester.getRect(find.byTooltip('Voltar'));
          expect(control.overlaps(plate), isFalse);
        }
      });
    }
  });
}

Future<void> pumpField(
  WidgetTester tester, {
  required FieldSize size,
  required double width,
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool back = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  final view = Size(width, 844);
  tester.view.physicalSize = view;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(size: view, textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: FieldLayout(
            title: 'Título',
            size: size,
            onBack: back ? () {} : null,
            children: const [],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void perchedOnTheField() {
  group('the mascot stands on the field\'s top edge', () {
    for (final (name, size, width, scale, back, side) in [
      ('narrow hero', FieldSize.hero, 390.0, 1.0, false, FieldSizes.heroTevi),
      ('narrow band', FieldSize.band, 390.0, 1.0, false, FieldSizes.bandTevi),
      (
        'band at 320 with back',
        FieldSize.band,
        320.0,
        1.0,
        true,
        FieldSizes.bandTevi,
      ),
      // At large text the hero shrinks to the band, and so does its mascot.
      ('hero at 200 %', FieldSize.hero, 390.0, 2.0, false, FieldSizes.bandTevi),
      (
        'wide panel at 840',
        FieldSize.band,
        840.0,
        1.0,
        true,
        FieldSizes.heroTevi,
      ),
      (
        'wide panel at 1200',
        FieldSize.hero,
        1200.0,
        1.0,
        false,
        FieldSizes.heroTevi,
      ),
      (
        'wide panel at 200 %',
        FieldSize.hero,
        1200.0,
        2.0,
        false,
        FieldSizes.heroTevi,
      ),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets('$name, ${brightness.name}: whole, watching, at the '
            'start, its legs on the edge', (tester) async {
          await pumpField(
            tester,
            size: size,
            width: width,
            brightness: brightness,
            scale: scale,
            back: back,
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(PerchedTevi), findsOneWidget);
          final tevi = figure(tester);
          expect(tevi.look, TeviLook.watching);
          expect(tevi.tier, TeviTier.full);
          expect(tevi.size, side);
          // On the dark theme's ground the dark parts take the night
          // colours; on cream, the day's.
          expect(tevi.night, brightness == Brightness.dark);

          final field = tester.getRect(find.byKey(FieldLayout.fieldKey));
          final ink =
              tester
                      .widget<DecoratedBox>(find.byKey(FieldLayout.fieldKey))
                      .decoration
                  as BoxDecoration;
          // The entry field, on a phone or as the wide panel, keeps the
          // larger corner; the band, the softer one.
          expect(
            ink.borderRadius,
            BorderRadius.circular(
              side == FieldSizes.heroTevi
                  ? FieldSizes.heroCorner
                  : FieldSizes.bandCorner,
            ),
          );
          final body = bodyOf(tester);
          expect(
            body.bottom - field.top,
            moreOrLessEquals(TeviPainter.perchOverlap, epsilon: .01),
            reason: 'the legs land on the edge, a little into the field',
          );
          expect(TeviPainter.perchOverlap, inInclusiveRange(1, 3));
          expect(
            body.left,
            moreOrLessEquals(field.left + Space.xl, epsilon: .01),
            reason: 'at the start, on the field content\'s inset',
          );
          expect(body.top, greaterThanOrEqualTo(0), reason: 'whole');
          expect(
            body.top,
            lessThan(field.top),
            reason: 'above the field, not inside it',
          );
        });
      }
    }

    testWidgets('right to left, it stands at the start and faces the '
        'content', (tester) async {
      await pumpField(
        tester,
        size: FieldSize.band,
        width: 390,
        direction: TextDirection.rtl,
      );

      final field = tester.getRect(find.byKey(FieldLayout.fieldKey));
      final box = tester.getRect(find.byType(Tevi));
      // Mirrored: the body's start edge is now on the right.
      final bodyStart = box.right - TeviPainter.body.left * box.width;
      expect(bodyStart, moreOrLessEquals(field.right - Space.xl, epsilon: .01));
      final flip = find.ancestor(
        of: find.byType(Tevi),
        matching: find.byType(Transform),
      );
      expect(
        tester.widget<Transform>(flip.first).transform.storage[0],
        -1,
        reason: 'turned to face the content',
      );
    });

    testWidgets('the band the hand-over leaves from is the narrow band\'s '
        'field', (tester) async {
      await pumpField(tester, size: FieldSize.band, width: 390);

      expect(
        tester.getRect(find.byKey(FieldLayout.fieldKey)),
        guardianBand(const Size(390, 844), EdgeInsets.zero).outerRect,
      );
    });
  });
}

void winkToConfirm() {
  group('a confirmation winks', () {
    Future<ValueNotifier<bool>> pumpToggle(
      WidgetTester tester, {
      bool still = false,
    }) async {
      final wink = ValueNotifier(false);
      addTearDown(wink.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: still),
              child: ValueListenableBuilder(
                valueListenable: wink,
                builder: (_, on, _) =>
                    FieldLayout(title: 'Título', wink: on, children: const []),
              ),
            ),
          ),
        ),
      );
      return wink;
    }

    testWidgets('it closes, holds and opens its eye once over the wink\'s '
        'duration when a confirmation turns on in place', (tester) async {
      final wink = await pumpToggle(tester);
      expect(figure(tester).look, TeviLook.watching, reason: 'at rest');

      wink.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final closing = figure(tester).look.lid;
      expect(closing, inExclusiveRange(0, 1));

      await tester.pump(const Duration(milliseconds: 500));
      expect(figure(tester).look, TeviLook.winking, reason: 'closed');

      await tester.pump(const Duration(milliseconds: 500));
      final opening = figure(tester).look.lid;
      expect(opening, inExclusiveRange(0, 1));

      await tester.pump(const Duration(milliseconds: 300));
      expect(figure(tester).look, TeviLook.watching, reason: 'ends open');
      // The controller notices it is done on the next frame.
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isFalse);
      expect(PerchedTevi.winkDuration, const Duration(milliseconds: 1400));
    });

    testWidgets('a screen shown as a confirmation winks on arrival, once', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const FieldLayout(title: 'Título', wink: true, children: []),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(figure(tester).look, TeviLook.winking);

      await tester.pumpAndSettle();
      expect(figure(tester).look, TeviLook.watching);
      await tester.pump(const Duration(seconds: 2));
      expect(figure(tester).look, TeviLook.watching, reason: 'only once');
    });

    testWidgets('under reduced motion it shows the closed eye for the '
        'wink\'s duration without animating, then the open eye', (
      tester,
    ) async {
      final wink = await pumpToggle(tester, still: true);

      wink.value = true;
      await tester.pump();
      expect(figure(tester).look, TeviLook.winking);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pump(const Duration(milliseconds: 700));
      expect(figure(tester).look, TeviLook.winking);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pump(const Duration(milliseconds: 700));
      expect(figure(tester).look, TeviLook.watching);
    });

    for (final still in [false, true]) {
      testWidgets('leaving mid-wink${still ? ' under reduced motion' : ''} '
          'leaves nothing running', (tester) async {
        final wink = await pumpToggle(tester, still: still);
        wink.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      });
    }
  });
}
