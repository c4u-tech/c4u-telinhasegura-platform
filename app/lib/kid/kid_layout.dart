import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/espiadinha.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// The frame of every child screen, "dentro da telinha":
/// the ink field is the whole ground, edge to edge, in either
/// theme; the simplified mark sits small at the top strip's start, quiet
/// (fullscreen design); [exit] takes the top end corner; [child] is
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
    this.fullWidth = false,
    this.scrolls = true,
    this.strip = true,
  }) : assert(scrolls || fullWidth, 'only a full-width screen fills'),
       assert(strip || !scrolls, 'only a screen that fills goes bare');

  final Widget child;

  /// Lays [child] across the whole width, from the top, unpadded at the
  /// sides, instead of centred in the 400 px column.
  final bool fullWidth;

  /// False: [child] fills the space below the strip, which never scrolls.
  final bool scrolls;

  /// The exit control, if the screen has one.
  final Widget? exit;

  /// False: no top strip, neither mark nor exit; [child] fills the safe
  /// area (the player in fullscreen, fullscreen design).
  final bool strip;

  /// The simplified mark's tier is 20–47 px; small and quiet, not a
  /// heading.
  static const markSize = 24.0;

  /// The exit's inset from the safe area's top and side: its ring, 2 dp
  /// inside its 64 dp target, stands clear of the edges, level with the
  /// mark centred in the same strip.
  static const exitInset = Space.lg;

  static double _vertical(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return math.max(pad.top, pad.bottom);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: buildTheme(Brightness.dark, Palette.kid),
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Palette.kid.ground,
        // Bare, the safe area's larger vertical inset stands on both sides,
        // so what fills it is centred on the screen, clear of a home
        // indicator (fullscreen design).
        body: SafeArea(
          top: strip,
          bottom: strip,
          minimum: strip
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(vertical: _vertical(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (strip)
                SizedBox(
                  height: KidSizes.target + 2 * exitInset,
                  child: Stack(
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: Space.xl,
                          ),
                          child: Semantics(
                            image: true,
                            label: 'Telinha Segura',
                            child: const CustomPaint(
                              size: Size.square(markSize),
                              painter: SimplifiedMarkPainter(),
                            ),
                          ),
                        ),
                      ),
                      if (exit case final exit?)
                        PositionedDirectional(
                          top: exitInset,
                          end: exitInset,
                          child: exit,
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: !scrolls
                    ? child
                    : fullWidth
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: Space.xl),
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
  );
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
