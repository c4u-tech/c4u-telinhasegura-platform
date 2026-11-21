import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/approve_screen.dart';
import 'package:telinha_segura/curation/end_line.dart' show EndLine;
import 'package:telinha_segura/design/pinned_header.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/kid_player.dart';

import '../store_screens/store_screens_test.dart' show loadFonts;
import 'approve_screen_test.dart';
import 'fixtures.dart';

/// What the flow's pinned header keeps at the top.
PinnedPart pinned(WidgetTester tester) =>
    tester.renderObject<RenderPinnedHeader>(find.byType(PinnedHeader)).pinned;

void main() {
  // The app's own typeface: how many lines a sentence takes, and so the
  // height the line keeps, depends on its glyphs.
  setUpAll(loadFonts);

  testWidgets('at 360 × 640 and 200 % text the window and its line, kept at '
      'the height of its longer sentence, still leave half the height, and '
      'stay', (tester) async {
    await approving(
      tester,
      draft: () => kept(draftJson()),
      size: const Size(360, 640),
      textScale: 2,
    );

    expect(pinned(tester), PinnedPart.child);
    await scrollContent(tester, 300);
    expect(tester.getTopLeft(window()).dy, Space.lg);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the line keeps its height as the video reaches its end, at '
      '200 % text on a small phone', (tester) async {
    final h = await approving(
      tester,
      draft: () => kept(draftJson()),
      size: const Size(360, 640),
      textScale: 2,
    );
    final before = tester.getSize(find.byType(EndLine)).height;
    final question = tester.getTopLeft(find.text(tie)).dy;

    h.adultPlayer.opened.last.emit(const PlayerEnded());
    await tester.pumpAndSettle();

    expect(find.text(playedToEnd), findsOneWidget);
    expect(tester.getSize(find.byType(EndLine)).height, before);
    expect(tester.getTopLeft(find.text(tie)).dy, question);
  });

  testWidgets('the check grows with the words, on the line and on the '
      'chosen answer', (tester) async {
    await approving(tester, size: const Size(360, 640), textScale: 2);
    await answer(tester, tie, 'Não');

    final checks = find.byIcon(Icons.check_rounded);
    expect(checks, findsNWidgets(2));
    for (final check in checks.evaluate()) {
      expect((check.renderObject! as RenderBox).size, const Size.square(40));
    }
  });
}
