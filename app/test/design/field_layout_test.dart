import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/espiadinha.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/theme.dart';

import 'pump.dart' show brandAssets;

double headRise(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<EspiadinhaPainter>()
    .single
    .rise;

void main() {
  wideAtLargeText();
  wordmarkInTheField();
  testWidgets('"o sol sobe" plays when rise turns on in a layout already '
      'shown (a confirmation on the same screen)', (tester) async {
    final rise = ValueNotifier(false);
    addTearDown(rise.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ValueListenableBuilder(
          valueListenable: rise,
          builder: (_, on, _) =>
              FieldLayout(title: 'Título', rise: on, children: const []),
        ),
      ),
    );
    expect(headRise(tester), 1, reason: 'shown in place at rest');

    rise.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(headRise(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(headRise(tester), 1);
  });
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

// The head already peeks over the ink field, so the field carries the
// wordmark alone, as its name plate: centred under the head, and never
// the smallest text in the field.
void wordmarkInTheField() {
  group('the field carries the wordmark, not a second mark', () {
    for (final (name, size, width, back, floor) in [
      ('narrow band', FieldSize.band, 390.0, false, 20.0),
      ('narrow band with a back control', FieldSize.band, 320.0, true, 20.0),
      ('narrow hero', FieldSize.hero, 390.0, false, 26.0),
      ('narrow hero with a back control', FieldSize.hero, 320.0, true, 26.0),
      ('wide panel', FieldSize.hero, 1280.0, false, 26.0),
    ]) {
      testWidgets('the $name centres the reversed wordmark under the head, '
          'at least $floor tall', (tester) async {
        final view = Size(width, 844);
        tester.view.physicalSize = view;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: FieldLayout(
              title: 'Título',
              size: size,
              onBack: back ? () {} : null,
              children: const [],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final assets = brandAssets(tester, find.byType(FieldLayout));
        expect(assets.map((a) => a.$1), [
          'assets/brand/telinha-segura-wordmark-reversed.svg',
        ]);
        final wordmark = find.byType(SvgPicture);
        expect(tester.getSize(wordmark).height, greaterThanOrEqualTo(floor));
        expect(
          tester.getCenter(wordmark).dx,
          moreOrLessEquals(
            tester.getCenter(find.byType(PeekingHead)).dx,
            epsilon: 2,
          ),
        );
        expect(find.bySemanticsLabel('Telinha Segura'), findsOneWidget);
        if (back) {
          // The back control keeps the start, clear of the name plate.
          final control = tester.getRect(find.byTooltip('Voltar'));
          expect(control.left, lessThan(tester.getRect(wordmark).left));
          expect(control.overlaps(tester.getRect(wordmark)), isFalse);
        }
      });
    }
  });
}
