import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/espiadinha.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/kid_layout.dart';

const _safe = EdgeInsets.only(top: 24, bottom: 16);

Future<void> pumpKid(
  WidgetTester tester,
  Widget layout, {
  Size size = const Size(360, 640),
  double textScale = 1,
  ThemeMode mode = ThemeMode.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: _safe.top, bottom: _safe.bottom);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: layout,
    ),
  );
}

Finder get mark => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is SimplifiedMarkPainter,
);

bool darkOval(Symbol method, List<dynamic> args) =>
    method == #drawOval &&
    (args[1] as Paint).color.toARGB32() == BrandColors.dark.toARGB32();

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('ink is the ground edge to edge in the ${mode.name} theme', (
      tester,
    ) async {
      await pumpKid(tester, const KidLayout(child: SizedBox()), mode: mode);
      final ground = find
          .descendant(
            of: find.byType(KidLayout),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.widget<Material>(ground).color, BrandColors.ink);
      expect(tester.getRect(ground), Offset.zero & const Size(360, 640));
    });
  }

  testWidgets('every shared widget inside paints in the kid dialect', (
    tester,
  ) async {
    late Palette palette;
    await pumpKid(
      tester,
      KidLayout(
        child: Builder(
          builder: (context) {
            palette = context.palette;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(palette, Palette.kid);
  });

  testWidgets('the simplified mark only, small, at the top edge; no '
      'wordmark', (tester) async {
    await pumpKid(tester, const KidLayout(child: SizedBox()));
    final rect = tester.getRect(mark);
    expect(rect.height, inInclusiveRange(20, 47));
    expect(rect.top, greaterThanOrEqualTo(_safe.top));
    expect(rect.top, lessThan(_safe.top + KidSizes.target));
    // At the strip's start, quiet (fullscreen design).
    expect(rect.left, _safe.left + Space.xl);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('sun only in the head, alone on ink with dark eyes', (
    tester,
  ) async {
    await pumpKid(tester, const KidLayout(child: SizedBox()));
    expect(
      mark,
      paints
        ..rrect(color: BrandColors.cream)
        ..path(color: BrandColors.sun, style: PaintingStyle.fill)
        ..something(darkOval)
        ..something(darkOval),
    );
    // No outline on ink: nothing is stroked.
    expect(
      mark,
      isNot(
        paints..something(
          (_, args) => args.whereType<Paint>().any(
            (p) => p.style == PaintingStyle.stroke,
          ),
        ),
      ),
    );
  });

  testWidgets('the exit slot sits in the top corner, 16 dp in from the '
      'safe area, level with the mark (fix round, item 4)', (tester) async {
    await pumpKid(
      tester,
      const KidLayout(
        exit: SizedBox.square(key: Key('exit'), dimension: 64),
        child: SizedBox(),
      ),
    );
    final exit = tester.getRect(find.byKey(const Key('exit')));
    expect(exit.top, _safe.top + Space.lg);
    expect(exit.right, 360 - Space.lg);
    expect(exit.center.dy, tester.getCenter(mark).dy);
    expect(exit.overlaps(tester.getRect(mark)), isFalse);
  });

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('the content column is centred and holds at 200% text at '
        '$size', (tester) async {
      await pumpKid(
        tester,
        KidLayout(
          child: Column(
            key: const Key('content'),
            children: [
              for (var i = 0; i < 12; i++)
                const Text('Logo tem vídeo aqui', textAlign: TextAlign.center),
            ],
          ),
        ),
        size: size,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final content = tester.getRect(find.byKey(const Key('content')));
      expect(content.center.dx, closeTo(size.width / 2, 0.5));
      expect(content.width, lessThanOrEqualTo(FieldSizes.columnMaxWidth));
      expect(content.top, greaterThanOrEqualTo(_safe.top + KidSizes.target));
    });
  }
}
