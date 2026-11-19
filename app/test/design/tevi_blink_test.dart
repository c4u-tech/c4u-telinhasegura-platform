import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';

import 'tevi_motion_test.dart' show drawn;

/// A child's mascot whose look [look] holds, on a screen that may ask for
/// reduced motion.
Future<void> pumpFacing(
  WidgetTester tester,
  ValueNotifier<TeviLook> look, {
  bool still = false,
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ValueListenableBuilder(
          valueListenable: look,
          builder: (_, look, _) => FacingTevi(size: 66, look: look),
        ),
      ),
    ),
  ),
);

/// The eyelid drawn at each of [frames] frames [step] apart.
Future<List<double>> lids(
  WidgetTester tester, {
  int frames = 12,
  Duration step = const Duration(milliseconds: 20),
}) async => [
  for (var i = 0; i < frames; i++) ...[
    await tester.pump(step).then((_) => drawn(tester).lid),
  ],
];

void main() {
  group('a child\'s mascot arriving on screen', () {
    testWidgets('blinks once, over the blink\'s length, then keeps still', (
      tester,
    ) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpFacing(tester, look);

      await tester.pump(Motion.blink ~/ 2);
      expect(drawn(tester).lid, greaterThan(.9), reason: 'the eye shut');

      await tester.pump(Motion.blink ~/ 2);
      expect(drawn(tester), TeviLook.watching, reason: 'and open again');
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no loop');
    });

    testWidgets('never blinks again while it stays', (tester) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpFacing(tester, look);
      await tester.pumpAndSettle();

      // A change of look and back is not an arrival.
      look.value = TeviLook.crestUp;
      await tester.pumpAndSettle();
      look.value = TeviLook.watching;
      await tester.pump();
      expect(await lids(tester), everyElement(0));
    });

    testWidgets('does not blink asleep', (tester) async {
      final look = ValueNotifier(TeviLook.asleep);
      addTearDown(look.dispose);
      await pumpFacing(tester, look);
      expect(tester.binding.transientCallbackCount, 0);
      expect(await lids(tester), everyElement(1));
    });

    testWidgets('does not blink under reduced motion', (tester) async {
      final look = ValueNotifier(TeviLook.watching);
      addTearDown(look.dispose);
      await pumpFacing(tester, look, still: true);
      expect(tester.binding.transientCallbackCount, 0);
      expect(await lids(tester), everyElement(0));
    });

    testWidgets('waits for its page to finish arriving', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: Motion.room,
          pageBuilder: (_, _, _) => const Center(child: FacingTevi(size: 66)),
        ),
      );
      await tester.pump();
      final during = await lids(
        tester,
        frames: 14,
        step: const Duration(milliseconds: 20),
      );
      expect(during, everyElement(0), reason: 'still while the page grows');

      // The page's last frame finds it arrived; the blink starts there.
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(Motion.blink ~/ 2);
      expect(drawn(tester).lid, greaterThan(.5), reason: 'blinks on arrival');
      await tester.pumpAndSettle();
      expect(drawn(tester), TeviLook.watching);
    });
  });

  testWidgets('the guardian\'s mascot does not blink', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Tevi(size: 66)),
      ),
    );
    expect(tester.binding.transientCallbackCount, 0);
  });
}
