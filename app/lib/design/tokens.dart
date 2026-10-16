import 'package:flutter/widgets.dart';

/// The brand's four colours, copied from `brand/tokens/brand-tokens.json`
/// (tokens_test.dart fails if they drift).
abstract final class BrandColors {
  static const ink = Color(0xFF1E5B66);
  static const sun = Color(0xFFF2B23A);
  static const cream = Color(0xFFFBF6EC);
  static const dark = Color(0xFF0F2A30);
}

/// The UI palette the brand does not define. Every neutral is tinted from
/// ink; sun appears only in the Espiadinha's head, never as text or state.
/// Contrast pairs are asserted in tokens_test.dart.
class Palette {
  const Palette({
    required this.brightness,
    required this.ground,
    required this.field,
    required this.onField,
    required this.onFieldMuted,
    required this.text,
    required this.muted,
    required this.input,
    required this.outline,
    required this.action,
    required this.onAction,
    required this.focus,
    required this.error,
    required this.errorGround,
    required this.headOutline,
  });

  final Brightness brightness;

  /// The work ground every form sits on.
  final Color ground;

  /// The flat ink field: the Espiadinha's screen.
  final Color field;
  final Color onField;
  final Color onFieldMuted;
  final Color text;
  final Color muted;
  final Color input;
  final Color outline;

  /// The primary action's fill.
  final Color action;
  final Color onAction;
  final Color focus;

  /// A warm earth tone: errors are calm, never alarm red.
  final Color error;
  final Color errorGround;

  /// The head's outline: required on light grounds (identity.md, Colour).
  final Color headOutline;

  static const light = Palette(
    brightness: Brightness.light,
    ground: BrandColors.cream,
    field: BrandColors.ink,
    onField: BrandColors.cream,
    onFieldMuted: Color(0xFFD3E2E3),
    text: Color(0xFF12343B),
    muted: Color(0xFF4A666B),
    input: Color(0xFFFFFDF8),
    outline: Color(0xFF6F8B90),
    action: BrandColors.ink,
    onAction: BrandColors.cream,
    focus: BrandColors.ink,
    error: Color(0xFF974614),
    errorGround: Color(0xFFF6E8DB),
    headOutline: BrandColors.ink,
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    ground: BrandColors.dark,
    field: BrandColors.ink,
    onField: BrandColors.cream,
    onFieldMuted: Color(0xFFD3E2E3),
    text: BrandColors.cream,
    muted: Color(0xFFA6BFC2),
    input: Color(0xFF16363D),
    outline: Color(0xFF6A8D93),
    action: BrandColors.cream,
    onAction: BrandColors.dark,
    focus: Color(0xFFA6BFC2),
    error: Color(0xFFEFA97E),
    errorGround: Color(0xFF2B2E28),
    headOutline: BrandColors.dark,
  );

  /// The kid dialect: the child is inside the Espiadinha's screen, so ink
  /// is the ground in both themes and cream the figure. Errors keep
  /// ember, on dark (tinted from ink) rather than the olive of the night
  /// palette; ember reads as text only on that ground.
  static const kid = Palette(
    brightness: Brightness.dark,
    ground: BrandColors.ink,
    field: BrandColors.ink,
    onField: BrandColors.cream,
    onFieldMuted: Color(0xFFD3E2E3),
    text: BrandColors.cream,
    muted: Color(0xFFD3E2E3),
    input: Color(0xFF16363D),
    outline: Color(0xFFA6BFC2),
    action: BrandColors.cream,
    onAction: BrandColors.dark,
    focus: BrandColors.cream,
    error: Color(0xFFEFA97E),
    errorGround: BrandColors.dark,
    headOutline: BrandColors.dark,
  );
}

/// One spacing rhythm: 4-point steps.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Corner radii cut from the mark's screen (radius 10 on a 33-unit-tall
/// rectangle): every control keeps that ratio to its height.
abstract final class Radii {
  static const screenRatio = 10 / 33;

  /// A 56 dp control.
  static const control = 17.0;
  static const small = 8.0;
}

/// Sizes of the flat field and its Espiadinha.
abstract final class FieldSizes {
  /// Grid unit of the mark on the entry field: the head radius is 14 units.
  static const heroUnit = 3.0;
  static const bandUnit = 1.75;
  static const wideBreakpoint = 840.0;
  // Google's rendered web button tops out at 400 px; every control in
  // the column shares that width so their edges line up.
  static const columnMaxWidth = 400.0;
}

/// The kid dialect's sizes: small hands get 64 dp targets (the PIN keys
/// too), and a child finds themself by a 96 dp+ avatar; the child home's
/// grows to [avatarWide] on wide screens.
abstract final class KidSizes {
  static const target = 64.0;
  static const avatar = 96.0;
  static const avatarLarge = 128.0;
  static const avatarWide = 192.0;
}

abstract final class Typefaces {
  static const family = 'Bricolage Grotesque';
}
