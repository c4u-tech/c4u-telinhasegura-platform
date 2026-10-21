import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/answer_choice.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/family/profile_fields.dart' show ChoiceTarget;

import '../family/widgets_test.dart' show pumpIn;

const question = 'Alguém bate de propósito?';
const words = ['Não', 'Sim', 'Não sei'];

Finder keyOf(String word) => find.widgetWithText(ChoiceTarget, word);

void main() {
  testWidgets('offers Não, Sim and Não sei side by side under the question, '
      'none chosen, each a 56 dp key', (tester) async {
    await pumpIn(
      tester,
      AnswerChoice(question: question, value: null, onChanged: (_) {}),
    );

    expect(find.text(question), findsOneWidget);
    final tops = [for (final w in words) tester.getTopLeft(keyOf(w)).dy];
    expect(tops.toSet(), hasLength(1), reason: 'one row');
    final lefts = [for (final w in words) tester.getTopLeft(keyOf(w)).dx];
    expect(lefts, [...lefts]..sort());
    expect(tester.getTopLeft(find.text(question)).dy, lessThan(tops.first));
    for (final w in words) {
      expect(tester.getSize(keyOf(w)).height, greaterThanOrEqualTo(56));
      expect(tester.widget<ChoiceTarget>(keyOf(w)).selected, isFalse);
    }
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('a tap answers; the chosen key carries a check, so the choice '
      'never rests on colour alone', (tester) async {
    ChecklistAnswer? value;
    await pumpIn(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AnswerChoice(
          question: question,
          value: value,
          onChanged: (a) => setState(() => value = a),
        ),
      ),
    );

    await tester.tap(keyOf('Sim'));
    await tester.pumpAndSettle();
    expect(value, ChecklistAnswer.appears);
    expect(
      find.descendant(
        of: keyOf('Sim'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(keyOf('Não sei'));
    await tester.pumpAndSettle();
    expect(value, ChecklistAnswer.doubt);
    await tester.tap(keyOf('Não'));
    await tester.pumpAndSettle();
    expect(value, ChecklistAnswer.ok);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('without "Não sei", only Não and Sim', (tester) async {
    await pumpIn(
      tester,
      AnswerChoice(
        question: question,
        value: null,
        unsure: false,
        onChanged: (_) {},
      ),
    );

    expect(keyOf('Não'), findsOneWidget);
    expect(keyOf('Sim'), findsOneWidget);
    expect(keyOf('Não sei'), findsNothing);
  });

  testWidgets('reads as a group named by its question, each answer a radio '
      'of it', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpIn(
      tester,
      AnswerChoice(
        question: question,
        value: ChecklistAnswer.ok,
        onChanged: (_) {},
      ),
    );

    expect(
      tester
          .getSemantics(find.bySemanticsLabel(question))
          .getSemanticsData()
          .role,
      SemanticsRole.radioGroup,
    );
    expect(
      tester.getSemantics(keyOf('Não')),
      isSemantics(
        label: 'Não',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(tester.getSemantics(keyOf('Sim')), isSemantics(isChecked: false));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('without onChanged the keys are disabled', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpIn(
      tester,
      const AnswerChoice(question: question, value: null, onChanged: null),
    );

    expect(
      tester.getSemantics(keyOf('Sim')),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
    semantics.dispose();
  });
}
