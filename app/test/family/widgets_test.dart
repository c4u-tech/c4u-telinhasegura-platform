import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/widgets.dart';

Future<void> pumpIn(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 640),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            child: Column(children: [child]),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('CapacityRow', () {
    testWidgets('one module per place, filled per taken one', (tester) async {
      await pumpIn(
        tester,
        const CapacityRow(filled: 2, total: 10, words: '2 de 10 crianças'),
      );
      final modules = tester.widgetList<StateModule>(find.byType(StateModule));
      expect(modules.map((m) => m.filled), [
        true,
        true,
        for (var i = 0; i < 8; i++) false,
      ]);
      expect(find.text('2 de 10 crianças'), findsOneWidget);
    });

    testWidgets('assistive technology reads the words only', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpIn(
        tester,
        const CapacityRow(filled: 3, total: 6, words: '3 de 6 vagas'),
      );
      expect(
        tester.getSemantics(find.byType(CapacityRow)),
        matchesSemantics(label: '3 de 6 vagas'),
      );
      semantics.dispose();
    });

    testWidgets('the words sit on their own line under the modules, at '
        'any width, so every door lays out the same', (tester) async {
      for (final size in [const Size(360, 640), const Size(1280, 800)]) {
        await pumpIn(
          tester,
          const CapacityRow(filled: 3, total: 6, words: '3 de 6 vagas'),
          size: size,
        );
        final modules = find.byType(StateModule);
        expect(
          tester.getTopLeft(find.text('3 de 6 vagas')).dy,
          greaterThan(tester.getBottomLeft(modules.first).dy),
          reason: '$size',
        );
        expect(
          tester.getTopLeft(find.text('3 de 6 vagas')).dx,
          tester.getTopLeft(modules.first).dx,
          reason: '$size',
        );
      }
    });

    testWidgets('wraps at 200% text on a phone without overflow', (
      tester,
    ) async {
      await pumpIn(
        tester,
        const CapacityRow(filled: 10, total: 10, words: '10 de 10 crianças'),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      // The words drop below the modules rather than squeezing them.
      expect(
        tester.getTopLeft(find.text('10 de 10 crianças')).dy,
        greaterThan(tester.getBottomLeft(find.byType(StateModule).first).dy),
      );
    });
  });

  group('DoorRow', () {
    testWidgets('the whole row, at least 72 dp tall, opens its door', (
      tester,
    ) async {
      var opened = 0;
      await pumpIn(
        tester,
        DoorRow(
          title: 'Crianças',
          semanticsLabel: 'Crianças, 2 de 10 crianças',
          onTap: () => opened++,
          child: const Text('2 de 10 crianças'),
        ),
      );
      final row = find.byType(DoorRow);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(72));
      expect(tester.getSize(row).width, 312);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await tester.tapAt(tester.getTopRight(row) + const Offset(-4, 4));
      await tester.tap(find.text('2 de 10 crianças'));
      expect(opened, 2);
    });

    testWidgets('a leading mark sits before the title, inside the target', (
      tester,
    ) async {
      var opened = 0;
      await pumpIn(
        tester,
        DoorRow(
          title: 'Lia',
          leading: const SizedBox.square(key: Key('mark'), dimension: 56),
          onTap: () => opened++,
        ),
      );
      final mark = tester.getRect(find.byKey(const Key('mark')));
      expect(mark.right, lessThan(tester.getTopLeft(find.text('Lia')).dx));

      await tester.tapAt(mark.center);
      expect(opened, 1);
    });

    testWidgets('is one labelled button with a 48 dp target', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpIn(
        tester,
        DoorRow(
          title: 'Crianças',
          semanticsLabel: 'Crianças, 2 de 10 crianças',
          onTap: () {},
          child: const Text('2 de 10 crianças'),
        ),
      );
      expect(
        tester.getSemantics(find.byType(DoorRow)),
        matchesSemantics(
          label: 'Crianças, 2 de 10 crianças',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      expect(find.bySemanticsLabel('2 de 10 crianças'), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('while busy, shows progress instead of the chevron and '
        'waits, keeping its label', (tester) async {
      final semantics = tester.ensureSemantics();
      var opened = 0;
      await pumpIn(
        tester,
        DoorRow(title: 'bia@example.com', busy: true, onTap: () => opened++),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(
        tester.getSemantics(find.byType(DoorRow)),
        matchesSemantics(
          label: 'bia@example.com',
          isButton: true,
          hasEnabledState: true,
        ),
      );

      await tester.tap(find.byType(DoorRow));
      expect(opened, 0);
      semantics.dispose();
    });

    testWidgets('the label defaults to the title', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpIn(tester, DoorRow(title: 'Convites', onTap: () {}));
      expect(find.bySemanticsLabel('Convites'), findsOneWidget);
      semantics.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('keyboard focus draws the 3 px outside ring '
          '(${brightness.name})', (tester) async {
        await pumpIn(
          tester,
          DoorRow(title: 'Crianças', onTap: () {}),
          brightness: brightness,
        );
        Iterable<BorderSide> rings() => tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(DoorRow),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((b) => b.decoration)
            .whereType<ShapeDecoration>()
            .map((d) => (d.shape as RoundedRectangleBorder).side)
            .where((s) => s.width == 3);
        expect(rings(), isEmpty);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final p = brightness == Brightness.light ? Palette.light : Palette.dark;
        final ring = rings().single;
        expect(ring.strokeAlign, BorderSide.strokeAlignOutside);
        expect(ring.color, brightness == Brightness.light ? p.text : p.muted);
      });
    }

    testWidgets('holds 200% text on a phone', (tester) async {
      await pumpIn(
        tester,
        DoorRow(
          title: 'Responsáveis',
          onTap: () {},
          child: const CapacityRow(filled: 3, total: 6, words: '3 de 6 vagas'),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Doors divides its rows with reed hairlines at 50%', (
    tester,
  ) async {
    await pumpIn(
      tester,
      Doors(
        children: [
          DoorRow(title: 'Crianças', onTap: () {}),
          DoorRow(title: 'Responsáveis', onTap: () {}),
          DoorRow(title: 'Convites', onTap: () {}),
        ],
      ),
    );
    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, hasLength(4));
    for (final d in dividers) {
      expect(d.color, Palette.light.outline.withValues(alpha: .5));
      expect(d.height, 1);
    }
    expect(find.byType(Card), findsNothing);
  });

  group('QuietAction', () {
    testWidgets('a text action at the start, clay when destructive', (
      tester,
    ) async {
      var pressed = 0;
      await pumpIn(
        tester,
        QuietAction(
          label: 'Sair da família',
          destructive: true,
          onPressed: () => pressed++,
        ),
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      final context = tester.element(find.byType(TextButton));
      expect(button.style?.foregroundColor?.resolve({}), context.palette.error);
      // The label starts on the column edge; the target stays 48 dp.
      expect(tester.getTopLeft(find.text('Sair da família')).dx, Space.xl);
      expect(tester.getSize(find.byType(TextButton)).height, 48);

      await tester.tap(find.text('Sair da família'));
      expect(pressed, 1);
    });

    testWidgets('while busy, shows progress beside its label and waits', (
      tester,
    ) async {
      var pressed = 0;
      await pumpIn(
        tester,
        QuietAction(
          label: 'Cancelar convite',
          busy: true,
          onPressed: () => pressed++,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(CircularProgressIndicator)).dx,
        Space.xl,
      );
      expect(find.text('Cancelar convite'), findsOneWidget);

      await tester.tap(find.text('Cancelar convite'));
      expect(pressed, 0);
    });
  });

  group('FigureRow', () {
    testWidgets('the label on the left, the figure on the right in tabular '
        'figures, one read line', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpIn(tester, const FigureRow(label: 'Contas', figure: '1.240'));

      final label = tester.getRect(find.text('Contas'));
      final figure = tester.getRect(find.text('1.240'));
      expect(label.left, Space.xl);
      expect(figure.right, 360 - Space.xl);
      expect(figure.center.dy, closeTo(label.center.dy, 1));
      final style = tester.widget<Text>(find.text('1.240')).style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(
        tester.getSemantics(find.byType(FigureRow)),
        matchesSemantics(label: 'Contas, 1.240'),
      );
      expect(tester.getSize(find.byType(FigureRow)).height, greaterThan(47));
      semantics.dispose();
    });

    testWidgets('at 200% text where the two cannot share the line, the '
        'figure goes under its label', (tester) async {
      await pumpIn(
        tester,
        const FigureRow(
          label: 'Denúncias nos últimos 7 dias',
          figure: 'menos de 5',
        ),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      final label = tester.getRect(find.text('Denúncias nos últimos 7 dias'));
      final figure = tester.getRect(find.text('menos de 5'));
      expect(figure.top, greaterThanOrEqualTo(label.bottom));
      expect(figure.left, Space.xl);
    });
  });
}
