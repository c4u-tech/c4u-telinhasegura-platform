import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'espiadinha.dart';
import 'tokens.dart';

/// Which way the ink field moves between the guardian and the child.
enum BandMotion {
  /// Hand-over: the guardian's band grows until the screen is the child's
  /// telinha.
  grow,

  /// Unlock: the child's full screen closes back onto the band.
  shrink,
}

/// Where the guardian layout draws its ink field on a screen of [size]
/// with [padding] as safe area (Layout, FieldLayout): narrow,
/// the 72 dp band inset 12 px at the sides and 8 px at the top under the
/// head strip; wide, the 46% panel inset 16 px.
RRect guardianBand(Size size, EdgeInsets padding) {
  final width = size.width - padding.horizontal;
  if (width >= FieldSizes.wideBreakpoint) {
    const unit = 4.0;
    return RRect.fromLTRBR(
      padding.left + Space.lg,
      padding.top + Space.lg + EspiadinhaPainter.height * unit,
      padding.left + width * 0.46 - Space.lg,
      size.height - padding.bottom - Space.lg,
      const Radius.circular(10 * unit),
    );
  }
  const unit = FieldSizes.bandUnit;
  final top = padding.top + Space.sm + EspiadinhaPainter.height * unit;
  return RRect.fromLTRBR(
    padding.left + Space.md,
    top,
    size.width - padding.right - Space.md,
    top + 72,
    const Radius.circular(10 * unit),
  );
}

/// The signature move between the two worlds: the ink field growing from
/// the guardian's band to the whole screen ([BandMotion.grow]) or closing
/// back onto it ([BandMotion.shrink]), ease-out over [duration]. Under
/// reduced motion it is a cut; at rest it leaves [child] untouched.
class BandTransition extends AnimatedWidget {
  const BandTransition({
    super.key,
    required Animation<double> animation,
    required this.motion,
    required this.child,
  }) : super(listenable: animation);

  static const duration = Duration(milliseconds: 400);
  static const curve = Curves.easeOutCubic;

  final BandMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    if (MediaQuery.disableAnimationsOf(context) || animation.isCompleted) {
      return child;
    }
    final size = MediaQuery.sizeOf(context);
    final band = guardianBand(size, MediaQuery.paddingOf(context));
    final full = RRect.fromRectAndRadius(Offset.zero & size, Radius.zero);
    final t = curve.transform(animation.value);
    return switch (motion) {
      BandMotion.grow => ClipPath(
        clipper: BandClipper(RRect.lerp(band, full, t)!),
        child: child,
      ),
      BandMotion.shrink => Stack(
        fit: StackFit.expand,
        children: [
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: InkFieldPainter(RRect.lerp(full, band, t)!),
            ),
          ),
        ],
      ),
    };
  }
}

/// Clips the incoming child screen to the growing field.
class BandClipper extends CustomClipper<Path> {
  const BandClipper(this.rrect);

  final RRect rrect;

  @override
  Path getClip(Size size) => Path()..addRRect(rrect);

  @override
  bool shouldReclip(BandClipper old) => old.rrect != rrect;
}

/// The closing field drawn over the guardian screen it returns to.
class InkFieldPainter extends CustomPainter {
  const InkFieldPainter(this.rrect);

  final RRect rrect;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRRect(rrect, Paint()..color = BrandColors.ink);

  @override
  bool shouldRepaint(InkFieldPainter old) => old.rrect != rrect;
}

CustomTransitionPage<T> _bandPage<T>(
  BandMotion motion,
  LocalKey? key,
  Widget child,
) => CustomTransitionPage<T>(
  key: key,
  transitionDuration: BandTransition.duration,
  reverseTransitionDuration: BandTransition.duration,
  child: child,
  transitionsBuilder: (context, animation, _, child) =>
      BandTransition(animation: animation, motion: motion, child: child),
);

/// A go_router page entering the child side: the band grows into it
/// (popping it plays the reverse).
CustomTransitionPage<T> bandGrowPage<T>({
  LocalKey? key,
  required Widget child,
}) => _bandPage(BandMotion.grow, key, child);

/// The page of a route reached both ways (the family home): with
/// [motion] the child's screen closes back onto the band over it, without
/// it the theme's ordinary page transition plays. An unlock arrives twice
/// at the same location: the mode's redirect and a later refresh carry no
/// motion, the unlock's own `go` does. A page type that changed with the
/// motion would stack a second, still animating copy of the screen over
/// the first; this one is the same route throughout, and keeps the first
/// motion it is given while it lives.
class BandArrivalPage<T> extends Page<T> {
  const BandArrivalPage({super.key, this.motion, required this.child});

  final BandMotion? motion;
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _BandArrivalRoute<T>(this);
}

class _BandArrivalRoute<T> extends PageRoute<T> {
  _BandArrivalRoute(BandArrivalPage<T> page) : super(settings: page);

  BandMotion? _motion;

  BandArrivalPage<T> get _page => settings as BandArrivalPage<T>;

  @override
  Duration get transitionDuration => BandTransition.duration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: _page.child,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => switch (_motion ??= _page.motion) {
    final motion? => BandTransition(
      animation: animation,
      motion: motion,
      child: child,
    ),
    null => Theme.of(context).pageTransitionsTheme.buildTransitions(
      this,
      context,
      animation,
      secondaryAnimation,
      child,
    ),
  };
}
