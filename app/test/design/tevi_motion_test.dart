import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';

/// The look the mascot is drawn with now.
TeviLook drawn(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(Tevi),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TeviPainter)
        .look;

/// A mascot whose look [look] holds, on a screen that may ask for
/// reduced motion.
Future<void> pumpMascot(
  WidgetTester tester,
  ValueNotifier<TeviLook> look, {
  bool still = false,
  bool eases = true,
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ValueListenableBuilder(
          valueListenable: look,
          builder: (_, look, _) => Tevi(size: 66, look: look, eases: eases),
        ),
      ),
    ),
  ),
);

void main() {
  group('a change of look on a mounted mascot', () {
    testWidgets('eases into the new look over the scale\'s change, once', (
      tester,
    ) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpMascot(tester, look);
      expect(drawn(tester), TeviLook.watching);

      look.value = TeviLook.crestUp;
      await tester.pump();
      expect(
        drawn(tester),
        TeviLook.watching,
        reason: 'it starts where it was',
      );

      await tester.pump(Motion.change ~/ 2);
      final crest = drawn(tester).crest;
      expect(crest, greaterThan(0));
      expect(crest, lessThan(1));

      await tester.pump(Motion.change ~/ 2);
      expect(drawn(tester), TeviLook.crestUp);
      // The frame after the last one finds the change over: no loop.
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no loop');
    });

    testWidgets('falls asleep slowly, over 600 ms', (tester) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpMascot(tester, look);

      look.value = TeviLook.asleep;
      await tester.pump();
      await tester.pump(Motion.change);
      expect(drawn(tester).lid, lessThan(1), reason: 'still closing');

      await tester.pump(Motion.fallAsleep - Motion.change);
      expect(drawn(tester), TeviLook.asleep);
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a change during a change starts from the look drawn then', (
      tester,
    ) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpMascot(tester, look);

      look.value = TeviLook.crestUp;
      await tester.pump();
      await tester.pump(Motion.change ~/ 2);
      final midway = drawn(tester).crest;

      look.value = TeviLook.watching;
      await tester.pump();
      expect(drawn(tester).crest, closeTo(midway, 1e-9), reason: 'no jump');
      await tester.pump(Motion.change);
      expect(drawn(tester), TeviLook.watching);
    });

    testWidgets('is a cut under reduced motion', (tester) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpMascot(tester, look, still: true);

      look.value = TeviLook.asleep;
      await tester.pump();
      expect(drawn(tester), TeviLook.asleep);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('is drawn as given when its caller drives the look', (
      tester,
    ) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpMascot(tester, look, eases: false);

      look.value = TeviLook.winking;
      await tester.pump();
      expect(drawn(tester), TeviLook.winking);
    });
  });

  testWidgets('the confirmation wink keeps its own beat, drawn as it goes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const PerchedTevi(size: 72, wink: true, child: SizedBox()),
      ),
    );
    // The eye is shut a fifth of the way in, with no easing behind it.
    await tester.pump(PerchedTevi.winkDuration ~/ 5);
    expect(drawn(tester).lid, 1);
    await tester.pumpAndSettle();
    expect(drawn(tester), TeviLook.watching);
  });
}
