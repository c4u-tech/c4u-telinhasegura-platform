import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/design/display_title.dart';

import 'pump.dart';

TextScaler scalerOf(WidgetTester tester, String title) =>
    tester.widget<Text>(find.text(title)).textScaler!;

void main() {
  testWidgets('a title whose words fit keeps the 200% scale', (tester) async {
    await pumpOn(tester, const DisplayTitle('Oi'), textScale: 2);

    expect(scalerOf(tester, 'Oi').scale(10), 20);
  });

  testWidgets('a word wider than the column shrinks the title only as far '
      'as that word needs, on one line', (tester) async {
    // The test font sets every glyph about one em wide: 13 glyphs of
    // 36 px at 200% are some 900 px, against 312 px inside the gutters.
    await pumpOn(tester, const DisplayTitle('Consentimento'), textScale: 2);

    final scale = scalerOf(tester, 'Consentimento').scale(1);
    expect(scale, lessThan(2));
    final size = tester.getSize(find.text('Consentimento'));
    expect(size.width, lessThanOrEqualTo(312));
    expect(size.width, greaterThan(312 * 0.95), reason: 'no smaller');
    expect(size.height, lessThan(40 * scale * 1.5), reason: 'one line');
  });

  testWidgets('an address breaks at its safe points instead of shrinking '
      'the title to fit it whole on one line (Plain Address Rule)', (
    tester,
  ) async {
    // Each piece between its break points ("ana@", "bia", ".com", ".br")
    // fits the 312 px column at 200%; the whole address does not.
    final shown = addressBreaks('ana@bia.com.br');
    await pumpOn(tester, DisplayTitle(shown), textScale: 2);

    expect(scalerOf(tester, shown).scale(10), 20, reason: 'kept 200%');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(shown), matching: find.byType(RichText)),
    );
    final lines = linesOf(paragraph);
    expect(lines.length, greaterThan(1));
    expectAddressBreaks(lines);
  });

  testWidgets('a title shown with break marks is read plain', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOn(
      tester,
      DisplayTitle(
        'Remover ${addressBreaks('bia@example.com')}?',
        semanticsLabel: 'Remover bia@example.com?',
      ),
    );

    expect(find.bySemanticsLabel('Remover bia@example.com?'), findsOneWidget);
    semantics.dispose();
  });
}
