import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';

import '../design/pump.dart';

void main() {
  testWidgets('a label wrapped onto two lines at 200 % text stays centred', (
    tester,
  ) async {
    await pumpOn(
      tester,
      SizedBox(
        width: 280,
        child: PrimaryButton(
          label: 'Entregar para Maria Eduarda',
          onPressed: () {},
        ),
      ),
      textScale: 2,
    );

    final text = find.text('Entregar para Maria Eduarda');
    expect(tester.widget<Text>(text).textAlign, TextAlign.center);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    // The paragraph laid out again as it is drawn: its text, alignment,
    // scale and width.
    final painter = TextPainter(
      text: paragraph.text,
      textAlign: paragraph.textAlign,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
    )..layout(minWidth: paragraph.size.width, maxWidth: paragraph.size.width);
    addTearDown(painter.dispose);
    final lines = painter.computeLineMetrics();
    expect(lines.length, greaterThan(1));
    for (final line in lines) {
      final slack = paragraph.size.width - line.width;
      expect(
        line.left,
        closeTo(slack / 2, 1),
        reason: 'line ${line.lineNumber}',
      );
    }
  });
}
