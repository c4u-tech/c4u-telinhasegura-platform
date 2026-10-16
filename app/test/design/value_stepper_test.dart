import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/design/value_stepper.dart';
import 'package:telinha_segura/screentime/words.dart';

import 'pump.dart';

/// A stepper over 15–240 in 15s, its value held here.
class Holder extends StatefulWidget {
  const Holder({super.key, required this.start, this.enabled = true});

  final int start;
  final bool enabled;

  @override
  State<Holder> createState() => _HolderState();
}

class _HolderState extends State<Holder> {
  late int value = widget.start;

  @override
  Widget build(BuildContext context) => ValueStepper(
    label: 'Por dia',
    value: value,
    min: 15,
    max: 240,
    step: 15,
    words: ScreenTimeWords.minutes,
    onChanged: widget.enabled ? (v) => setState(() => value = v) : null,
  );
}

Finder key(String label) => find.bySemanticsLabel(label);

void expectEnabled(WidgetTester tester, String label, bool enabled) => expect(
  tester.getSemantics(key(label)),
  isSemantics(isEnabled: enabled),
  reason: label,
);

void main() {
  testWidgets('the value in words between − and +, moving by the step', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpOn(tester, const Holder(start: 90));

    expect(find.text('Por dia'), findsOneWidget);
    expect(find.text('1 h 30 min'), findsOneWidget);
    await tester.tap(key('Mais 15 min'));
    await tester.pump();
    expect(find.text('1 h 45 min'), findsOneWidget);
    await tester.tap(key('Menos 15 min'));
    await tester.pump();
    await tester.tap(key('Menos 15 min'));
    await tester.pump();
    expect(find.text('1 h 15 min'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('− waits at the least and + at the most', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOn(tester, const Holder(start: 30));

    expectEnabled(tester, 'Menos 15 min', true);
    await tester.tap(key('Menos 15 min'));
    await tester.pump();
    expect(find.text('15 min'), findsOneWidget);
    expectEnabled(tester, 'Menos 15 min', false);
    expectEnabled(tester, 'Mais 15 min', true);

    await pumpOn(tester, const Holder(start: 240, key: Key('max')));
    expect(find.text('4 h'), findsOneWidget);
    expectEnabled(tester, 'Mais 15 min', false);
    expectEnabled(tester, 'Menos 15 min', true);
    semantics.dispose();
  });

  testWidgets('without onChanged, both keys wait', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOn(tester, const Holder(start: 90, enabled: false));

    expectEnabled(tester, 'Mais 15 min', false);
    expectEnabled(tester, 'Menos 15 min', false);
    semantics.dispose();
  });

  testWidgets('the value is read as adjustable, with its increase and '
      'decrease', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOn(tester, const Holder(start: 90));

    final value = find.bySemanticsLabel('Por dia');
    expect(
      tester.getSemantics(value),
      isSemantics(
        label: 'Por dia',
        value: '1 h 30 min',
        increasedValue: '1 h 45 min',
        decreasedValue: '1 h 15 min',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    tester.semantics.performAction(
      find.semantics.byLabel('Por dia'),
      SemanticsAction.increase,
    );
    await tester.pump();
    expect(find.text('1 h 45 min'), findsOneWidget);

    await pumpOn(tester, const Holder(start: 15, key: Key('min')));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Por dia')),
      isSemantics(hasIncreaseAction: true, hasDecreaseAction: false),
    );
    semantics.dispose();
  });

  testWidgets('outlined 56 dp keys at the control corner, the value in '
      'headline', (tester) async {
    await pumpOn(tester, const Holder(start: 90));

    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      final box = tester.getSize(find.byWidget(button));
      expect(box, const Size.square(56));
      final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(Radii.control));
    }
    expect(find.byType(OutlinedButton), findsNWidgets(2));
    final style = tester.widget<Text>(find.text('1 h 30 min')).style!;
    final headline = Theme.of(tester.element(find.text('1 h 30 min')))
        .textTheme
        .headlineSmall!;
    expect(style.fontSize, headline.fontSize);
  });

  testWidgets('at 200% text, 360 wide, the longest value fits', (tester) async {
    await pumpOn(tester, const Holder(start: 225), textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('3 h 45 min'), findsOneWidget);
  });
}
