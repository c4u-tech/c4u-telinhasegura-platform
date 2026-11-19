import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/mosaic.dart';

import '../design/pump.dart';
import '../design/tevi_motion_test.dart' show drawn;

Future<void> pumpLoading(WidgetTester tester, {bool still = false}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: themeOf(Ground.kid),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: const Scaffold(body: MosaicLoading()),
          ),
        ),
      ),
    );

/// The gaze drawn at each tenth of a sweep, over one sweep.
Future<List<double>> oneSweep(WidgetTester tester) async => [
  for (var i = 0; i < 10; i++) ...[
    await tester.pump(Motion.gaze ~/ 10).then((_) => drawn(tester).gaze),
  ],
];

void main() {
  testWidgets('while the home loads, the mascot\'s gaze sweeps back and '
      'ahead once every 1.8 s', (tester) async {
    runLoops();
    await pumpLoading(tester);
    final first = await oneSweep(tester);
    expect(first.reduce((a, b) => a > b ? a : b), greaterThan(.9));
    expect(first.last, lessThan(.1), reason: 'back ahead by the period');
    final second = await oneSweep(tester);
    for (var i = 0; i < 10; i++) {
      expect(second[i], closeTo(first[i], 1e-6), reason: 'it repeats');
    }
  });

  testWidgets('the sweep stops once the loading screen leaves', (tester) async {
    runLoops();
    await pumpLoading(tester);
    await tester.pump(Motion.gaze ~/ 3);
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('under reduced motion the mascot looks ahead, still', (
    tester,
  ) async {
    runLoops();
    await pumpLoading(tester, still: true);
    expect(await oneSweep(tester), everyElement(0));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
