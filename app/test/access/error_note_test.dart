import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/tokens.dart';

import '../design/pump.dart';

void main() {
  for (final (ground, palette) in [
    (Ground.light, Palette.light),
    (Ground.dark, Palette.dark),
  ]) {
    testWidgets('on the ${ground.name} ground the note is a panel with the '
        'corner of the fields and buttons around it, in the error\'s '
        'colours', (tester) async {
      await pumpOn(tester, const ErrorNote('Algo deu errado.'), ground: ground);

      final panel =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(ErrorNote),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(panel.borderRadius, BorderRadius.circular(Radii.control));
      expect(panel.color, palette.errorGround);
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.error_outline_rounded),
      );
      expect(icon.color, palette.error);
      expect(
        tester.widget<Text>(find.text('Algo deu errado.')).style?.color,
        palette.error,
      );
    });
  }
}
