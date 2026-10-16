import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/espiadinha.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/theme.dart';

double headRise(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<EspiadinhaPainter>()
    .single
    .rise;

void main() {
  wideAtLargeText();
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
