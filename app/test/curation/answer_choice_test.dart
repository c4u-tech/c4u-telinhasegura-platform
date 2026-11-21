import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/answer_choice.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/family/profile_fields.dart' show ChoiceTarget;

import '../family/widgets_test.dart' show pumpIn;
import '../store_screens/store_screens_test.dart' show loadFonts;

const question = 'Alguém bate de propósito?';
const words = ['Não', 'Sim', 'Não sei'];

Finder keyOf(String word) => find.widgetWithText(ChoiceTarget, word);

/// How many lines [word]'s label takes inside its key.
int linesOf(WidgetTester tester, String word) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: keyOf(word), matching: find.text(word)),
    )
    .getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: word.length),
    )
    .length;

void main() {
  // The app's own typeface: whether a word breaks depends on its glyphs.
  setUpAll(loadFonts);

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

  testWidgets('in a narrow window at large text, the three keys stand level '
      'at one height of 56 dp or more', (tester) async {
    await pumpIn(
      tester,
      AnswerChoice(
        question: question,
        value: ChecklistAnswer.doubt,
        onChanged: (_) {},
      ),
      size: const Size(320, 640),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final heights = {for (final w in words) tester.getSize(keyOf(w)).height};
    expect(heights, hasLength(1), reason: 'equal heights');
    expect(heights.single, greaterThanOrEqualTo(56));
    final tops = {for (final w in words) tester.getTopLeft(keyOf(w)).dy};
    expect(tops, hasLength(1), reason: 'one row');
  });

  testWidgets('at 200 % text on a 360-wide phone, a chosen one-word key '
      'keeps its word on one line, its check moving above it', (tester) async {
    await pumpIn(
      tester,
      AnswerChoice(
        question: question,
        value: ChecklistAnswer.ok,
        onChanged: (_) {},
      ),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(linesOf(tester, 'Não'), 1);
    final check = find.descendant(
      of: keyOf('Não'),
      matching: find.byIcon(Icons.check_rounded),
    );
    expect(check, findsOneWidget, reason: 'never colour alone');
    final word = find.descendant(of: keyOf('Não'), matching: find.text('Não'));
    expect(
      tester.getBottomLeft(check).dy,
      lessThanOrEqualTo(tester.getTopLeft(word).dy),
    );
  });

  testWidgets('where the word fits beside it, the check stays before it', (
    tester,
  ) async {
    await pumpIn(
      tester,
      AnswerChoice(
        question: question,
        value: ChecklistAnswer.ok,
        onChanged: (_) {},
      ),
    );

    final check = find.descendant(
      of: keyOf('Não'),
      matching: find.byIcon(Icons.check_rounded),
    );
    final word = find.descendant(of: keyOf('Não'), matching: find.text('Não'));
    expect(tester.getCenter(check).dy, closeTo(tester.getCenter(word).dy, 1));
    expect(tester.getTopRight(check).dx, lessThan(tester.getTopLeft(word).dx));
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

  testWidgets('without onChanged the keys look disabled, a chosen one '
      'still carrying its check', (tester) async {
    await pumpIn(
      tester,
      const AnswerChoice(
        question: question,
        value: ChecklistAnswer.appears,
        onChanged: null,
      ),
    );

    final p = tester.element(find.byType(AnswerChoice)).palette;
    for (final w in words) {
      final box =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: keyOf(w),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(box.color, p.outline.withValues(alpha: .32), reason: w);
      expect(
        tester.widget<Text>(find.text(w)).style?.color,
        p.text.withValues(alpha: .6),
        reason: w,
      );
    }
    expect(
      find.descendant(
        of: keyOf('Sim'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
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
