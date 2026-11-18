import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/curation.dart' show VideoTheme;
import 'package:telinha_segura/kid/theme_glyph.dart';

/// How much of a glyph drawn in its world reads as figure: each pixel
/// counts by how far its colour has moved from the ground toward the
/// figure, over the glyph's whole square.
Future<double> weight(WidgetTester tester, VideoTheme theme) async {
  final world = worldOf(theme);
  const side = 128;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, side + .0, side + .0),
      Paint()..color = world.ground,
    );
  ThemeGlyphPainter(
    theme,
    color: world.figure,
    ground: world.ground,
  ).paint(canvas, const Size.square(side + .0));
  final image = await tester.runAsync(
    () => recorder.endRecording().toImage(side, side),
  );
  final bytes = (await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  double channel(Color c, int i) =>
      switch (i) {
        0 => c.r,
        1 => c.g,
        _ => c.b,
      } *
      255;
  var sum = 0.0;
  for (var p = 0; p < side * side; p++) {
    var moved = 0.0, span = 0.0;
    for (var i = 0; i < 3; i++) {
      final g = channel(world.ground, i);
      moved += (bytes.getUint8(p * 4 + i) - g).abs();
      span += (channel(world.figure, i) - g).abs();
    }
    sum += moved / span;
  }
  return sum / (side * side);
}

void main() {
  testWidgets('drawn in its world, the ball weighs no more than the other '
      'five glyphs do on average', (tester) async {
    final weights = {
      for (final t in VideoTheme.values)
        if (t != VideoTheme.unknown) t: await weight(tester, t),
    };
    final ball = weights.remove(VideoTheme.brincar)!;
    final mean = weights.values.reduce((a, b) => a + b) / weights.length;
    expect(ball, lessThanOrEqualTo(mean));
  });
}
