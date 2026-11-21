import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/approve_screen.dart';

import '../store_screens/store_screens_test.dart' show loadFonts;
import 'approve_screen_test.dart';
import 'doubt_screens_test.dart' show doubtHeld;
import 'fixtures.dart';

void main() {
  // The app's own typeface: where a line breaks depends on its glyphs.
  setUpAll(loadFonts);

  testWidgets('at 200 % text on a small phone a doubt\'s line on "Publicar" '
      'wraps only between words', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      size: const Size(360, 640),
      textScale: 2,
    );

    expectBreaksOnlyAtSpaces(
      tester,
      find.text(nb('Mãe ou pai teve dúvida · Bichos · 5 a 8 anos')),
    );
  });

  testWidgets('at 200 % text on a small phone the summary\'s theme and band '
      'wrap only between words', (tester) async {
    await approving(tester, size: const Size(360, 640), textScale: 2);
    await toTopic(tester);
    await choose(tester, 'Histórias');
    await forOlder(tester);
    await choose(tester, '9 a 12 anos');
    await tester.enterText(reasonField(), 'Fala de namoro.');
    await tester.pumpAndSettle();
    await tapPrimary(tester);
    expect(find.text(reviewTitle), findsOneWidget);

    expectBreaksOnlyAtSpaces(tester, find.text(nb('Histórias · 9 a 12 anos')));
  });
}
