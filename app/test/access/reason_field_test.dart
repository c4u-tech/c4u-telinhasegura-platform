import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/confirm.dart' show validReason;

import '../family/widgets_test.dart' show pumpIn;

void main() {
  Future<TextEditingController> field(
    WidgetTester tester, {
    double textScale = 1,
    int minLines = 1,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpIn(
      tester,
      ReasonField(
        controller: controller,
        label: 'Motivo',
        maxLength: 200,
        minLines: minLines,
      ),
      textScale: textScale,
    );
    return controller;
  }

  testWidgets('takes no more than its bound counted as the server counts, '
      'one per character code, and the count shows near it', (tester) async {
    final controller = await field(tester);

    // A thumbs-up with a skin tone is one symbol made of two codes.
    await tester.enterText(find.byType(TextField), '👍🏽' * 150);
    await tester.pump();
    expect(controller.text.runes.length, 200);
    expect(find.text('200 de 200'), findsOneWidget);
    expect(validReason(controller.text), isTrue);

    await tester.enterText(find.byType(TextField), 'a' * 150);
    await tester.pump();
    expect(find.textContaining(' de 200'), findsNothing);
    await tester.enterText(find.byType(TextField), '😀' * 170);
    await tester.pump();
    expect(find.text('170 de 200'), findsOneWidget);
    expect(validReason(controller.text), isTrue);
  });

  testWidgets('grows with its words from its fewest lines', (tester) async {
    await field(tester, minLines: 3);

    final f = tester.widget<TextField>(find.byType(TextField));
    expect(f.minLines, 3);
    expect(f.maxLines, isNull);
  });

  testWidgets('at 200 % text its label stands on its own line over the '
      'field, read as the field\'s', (tester) async {
    final semantics = tester.ensureSemantics();
    await field(tester, textScale: 2);

    final label = find.text('Motivo');
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.labelText,
      isNull,
    );
    expect(
      tester.getTopLeft(find.byType(TextField)).dy -
          tester.getBottomLeft(label).dy,
      8,
    );
    expect(
      tester.getSemantics(find.byType(TextField)),
      isSemantics(label: 'Motivo', isTextField: true),
    );
    semantics.dispose();
  });
}
