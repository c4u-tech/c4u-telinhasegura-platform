import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  test('brand colours equal brand/tokens/brand-tokens.json', () {
    final json = jsonDecode(
      File('../brand/tokens/brand-tokens.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final colors =
        (json['brand'] as Map<String, dynamic>)['color']
            as Map<String, dynamic>;
    String value(String name) =>
        (colors[name] as Map<String, dynamic>)[r'$value'] as String;

    expect(_hex(BrandColors.ink), value('ink'));
    expect(_hex(BrandColors.sun), value('sun'));
    expect(_hex(BrandColors.cream), value('cream'));
    expect(_hex(BrandColors.dark), value('dark'));
  });

  for (final palette in [Palette.light, Palette.dark]) {
    group('${palette.brightness.name} palette', () {
      test('text pairs reach WCAG AA 4.5:1', () {
        final pairs = {
          'text/ground': (palette.text, palette.ground),
          'muted/ground': (palette.muted, palette.ground),
          'error/ground': (palette.error, palette.ground),
          'text/input': (palette.text, palette.input),
          'error/input': (palette.error, palette.input),
          'error/errorGround': (palette.error, palette.errorGround),
          'onField/field': (palette.onField, palette.field),
          'onFieldMuted/field': (palette.onFieldMuted, palette.field),
          'onAction/action': (palette.onAction, palette.action),
        };
        for (final MapEntry(:key, value: (fg, bg)) in pairs.entries) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: key);
        }
      });

      test('component boundaries reach 3:1', () {
        expect(contrast(palette.outline, palette.ground), greaterThan(3));
        expect(contrast(palette.outline, palette.input), greaterThan(3));
        expect(contrast(palette.focus, palette.ground), greaterThan(3));
        expect(contrast(palette.action, palette.ground), greaterThan(3));
      });
    });
  }

  test('buttons draw a 3 dp focus ring only when focused (WCAG 2.4.7)', () {
    for (final b in Brightness.values) {
      final theme = buildTheme(b);
      for (final side in [
        theme.filledButtonTheme.style!.side!,
        theme.outlinedButtonTheme.style!.side!,
        theme.textButtonTheme.style!.side!,
      ]) {
        expect(side.resolve({WidgetState.focused})?.width, 3);
        expect(side.resolve({})?.width ?? 0, lessThan(3));
      }
    }
  });

  test('the themes use Bricolage Grotesque and the palette ground', () {
    for (final b in Brightness.values) {
      final theme = buildTheme(b);
      final palette = b == Brightness.light ? Palette.light : Palette.dark;
      expect(theme.scaffoldBackgroundColor, palette.ground);
      expect(theme.textTheme.bodyLarge?.fontFamily, Typefaces.family);
      expect(theme.textTheme.displaySmall?.fontFamily, Typefaces.family);
    }
  });

  group('kid palette', () {
    const kid = Palette.kid;

    test('the error note sits on dark, tinted from ink, ember on it at '
        'AA (fix round, item 2)', () {
      expect(kid.errorGround, BrandColors.dark);
      expect(kid.error, Palette.dark.error);
      expect(contrast(kid.error, BrandColors.dark), greaterThanOrEqualTo(4.5));
    });

    test('ink is the ground and cream the figure', () {
      expect(kid.ground, BrandColors.ink);
      expect(kid.field, BrandColors.ink);
      expect(kid.text, BrandColors.cream);
      expect(kid.action, BrandColors.cream);
      expect(kid.onAction, BrandColors.dark);
    });

    test('text pairs reach WCAG AA 4.5:1', () {
      final pairs = {
        'text/ground': (kid.text, kid.ground),
        'muted/ground': (kid.muted, kid.ground),
        'onAction/action': (kid.onAction, kid.action),
        'error/errorGround': (kid.error, kid.errorGround),
      };
      for (final MapEntry(:key, value: (fg, bg)) in pairs.entries) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: key);
      }
    });

    test('component boundaries reach 3:1 on ink', () {
      expect(contrast(kid.outline, kid.ground), greaterThan(3));
      expect(contrast(kid.action, kid.ground), greaterThan(3));
      expect(contrast(kid.focus, kid.ground), greaterThan(3));
      expect(contrast(kid.error, kid.ground), greaterThan(3));
    });

    test('a theme built on it carries it, so every widget paints on ink', () {
      final theme = buildTheme(Brightness.dark, Palette.kid);
      expect(theme.scaffoldBackgroundColor, BrandColors.ink);
      expect(theme.extension<PaletteTheme>()?.palette, Palette.kid);
      expect(
        buildTheme(Brightness.light).extension<PaletteTheme>()?.palette,
        Palette.light,
      );
    });
  });

  test('kid sizes: 64 dp targets and 96-128 dp avatars', () {
    expect(KidSizes.target, 64);
    expect(KidSizes.avatar, 96);
    expect(KidSizes.avatarLarge, 128);
    expect(KidSizes.avatarWide, 192);
  });
}
