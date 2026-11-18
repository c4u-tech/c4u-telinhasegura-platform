import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/design/wordmark.dart';

void main() {
  testWidgets('the wordmark keeps its proportions at every size', (
    tester,
  ) async {
    for (final h in [
      WordmarkSizes.band,
      WordmarkSizes.rail,
      WordmarkSizes.hero,
    ]) {
      await tester.pumpWidget(Center(child: Wordmark(height: h)));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(Wordmark));
      expect(size.height, h);
      expect(size.width / size.height, closeTo(387.24 / 60, 0.05));
    }
  });

  test('the wordmark keeps its coral dot: cream letters and the beak '
      'colour for the play mark over the i', () {
    final svg = File(Wordmark.asset).readAsStringSync();
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
            .toUpperCase();
    final fills = RegExp(r'fill="(#[0-9A-Fa-f]{6})"')
        .allMatches(svg)
        .map((m) => m.group(1)!.toUpperCase())
        .toSet();
    expect(fills, {hex(BrandColors.cream), hex(BrandColors.beak)});
  });
}
