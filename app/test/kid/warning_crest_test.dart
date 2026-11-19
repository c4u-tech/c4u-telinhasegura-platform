import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';

import '../design/pump.dart';

/// The look the note's mascot is drawn with now.
TeviLook drawn(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(Tevi),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TeviPainter)
        .look;

void main() {
  for (final beside in [false, true]) {
    final where = beside ? 'beside its line' : 'above its line';
    testWidgets('a warning raises the crest over the scale\'s change, '
        '$where', (tester) async {
      await pumpOn(
        tester,
        KidErrorNote('Não deu certo.', beside: beside),
        ground: Ground.kid,
      );
      expect(drawn(tester).crest, 0, reason: 'it starts flat');

      await tester.pump(const Duration(milliseconds: 110));
      expect(drawn(tester).crest, inExclusiveRange(0, 1));

      await tester.pump(const Duration(milliseconds: 120));
      expect(drawn(tester), TeviLook.crestUp);
      await tester.pumpAndSettle();
      expect(drawn(tester), TeviLook.crestUp, reason: 'once, then still');
    });
  }

  testWidgets('under reduced motion the crest is up at once', (tester) async {
    await pumpOn(
      tester,
      const KidErrorNote('Não deu certo.'),
      ground: Ground.kid,
      disableAnimations: true,
    );
    expect(drawn(tester), TeviLook.crestUp);
  });

  testWidgets('a note that is not a warning does not raise it', (tester) async {
    await pumpOn(
      tester,
      const KidErrorNote('Agora não.', asleep: true),
      ground: Ground.kid,
    );
    expect(drawn(tester), TeviLook.asleep);
  });
}
