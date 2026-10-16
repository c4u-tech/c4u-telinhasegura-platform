import 'package:flutter/material.dart';

import 'tokens.dart';

extension PaletteOf on BuildContext {
  /// The ambient theme's palette: the kid dialect's under a kid theme,
  /// otherwise the one of its brightness.
  Palette get palette {
    final theme = Theme.of(this);
    return theme.extension<PaletteTheme>()?.palette ??
        (theme.brightness == Brightness.light ? Palette.light : Palette.dark);
  }
}

/// Carries the palette a theme was built from, so a subtree themed in the
/// kid dialect paints every shared widget on ink.
class PaletteTheme extends ThemeExtension<PaletteTheme> {
  const PaletteTheme(this.palette);

  final Palette palette;

  @override
  PaletteTheme copyWith({Palette? palette}) =>
      PaletteTheme(palette ?? this.palette);

  @override
  PaletteTheme lerp(PaletteTheme? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Bricolage Grotesque is variable: weight and optical size are axes, so
/// each style names both (Flutter does not map [FontWeight] onto `wght`
/// on every platform).
TextStyle _face(
  double size,
  double height,
  double weight, {
  double? opsz,
  double tracking = 0,
}) => TextStyle(
  fontFamily: Typefaces.family,
  fontSize: size,
  height: height / size,
  letterSpacing: tracking * size,
  fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
  fontVariations: [
    FontVariation('wght', weight),
    FontVariation('opsz', opsz ?? size.clamp(12, 96)),
  ],
);

/// The type ramp: a decisive display step for each screen's one task,
/// then plain reading sizes.
TextTheme _textTheme(Color text, Color muted) => TextTheme(
  // The field's focal scale on wide screens; titles step down from it.
  displayLarge: _face(58, 62, 700, opsz: 72, tracking: -0.025),
  displaySmall: _face(36, 40, 720, tracking: -0.02),
  headlineSmall: _face(24, 30, 560, tracking: -0.01),
  titleLarge: _face(22, 28, 600, tracking: -0.01),
  titleMedium: _face(18, 24, 600),
  bodyLarge: _face(16, 24, 400, opsz: 14),
  bodyMedium: _face(15, 22, 400, opsz: 14),
  bodySmall: _face(13, 18, 450, opsz: 12),
  labelLarge: _face(16, 20, 620, opsz: 14),
  labelMedium: _face(14, 18, 560, opsz: 14),
).apply(bodyColor: text, displayColor: text);

/// The keyboard focus ring (WCAG 2.4.7): a 3 dp line outside the control,
/// dark on light and pale on dark, so it shows against both the ground and
/// a filled action. [rest] is the side when not focused.
WidgetStateProperty<BorderSide?> focusRing(Palette p, [BorderSide? rest]) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(
              color: p.brightness == Brightness.light ? p.text : p.muted,
              width: 3,
              strokeAlign: BorderSide.strokeAlignOutside,
            )
          : rest,
    );

/// The theme of [brightness], or of [palette] when given (the kid dialect).
ThemeData buildTheme(Brightness brightness, [Palette? palette]) {
  final p =
      palette ??
      (brightness == Brightness.light ? Palette.light : Palette.dark);
  final text = _textTheme(p.text, p.muted);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.control),
  );
  const minimum = Size(64, 56);
  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.control),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    // 56 dp controls on every platform: compact web density would break
    // the 10/33 corner ratio the radii are cut for.
    visualDensity: VisualDensity.standard,
    brightness: brightness,
    fontFamily: Typefaces.family,
    scaffoldBackgroundColor: p.ground,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: p.action,
      onPrimary: p.onAction,
      secondary: p.field,
      onSecondary: p.onField,
      error: p.error,
      onError: p.ground,
      surface: p.ground,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      outline: p.outline,
      surfaceContainerHighest: p.input,
    ),
    textTheme: text,
    focusColor: p.focus.withValues(alpha: 0.16),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.focus,
      selectionColor: p.focus.withValues(alpha: 0.24),
      selectionHandleColor: p.focus,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.outline.withValues(alpha: 0.6)),
      radius: const Radius.circular(Radii.small),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.action,
        foregroundColor: p.onAction,
        disabledBackgroundColor: p.outline.withValues(alpha: 0.32),
        disabledForegroundColor: p.text.withValues(alpha: 0.6),
        minimumSize: minimum,
        shape: shape,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      ).copyWith(side: focusRing(p)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        minimumSize: minimum,
        shape: shape,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      ).copyWith(side: focusRing(p, BorderSide(color: p.outline, width: 1.5))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.text,
        minimumSize: const Size(48, 48),
        textStyle: text.labelLarge?.copyWith(
          decoration: TextDecoration.underline,
          decorationThickness: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small),
        ),
      ).copyWith(side: focusRing(p)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.input,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: 18,
      ),
      labelStyle: text.bodyLarge?.copyWith(color: p.muted),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: p.text),
      helperStyle: text.bodySmall?.copyWith(color: p.muted),
      errorStyle: text.bodySmall?.copyWith(color: p.error),
      errorMaxLines: 3,
      helperMaxLines: 3,
      border: border(p.outline),
      enabledBorder: border(p.outline),
      focusedBorder: border(p.focus, 2.5),
      errorBorder: border(p.error),
      focusedErrorBorder: border(p.error, 2.5),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: p.outline, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.action : p.input,
      ),
      checkColor: WidgetStatePropertyAll(p.onAction),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.onAction),
    iconTheme: IconThemeData(color: p.text),
    extensions: [PaletteTheme(p)],
  );
}
