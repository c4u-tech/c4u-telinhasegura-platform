import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/press_sink.dart';

import '../design/pump.dart';

const _target = Key('target');

/// The scale [PressSink] draws its child at now.
double scale(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(PressSink),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .entry(0, 0);

Future<List<String>> pumpTarget(
  WidgetTester tester, {
  bool still = false,
  bool enabled = true,
  Size size = const Size.square(200),
}) async {
  final taps = <String>[];
  await pumpOn(
    tester,
    PressSink(
      enabled: enabled,
      child: Semantics(
        button: true,
        label: 'Bichos',
        onTap: () => taps.add('semantics'),
        child: GestureDetector(
          key: _target,
          onTap: () => taps.add('tap'),
          child: ColoredBox(
            color: BrandColors.sun,
            child: SizedBox.fromSize(size: size),
          ),
        ),
      ),
    ),
    disableAnimations: still,
  );
  return taps;
}

void main() {
  testWidgets('pressed, a target sinks to 96 % in 90 ms and comes back up '
      'in 160 ms once let go', (tester) async {
    final taps = await pumpTarget(tester);
    expect(scale(tester), 1);

    final press = await tester.startGesture(
      tester.getCenter(find.byKey(_target)),
    );
    await tester.pump();
    await tester.pump(Motion.press ~/ 2);
    expect(scale(tester), inExclusiveRange(PressSink.depth, 1));
    await tester.pump(Motion.press ~/ 2);
    expect(scale(tester), closeTo(PressSink.depth, 1e-9));
    expect(PressSink.depth, .96);

    await press.up();
    await tester.pump();
    await tester.pump(Motion.release ~/ 2);
    expect(scale(tester), inExclusiveRange(PressSink.depth, 1));
    await tester.pump(Motion.release ~/ 2);
    expect(scale(tester), closeTo(1, 1e-9));
    expect(taps, ['tap'], reason: 'the tap still lands, once');
  });

  testWidgets('under reduced motion it is a cut, down and up', (tester) async {
    await pumpTarget(tester, still: true);
    final press = await tester.startGesture(
      tester.getCenter(find.byKey(_target)),
    );
    await tester.pump();
    expect(scale(tester), PressSink.depth);
    expect(tester.binding.transientCallbackCount, 0);

    await press.up();
    await tester.pump();
    expect(scale(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a small target sinks at least 3 dp at each edge, never below '
      '90 %; a large one keeps 96 %', (tester) async {
    for (final (size, depth) in [
      (const Size.square(64), 1 - 6 / 64),
      (const Size(300, 64), 1 - 6 / 64),
      (const Size.square(150), .96),
      (const Size(320, 240), .96),
      (const Size.square(40), .9),
    ]) {
      await pumpTarget(tester, size: size);
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(_target)),
      );
      await tester.pumpAndSettle();
      expect(scale(tester), closeTo(depth, 1e-9), reason: '$size');
      await press.up();
      await tester.pumpAndSettle();
      expect(scale(tester), 1);
    }
    expect(PressSink.depthOf(const Size.square(64)), closeTo(.91, .005));
  });

  testWidgets('a target that cannot act does not sink', (tester) async {
    await pumpTarget(tester, enabled: false);
    final press = await tester.startGesture(
      tester.getCenter(find.byKey(_target)),
    );
    await tester.pumpAndSettle();
    expect(scale(tester), 1);
    await press.up();
  });

  testWidgets('a finger that slides off, as into a scroll, lets it come back '
      'up', (tester) async {
    await pumpTarget(tester);
    final press = await tester.startGesture(
      tester.getCenter(find.byKey(_target)),
    );
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(PressSink.depth, 1e-9));

    await press.moveBy(const Offset(0, kTouchSlop * 2));
    await tester.pumpAndSettle();
    expect(scale(tester), 1);
    await press.up();
  });

  testWidgets('sunk, its hit area and its semantics stay as they were', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final taps = await pumpTarget(tester);
    final box = tester.getRect(find.byKey(_target));
    final before = tester.getSemantics(find.bySemanticsLabel('Bichos'));

    final press = await tester.startGesture(box.center);
    await tester.pumpAndSettle();
    // A corner the sunk picture no longer covers still takes a touch.
    final corner = box.topLeft + const Offset(1, 1);
    final hits = HitTestResult();
    tester.binding.hitTestInView(hits, corner, tester.view.viewId);
    expect(
      hits.path.any(
        (e) => e.target == tester.renderObject(find.byKey(_target)),
      ),
      isTrue,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Bichos')),
      matchesSemantics(isButton: true, label: before.label, hasTapAction: true),
    );
    await press.up();
    await tester.pumpAndSettle();
    expect(taps, ['tap']);
    semantics.dispose();
  });
}
