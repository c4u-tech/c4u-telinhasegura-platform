import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';

const _phone = Size(360, 640);

RRect? clipOf(WidgetTester tester) {
  final clips = find.descendant(
    of: find.byType(BandTransition),
    matching: find.byType(ClipPath),
  );
  if (clips.evaluate().isEmpty) return null;
  return (tester.widget<ClipPath>(clips.first).clipper! as BandClipper).rrect;
}

RRect? overlayOf(WidgetTester tester) {
  final paints = tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(BandTransition),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((p) => p.painter)
      .whereType<InkFieldPainter>();
  return paints.isEmpty ? null : paints.single.rrect;
}

Future<AnimationController> pumpTransition(
  WidgetTester tester,
  BandMotion motion, {
  bool still = false,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = AnimationController(
    vsync: const TestVSync(),
    duration: BandTransition.duration,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(size: _phone)
            .copyWith(disableAnimations: still),
        child: BandTransition(
          animation: controller,
          motion: motion,
          child: const ColoredBox(
            key: Key('page'),
            color: BrandColors.ink,
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  test('the band is where the guardian layout draws its ink field', () {
    expect(
      guardianBand(_phone, const EdgeInsets.only(top: 24)),
      RRect.fromLTRBR(
        12,
        24 + 8 + 22 * FieldSizes.bandUnit,
        348,
        24 + 8 + 22 * FieldSizes.bandUnit + 72,
        const Radius.circular(10 * FieldSizes.bandUnit),
      ),
    );
    expect(
      guardianBand(const Size(1280, 800), EdgeInsets.zero),
      RRect.fromLTRBR(
        16,
        16 + 22 * 4,
        1280 * 0.46 - 16,
        800 - 16,
        const Radius.circular(40),
      ),
    );
  });

  testWidgets('grow: the band widens into the whole screen', (tester) async {
    final controller = await pumpTransition(tester, BandMotion.grow);
    expect(clipOf(tester), guardianBand(_phone, EdgeInsets.zero));

    controller.value = 0.5;
    await tester.pump();
    final mid = clipOf(tester)!;
    final band = guardianBand(_phone, EdgeInsets.zero);
    expect(mid.height, greaterThan(band.height));
    expect(mid.height, lessThan(_phone.height));

    controller.value = 1;
    await tester.pump();
    expect(clipOf(tester), isNull, reason: 'full-bleed ink at rest');
    expect(tester.getRect(find.byKey(const Key('page'))), Offset.zero & _phone);
  });

  testWidgets('shrink: the ink screen closes back onto the band, then '
      'leaves the page as it is', (tester) async {
    final controller = await pumpTransition(tester, BandMotion.shrink);
    expect(
      overlayOf(tester),
      RRect.fromRectAndRadius(Offset.zero & _phone, Radius.zero),
    );

    controller.value = 0.5;
    await tester.pump();
    final mid = overlayOf(tester)!;
    expect(mid.height, lessThan(_phone.height));
    expect(mid.height, greaterThan(72));

    controller.value = 1;
    await tester.pump();
    expect(overlayOf(tester), isNull);
  });

  for (final motion in BandMotion.values) {
    testWidgets('${motion.name} under reduced motion is a cut', (tester) async {
      final controller = await pumpTransition(tester, motion, still: true);
      controller.value = 0.3;
      await tester.pump();
      expect(clipOf(tester), isNull);
      expect(overlayOf(tester), isNull);
    });
  }

  group('as a go_router page', () {
    Future<GoRouter> pumpRouter(
      WidgetTester tester, {
      bool still = false,
    }) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox.expand()),
          GoRoute(
            path: '/crianca',
            pageBuilder: (_, state) => bandGrowPage<void>(
              key: state.pageKey,
              child: const ColoredBox(
                key: Key('page'),
                color: BrandColors.ink,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: child!,
          ),
        ),
      );
      return router;
    }

    testWidgets('grows over about 400 ms and ends full-bleed', (tester) async {
      final router = await pumpRouter(tester);
      router.go('/crianca');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(clipOf(tester)!.height, lessThan(_phone.height));

      await tester.pump(const Duration(milliseconds: 250));
      expect(clipOf(tester), isNull);
      expect(
        tester.getRect(find.byKey(const Key('page'))),
        Offset.zero & _phone,
      );
    });

    testWidgets('cuts under reduced motion', (tester) async {
      final router = await pumpRouter(tester, still: true);
      router.go('/crianca');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(clipOf(tester), isNull);
      expect(
        tester.getRect(find.byKey(const Key('page'))),
        Offset.zero & _phone,
      );
    });
  });
}
