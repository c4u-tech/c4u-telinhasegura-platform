import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The Espiadinha's head and fingers, drawn from the mark's 64-unit
/// geometry above the edge of the
/// ink field, which is its screen. The strip spans mark y 5 (head top) to
/// y 27 (screen top): 64 × 22 units.
///
/// "O sol sobe": [rise] runs 0 → 1. The fingers grip the edge first, then
/// the head rises from behind it, and the eyes open last, looking down
/// into the screen, never out at the viewer.
class EspiadinhaPainter extends CustomPainter {
  EspiadinhaPainter({
    required this.palette,
    this.rise = 1,
    this.asleep = false,
    this.waving = false,
  });

  final Palette palette;
  final double rise;

  /// Both hands lifted off the edge beside the head, fingers fanned: the
  /// goodbye at a pacotinho's end. The
  /// eyes stay open, so it never reads as the sleeping telinha.
  final bool waving;

  /// Eyes closed, two arcs: the child's day is over (the sleeping
  /// telinha).
  final bool asleep;

  static const width = 64.0;
  static const height = 22.0;
  static const _top = 5.0;
  static const _cut = 24.5;

  static double _phase(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  static double _easeOut(double t) =>
      t >= 1 ? 1 : 1 - math.pow(2, -10 * t).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / width;
    canvas.scale(u);
    canvas.translate(0, -_top);
    // Nothing shows below the cut: the head rises from behind the edge.
    canvas.clipRect(const Rect.fromLTRB(0, 0, width, _cut));

    final light = palette.brightness == Brightness.light;
    final sun = Paint()..color = BrandColors.sun;
    Paint stroke(double w) => Paint()
      ..color = palette.headOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round;

    final fingers = _easeOut(_phase(rise, 0, 0.35));
    final head = _easeOut(_phase(rise, 0.2, 0.9));
    final eyes = _phase(rise, 0.75, 1);

    // Fingers: radius 2.15, centres 1.1 above the cut (the mark SVG's
    // large-arc segments), so a little more than half of each shows.
    final lift = Offset(0, (1 - fingers) * 5);
    if (waving) {
      final hands = _hands().shift(lift);
      canvas.drawPath(hands, sun);
      if (light) canvas.drawPath(hands, stroke(1.5));
    } else {
      for (final centre in _gripAt) {
        final path = _cutCircle(centre, 2.15).shift(lift);
        canvas.drawPath(path, sun);
        if (light) canvas.drawPath(path, stroke(1.5));
      }
    }

    // Head: radius 14 centred at (32, 19), cut flat at 24.5.
    final drop = (1 - head) * (_cut - _top + 2);
    final headPath = _cutCircle(
      const Offset(32, 19),
      14,
    ).shift(Offset(0, drop));
    canvas.drawPath(headPath, sun);
    if (light) canvas.drawPath(headPath, stroke(2.4));

    if (eyes > 0) {
      final eye = Paint()
        ..color = (light ? palette.headOutline : BrandColors.dark).withValues(
          alpha: eyes,
        );
      if (asleep) {
        // Closed: each eye's lower rim as one arc, its lid shut over it,
        // still turned down into the screen.
        eye
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        for (final x in [26.5, 37.5]) {
          canvas.drawPath(
            Path()..addArc(
              Rect.fromCenter(
                center: Offset(x, 16.6 + drop),
                width: 5.2,
                height: 3.6,
              ),
              0,
              math.pi,
            ),
            eye,
          );
        }
        return;
      }
      for (final x in [26.5, 37.5]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, 17 + drop),
            width: 5.2,
            height: 6.4,
          ),
          eye,
        );
      }
    }
  }

  static const _gripX = [9.6, 13.4, 17.2, 46.8, 50.6, 54.4];
  static final _gripAt = [for (final x in _gripX) Offset(x, _cut - 1.1)];

  /// Both hands raised clear of the head to say goodbye, mirrored: a
  /// palm disc and three rounded fingers fanned out from it, leaning away
  /// from the head, with ground between their tips so each hand reads as
  /// a hand and not as a paw's separate toes.
  static Path _hands() {
    var hands = Path();
    for (final (palm, lean) in [
      (const Offset(10, 18.5), -1.0),
      (const Offset(54, 18.5), 1.0),
    ]) {
      hands = Path.combine(
        PathOperation.union,
        hands,
        Path()..addOval(Rect.fromCircle(center: palm, radius: 3.4)),
      );
      for (final step in [-1, 0, 1]) {
        final a = (lean * 18 + step * 32) * math.pi / 180;
        final tip = palm + Offset(7 * math.sin(a), -7 * math.cos(a));
        hands = Path.combine(
          PathOperation.union,
          hands,
          _capsule(palm, tip, 1.6),
        );
      }
    }
    return hands;
  }

  /// A finger: a round-ended bar of half-width [r] from [a] to [b].
  static Path _capsule(Offset a, Offset b, double r) {
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / d.distance * r;
    final turn = math.atan2(d.dy, d.dx);
    return Path()
      ..moveTo((a + n).dx, (a + n).dy)
      ..lineTo((b + n).dx, (b + n).dy)
      ..arcTo(
        Rect.fromCircle(center: b, radius: r),
        turn + math.pi / 2,
        -math.pi,
        false,
      )
      ..lineTo((a - n).dx, (a - n).dy)
      ..arcTo(
        Rect.fromCircle(center: a, radius: r),
        turn - math.pi / 2,
        -math.pi,
        false,
      )
      ..close();
  }

  /// A circle cut flat by the horizontal line y = [_cut].
  static Path _cutCircle(Offset c, double r) {
    final dy = _cut - c.dy;
    if (dy >= r) {
      return Path()..addOval(Rect.fromCircle(center: c, radius: r));
    }
    // The cut meets the circle at angles a and π − a (y grows downward);
    // the visible arc runs clockwise from π − a over the top to 2π + a.
    final a = math.asin(dy / r);
    return Path()
      ..addArc(
        Rect.fromCircle(center: c, radius: r),
        math.pi - a,
        math.pi + 2 * a,
      )
      ..close();
  }

  @override
  bool shouldRepaint(EspiadinhaPainter old) =>
      old.rise != rise ||
      old.palette != palette ||
      old.asleep != asleep ||
      old.waving != waving;
}

/// The simplified mark on ink (`telinha-segura-mark-simplified-color-on-
/// dark.svg`): a cream screen and the head standing alone, no fingers, no
/// outline, eyes in dark. The child side's only brand sign;
/// drawn on the mark's 64-unit grid.
class SimplifiedMarkPainter extends CustomPainter {
  const SimplifiedMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 27, 58, 33),
        const Radius.circular(10),
      ),
      Paint()..color = BrandColors.cream,
    );
    canvas.drawPath(
      EspiadinhaPainter._cutCircle(const Offset(32, 19), 14),
      Paint()..color = BrandColors.sun,
    );
    final eye = Paint()..color = BrandColors.dark;
    for (final x in [26.5, 37.5]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 17), width: 5.2, height: 6.4),
        eye,
      );
    }
  }

  @override
  bool shouldRepaint(SimplifiedMarkPainter old) => false;
}
