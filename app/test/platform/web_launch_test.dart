import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/shell/splash.dart';

String hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  final page = File('web/index.html').readAsStringSync();

  test('before the app paints, the page shows the launch ground and the '
      'mascot\'s body alone, in both themes', () {
    final launch = page.indexOf('<div id="launch"');
    expect(launch, greaterThan(page.indexOf('<body>')));
    expect(launch, lessThan(page.indexOf('flutter_bootstrap.js"')));
    expect(
      page,
      contains(
        '#launch { position: fixed; inset: 0; '
        'background: ${hex(BrandColors.ink.toARGB32())}; }',
      ),
    );
    final svg = RegExp(
      r'<svg[^>]*>(.*?)</svg>',
      dotAll: true,
    ).firstMatch(page.substring(launch))!;
    expect(
      svg.group(1),
      '<rect x="14" y="20" width="84" height="70" rx="26" '
      'fill="${hex(BrandColors.sun.toARGB32())}"/>',
      reason: 'the body alone, as on the native launch screens',
    );
    expect(page, isNot(contains('prefers-color-scheme: dark) { #launch')));
  });

  test('the body stands where the app\'s opening draws it on the web', () {
    const box = Opening.markSide;
    final side = box == box.roundToDouble() ? '${box.round()}' : '$box';
    final c = TeviPainter.drawingCentre;
    expect(page, contains('width: ${side}px; height: ${side}px;'));
    expect(
      page,
      contains(
        'left: calc(50% - ${side}px * ${c.dx.toStringAsFixed(6)}); '
        'top: calc(50% - ${side}px * ${c.dy.toStringAsFixed(6)});',
      ),
    );
  });

  test('the ground goes once the app has painted its first frame', () {
    expect(page, contains("addEventListener('flutter-first-frame'"));
  });
}
