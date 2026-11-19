import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../design/pump.dart';

/// How opaque the placeholder's bars are drawn now.
double opacity(WidgetTester tester) {
  final fades = tester.widgetList<FadeTransition>(
    find.descendant(
      of: find.byType(FamilyPlaceholder),
      matching: find.byType(FadeTransition),
    ),
  );
  return fades.isEmpty ? 1 : fades.single.opacity.value;
}

/// The bars' opacity at each tenth of a breath, over one breath.
Future<List<double>> oneBreath(WidgetTester tester) async => [
  for (var i = 0; i < 10; i++) ...[
    await tester.pump(Motion.breath ~/ 10).then((_) => opacity(tester)),
  ],
];

void main() {
  testWidgets('the bars breathe, down to .45 and back once every 1.4 s', (
    tester,
  ) async {
    runLoops();
    await pumpOn(tester, const FamilyPlaceholder());
    final first = await oneBreath(tester);
    expect(first.reduce((a, b) => a < b ? a : b), closeTo(.45, .02));
    expect(first.last, closeTo(1, .02), reason: 'back by the period');
    final second = await oneBreath(tester);
    for (var i = 0; i < 10; i++) {
      expect(second[i], closeTo(first[i], 1e-6), reason: 'it repeats');
    }
  });

  testWidgets('the breath stops once the placeholder leaves', (tester) async {
    runLoops();
    await pumpOn(tester, const FamilyPlaceholder());
    await tester.pump(Motion.breath ~/ 3);
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('under reduced motion the bars stay still', (tester) async {
    runLoops();
    await pumpOn(tester, const FamilyPlaceholder(), disableAnimations: true);
    expect(await oneBreath(tester), everyElement(1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('it is still read by its label alone', (tester) async {
    runLoops();
    final semantics = tester.ensureSemantics();
    await pumpOn(tester, const FamilyPlaceholder(label: 'Carregando'));
    await tester.pump(Motion.breath ~/ 2);
    expect(semanticsStrings(tester), ['Carregando']);
    semantics.dispose();
  });
}
