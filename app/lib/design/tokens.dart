import 'package:flutter/widgets.dart';

/// The brand's six colours, copied from `brand/tokens/brand-tokens.json`
/// (tokens_test.dart fails if they drift).
abstract final class BrandColors {
  static const ink = Color(0xFF1E5B66);

  /// The mascot's body: a fill, never text.
  static const sun = Color(0xFFFFC42E);
  static const cream = Color(0xFFFBF6EC);
  static const dark = Color(0xFF0F2A30);

  /// The beak of the mark and the dot of the wordmark's i. It belongs to
  /// the mark: never an error colour, never text.
  static const beak = Color(0xFFFF5A36);

  /// A support ground, light enough for dark text.
  static const sky = Color(0xFFA9DDE8);
}

/// The UI palette the brand does not define. Every neutral is tinted from
/// ink. Sun, beak and sky are brand colours for the mark and its
/// grounds; none of them is text or a state colour. Sun also fills the
/// active indicator and, on the dark grounds, the primary action, always
/// under a dark label, never alone on a light ground.
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
    required this.indicator,
    required this.onIndicator,
    required this.focus,
    required this.error,
    required this.errorGround,
  });

  final Brightness brightness;

  /// The work ground every form sits on.
  final Color ground;

  /// The flat ink field the mascot stands on.
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

  /// The navigation's active destination: its indicator's fill and the
  /// icon on it.
  final Color indicator;
  final Color onIndicator;
  final Color focus;

  /// A warm earth tone: errors are calm, never alarm red.
  final Color error;
  final Color errorGround;

  static const light = Palette(
    brightness: Brightness.light,
    ground: BrandColors.cream,
    field: BrandColors.ink,
    onField: BrandColors.cream,
    onFieldMuted: Color(0xFFD3E2E3),
    text: BrandColors.dark,
    muted: Color(0xFF4A666B),
    input: Color(0xFFFFFDF8),
    outline: Color(0xFF6F8B90),
    action: BrandColors.ink,
    onAction: BrandColors.cream,
    indicator: BrandColors.sun,
    onIndicator: BrandColors.dark,
    focus: BrandColors.ink,
    error: Color(0xFF974614),
    errorGround: Color(0xFFF6E8DB),
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
    action: BrandColors.sun,
    onAction: BrandColors.dark,
    indicator: BrandColors.sun,
    onIndicator: BrandColors.dark,
    focus: Color(0xFFA6BFC2),
    error: Color(0xFFEFA97E),
    errorGround: Color(0xFF2B2E28),
  );

  /// The kid dialect: the child is inside the ink field, so ink
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
    action: BrandColors.sun,
    onAction: BrandColors.dark,
    indicator: BrandColors.sun,
    onIndicator: BrandColors.dark,
    focus: BrandColors.cream,
    error: Color(0xFFEFA97E),
    errorGround: BrandColors.dark,
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

/// Corner radii cut from the mascot's body, a rounded rectangle 70 units
/// tall with a 26-unit corner: every control keeps that ratio to its
/// height, so a button reads as the same soft block the mascot is.
abstract final class Radii {
  /// The shape ratio: a corner over the height it rounds.
  static const screenRatio = 26 / 70;

  /// A 56 dp control (the theme's buttons and fields) at the ratio: 20.8.
  static const control = 56 * screenRatio;
  static const small = 8.0;

  /// A panel that groups several rows.
  static const card = 28.0;
}

/// Sizes of the flat field and the mascot standing on it.
abstract final class FieldSizes {
  /// The grid each field's corner is cut on: 10 units.
  static const heroUnit = 3.0;
  static const bandUnit = 1.75;

  /// The mascot standing on the entry field.
  static const heroTevi = 112.0;

  /// The mascot standing on the band: small enough that a task screen's
  /// first section still starts above the fold of a common phone.
  static const bandTevi = 72.0;
  static const wideBreakpoint = 840.0;
  // Google's rendered web button tops out at 400 px; every control in
  // the column shares that width so their edges line up.
  static const columnMaxWidth = 400.0;

  /// From this much room for its column, a page of sections (a child's
  /// page) sets its first two side by side: two 300 px columns, as wide
  /// as a small phone's, 24 px apart.
  static const pairedMinWidth = 2 * 300.0 + Space.xl;
}

/// The guardian's navigation: the ink rail on a wide window and the bar
/// on a narrow one. The selected destination's indicator has the
/// mascot's body proportions (84 × 70) at [indicator] tall, cornered at
/// the same ratio.
abstract final class ShellSizes {
  /// The grid the rail's corner is cut on: 10 units.
  static const railUnit = 2.0;

  /// The mascot standing on the rail: it takes about the room above the
  /// rail that the navigation always kept there.
  static const railTevi = 72.0;
  static const railWidth = 248.0;

  /// The rail's field inset from the window, as the wide panel's was.
  static const railInset = Space.lg;
  static const indicator = 32.0;
  static const indicatorWidth = indicator * 84 / 70;

  /// A destination's row in the rail, a control's height.
  static const railItem = 56.0;

  /// From this width a place of several items (the family, the account,
  /// the team) shows its list and the item it opens side by side: the
  /// large window class, which a 10 to 11 inch tablet in landscape
  /// reaches (about 1317 dp), while the same tablet in portrait and a
  /// small laptop window keep one column.
  static const listDetailBreakpoint = 1200.0;

  /// The list's pane beside the rail, before the reed hairline.
  static const listPaneWidth = 320.0;
}

/// The wordmark's box height in each ink field. The wordmark is the
/// field's name plate, so it is never the smallest text in the field.
abstract final class WordmarkSizes {
  static const band = 20.0;
  static const rail = 22.0;
  static const hero = 28.0;
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
