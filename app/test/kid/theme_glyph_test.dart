import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/curation.dart' show VideoTheme;
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/theme_glyph.dart';

/// A glyph drawn in [world] at 128 px: for each pixel, how far its colour
/// has moved from the ground toward the figure, 0 to 1.
Future<List<double>> coverage(
  WidgetTester tester,
  ColourWorld world,
  CustomPainter Function(ColourWorld world) painter,
) async {
  const side = 128;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, side + .0, side + .0),
      Paint()..color = world.ground,
    );
  painter(world).paint(canvas, const Size.square(side + .0));
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
  return [
    for (var p = 0; p < side * side; p++)
      () {
        var moved = 0.0, span = 0.0;
        for (var i = 0; i < 3; i++) {
          final g = channel(world.ground, i);
          moved += (bytes.getUint8(p * 4 + i) - g).abs();
          span += (channel(world.figure, i) - g).abs();
        }
        return moved / span;
      }(),
  ];
}

/// The seven glyphs, each in the world it stands on: the six themes in
/// theirs, the pacotinhos' on the home's.
Map<String, (ColourWorld, CustomPainter Function(ColourWorld))> get glyphs => {
  for (final t in VideoTheme.values)
    if (t != VideoTheme.unknown)
      t.name: (
        worldOf(t),
        (w) => ThemeGlyphPainter(t, color: w.figure, ground: w.ground),
      ),
  'pacotinhos': (ColourWorlds.home, (w) => PackGlyphPainter(color: w.figure)),
};

void main() {
  testWidgets('the seven glyphs weigh alike: each covers within a fifth of '
      'their mean', (tester) async {
    final weights = <String, double>{};
    for (final MapEntry(:key, value: (world, painter)) in glyphs.entries) {
      final c = await coverage(tester, world, painter);
      weights[key] = c.reduce((a, b) => a + b) / c.length;
    }
    final mean = weights.values.reduce((a, b) => a + b) / weights.length;
    for (final MapEntry(:key, :value) in weights.entries) {
      expect(value / mean, inInclusiveRange(.8, 1.2), reason: key);
    }
  });

  testWidgets('each glyph is one colour on its ground: no mid tone, only '
      'the edges between them', (tester) async {
    for (final MapEntry(:key, value: (world, painter)) in glyphs.entries) {
      final c = await coverage(tester, world, painter);
      final drawn = c.where((v) => v > .1).length;
      final mid = c.where((v) => v > .2 && v < .8).length;
      // Anti-aliased edges are a thin share; a filled mid tone is not.
      expect(mid / drawn, lessThan(.12), reason: key);
    }
  });
}
