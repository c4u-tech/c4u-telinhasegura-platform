import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';

import '../design/pump.dart';

double progress(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(HoldToExit),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((p) => p.painter)
    .whereType<ExitRingPainter>()
    .single
    .progress;

Future<int Function()> pumpExit(
  WidgetTester tester, {
  bool still = false,
}) async {
  var exits = 0;
  await pumpOn(
    tester,
    HoldToExit(onExit: () => exits++),
    ground: Ground.kid,
    disableAnimations: still,
  );
  return () => exits;
}

void main() {
  testWidgets('a continuous 2-second press exits, filling the ring as it '
      'goes', (tester) async {
    final exits = await pumpExit(tester);
    final press = await tester.startGesture(
      tester.getCenter(find.byType(HoldToExit)),
    );
    await tester.pump(); // the press starts the clock
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), closeTo(0.5, 0.05));
    expect(exits(), 0);

    await tester.pump(const Duration(milliseconds: 1001));
    expect(exits(), 1);
    await press.up();
    await tester.pump();
    expect(progress(tester), 0, reason: 'empty again for the next time');
  });

  testWidgets('releasing early empties the ring and exits nothing', (
    tester,
  ) async {
    final exits = await pumpExit(tester);
    final center = tester.getCenter(find.byType(HoldToExit));

    final first = await tester.startGesture(center);
    await tester.pump(); // the press starts the clock
    await tester.pump(const Duration(milliseconds: 1500));
    await first.up();
    await tester.pump();
    expect(progress(tester), 0);

    final second = await tester.startGesture(center);
    await tester.pump(); // the press starts the clock
    await tester.pump(const Duration(milliseconds: 1500));
    expect(exits(), 0, reason: 'a new press starts from empty');
    await second.cancel();
    await tester.pump();
    expect(progress(tester), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(exits(), 0);
  });

  testWidgets('reduced motion still takes the full 2 seconds', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final exits = await pumpExit(tester, still: true);
    final press = await tester.startGesture(
      tester.getCenter(find.byType(HoldToExit)),
    );
    await tester.pump(); // the press starts the clock
    await tester.pump(const Duration(milliseconds: 1000));
    expect(exits(), 0);
    expect(progress(tester), closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 1001));
    expect(exits(), 1);
    await press.up();
  });

  testWidgets('assistive technology gets a long-press action that exits '
      'at once', (tester) async {
    final semantics = tester.ensureSemantics();
    final exits = await pumpExit(tester);
    final node = tester.getSemantics(find.bySemanticsLabel(HoldToExit.label));
    expect(
      node,
      isSemantics(label: 'Sair do modo criança', hasLongPressAction: true),
    );

    tester.semantics.longPress(find.semantics.byLabel(HoldToExit.label));
    await tester.pump();
    expect(exits(), 1);
    semantics.dispose();
  });

  testWidgets('a held key exits too, for a keyboard', (tester) async {
    final exits = await pumpExit(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(seconds: 2));
    expect(exits(), 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2001));
    expect(exits(), 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  });

  testWidgets('a 64 dp labelled target, low-key but 3:1 on ink', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpExit(tester);
    final size = tester.getSize(find.byType(HoldToExit));
    expect(size.width, greaterThanOrEqualTo(KidSizes.target));
    expect(size.height, greaterThanOrEqualTo(KidSizes.target));
    // The glyph is drawn in the kid outline, asserted ≥ 3:1 on ink in
    // tokens_test.dart; no text, no lock.
    final glyph = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(HoldToExit),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<ExitGlyphPainter>()
        .single;
    expect(glyph.color, Palette.kid.outline);
    expect(
      find.descendant(of: find.byType(HoldToExit), matching: find.byType(Text)),
      findsNothing,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
