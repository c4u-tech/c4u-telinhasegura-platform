import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// The frame of every child screen, "dentro da telinha":
/// the ink field is the whole ground, edge to edge, in either
/// theme; the simplified mascot sits small at the top strip's start, quiet
/// (fullscreen design), unless a [lead] takes its place; [exit] takes the
/// top end corner; [child] is
/// centred in a column that scrolls rather than overflow. Everything inside paints in the kid dialect. A [fullWidth]
/// screen (the shelves) takes the whole width from the top instead, its
/// rows running to the screen's edges. A screen that must not scroll (the
/// player, whose surface takes no gesture of ours) fills the space below
/// the strip instead.
class KidLayout extends StatelessWidget {
  const KidLayout({
    super.key,
    required this.child,
    this.exit,
    this.lead,
    this.mark = true,
    this.leadInset = Space.xl,
    this.ground,
    this.rise = 0,
    this.fullWidth = false,
    this.scrolls = true,
    this.strip = true,
  }) : assert(scrolls || fullWidth, 'only a full-width screen fills'),
       assert(strip || !scrolls, 'only a screen that fills goes bare'),
       assert(rise == 0 || (strip && !scrolls), 'only a filled strip rises');

  final Widget child;

  /// Lays [child] across the whole width, from the top, unpadded at the
  /// sides, instead of centred in the 400 px column.
  final bool fullWidth;

  /// False: [child] fills the space below the strip, which never scrolls.
  final bool scrolls;

  /// The exit control, if the screen has one.
  final Widget? exit;

  /// What stands at the strip's start in the mark's place (the child's
  /// own avatar on their home).
  final Widget? lead;

  /// False: without [lead] the strip's start stays empty. Where the
  /// mascot stands whole on the screen, a small one beside it says
  /// nothing more.
  final bool mark;

  /// [lead]'s distance from the start edge: a key as large as the exit
  /// stands as far from its edge as the exit does from its own.
  final double leadInset;

  /// The ground edge to edge, when the screen is a theme's world rather
  /// than the ink field.
  final Color? ground;

  /// How far [child] reaches up into the strip, between [lead] and
  /// [exit]: the mascot standing on the home's first picture lifts its
  /// head there. The strip has no ground of its own, so what rises shows,
  /// and [lead] and [exit] stay above it and keep their taps.
  final double rise;

  /// The strip's height: the exit's target and its inset on both sides.
  static const stripHeight = KidSizes.target + 2 * exitInset;

  /// False: no top strip, neither mark nor exit; [child] fills the safe
  /// area (the player in fullscreen, fullscreen design).
  final bool strip;

  /// The simplified mascot, small and quiet: not a heading.
  static const markSize = 24.0;

  /// The exit's inset from the safe area's top and side: its ring, 2 dp
  /// inside its 64 dp target, stands clear of the edges, level with the
  /// mark centred in the same strip.
  static const exitInset = Space.lg;

  static double _vertical(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return math.max(pad.top, pad.bottom);
  }

  Widget _strip() => SizedBox(
    height: stripHeight,
    child: Stack(
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: leadInset),
            // The figure takes its colours from the ground below it.
            child:
                lead ??
                (mark
                    ? Builder(
                        builder: (context) => Tevi(
                          size: markSize,
                          tier: TeviTier.simplified,
                          night: TeviGround.nightAt(context),
                          semanticLabel: 'Telinha Segura',
                        ),
                      )
                    : const SizedBox.shrink()),
          ),
        ),
        if (exit case final exit?)
          PositionedDirectional(top: exitInset, end: exitInset, child: exit),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: buildTheme(Brightness.dark, Palette.kid),
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _ground,
        // Bare, the safe area's larger vertical inset stands on both sides,
        // so what fills it is centred on the screen, clear of a home
        // indicator (fullscreen design).
        // Every mascot on the screen reads this ground for its colours.
        body: TeviGround(
          color: _ground,
          child: SafeArea(
            top: strip,
            bottom: strip,
            minimum: strip
                ? EdgeInsets.zero
                : EdgeInsets.symmetric(vertical: _vertical(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (strip && rise == 0) _strip(),
                Expanded(
                  child: rise > 0
                      ? Stack(
                          children: [
                            Positioned.fill(
                              top: stripHeight - rise,
                              child: child,
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: stripHeight,
                              child: _strip(),
                            ),
                          ],
                        )
                      : !scrolls
                      ? child
                      : fullWidth
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.xl,
                          ),
                          child: child,
                        )
                      : LayoutBuilder(
                          builder: (context, box) => SingleChildScrollView(
                            padding: const EdgeInsets.all(Space.xl),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: box.maxHeight - 2 * Space.xl,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: FieldSizes.columnMaxWidth,
                                  ),
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Color get _ground => ground ?? Palette.kid.ground;
}

/// The quiet "Voltar" of a child screen, at the child side's 64 dp:
/// centred, as everything on the child side is,
/// its label centred in its own target.
class KidBack extends StatelessWidget {
  const KidBack({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.square(KidSizes.target),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
      ),
      child: const Text('Voltar'),
    ),
  );
}
