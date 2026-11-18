import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/tokens.dart';

import '../design/pump.dart';

import '../family/widgets_test.dart' show pumpIn;

void main() {
  testWidgets('names its steps with the word it is given, one module per '
      'step, filled up to the current one', (tester) async {
    await pumpIn(tester, const StepMarks(step: 2, of: 5, word: 'Etapa'));

    expect(find.text('Etapa 2 de 5'), findsOneWidget);
    final modules = tester
        .widgetList<StateModule>(find.byType(StateModule))
        .toList();
    expect(modules, hasLength(5));
    expect(modules.where((m) => m.filled), hasLength(2));
  });

  testWidgets('says "Passo" unless told otherwise', (tester) async {
    await pumpIn(tester, const StepMarks(step: 1, of: 2));

    expect(find.text('Passo 1 de 2'), findsOneWidget);
  });

  for (final (ground, palette) in [
    (Ground.light, Palette.light),
    (Ground.dark, Palette.dark),
    (Ground.kid, Palette.kid),
  ]) {
    testWidgets('on the ${ground.name} ground a filled module takes the '
        'meter\'s colour and a hollow one the outline, never the '
        'action\'s', (tester) async {
      await pumpOn(
        tester,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StateModule(key: Key('on'), filled: true),
            StateModule(key: Key('off'), filled: false),
          ],
        ),
        ground: ground,
      );
      await tester.pumpAndSettle();
      BoxDecoration of(String key) =>
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(Key(key)),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      final on = of('on'), off = of('off');
      expect(on.color, palette.meter);
      expect((on.border! as Border).top.color, palette.meter);
      expect(off.color, Colors.transparent);
      expect((off.border! as Border).top.color, palette.outline);
    });
  }
}
