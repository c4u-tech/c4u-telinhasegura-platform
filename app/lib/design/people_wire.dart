import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tevi.dart';
import 'theme.dart';

/// The people who approved something, as birds standing on a gently
/// sagging wire: one bird per person, [drawnAtMost] at most, and the rest
/// as "+N" beside them. The birds are the mascot's one-colour silhouette
/// in the text colour, so they count people rather than add mascots. The
/// row starts a little in from the reading direction's start, so the wire
/// shows on both sides of it.
///
/// It is decoration: the words beside it say the same count, so nothing
/// of it reaches the screen reader.
class PeopleWire extends StatelessWidget {
  const PeopleWire({super.key, required this.people});

  /// How many approved it.
  final int people;

  static const drawnAtMost = 5;

  static const height = 40.0;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.text;
    final birds = math.min(people, drawnAtMost);
    final rest = people - birds;
    final direction = Directionality.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = PeopleWirePainter(
              birds: birds,
              color: color,
              textDirection: direction,
            );
            final width = constraints.maxWidth;
            final after =
                PeopleWirePainter.inset +
                painter.birdsWidth +
                PeopleWirePainter.pitch * .15;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: CustomPaint(painter: painter)),
                if (rest > 0)
                  PositionedDirectional(
                    start: after,
                    // On the wire, beside the last bird's body. The wire
                    // sags evenly, so its height is the same from either end.
                    bottom:
                        height -
                        PeopleWirePainter.wireAt(after, width) +
                        PeopleWirePainter.stroke * 2,
                    child: Text(
                      '+$rest',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Draws the wire across its whole width and [birds] birds on it from the
/// start side of [textDirection], each standing on it by its feet. Right
/// to left the drawing is mirrored, so the birds face the way the row runs.
class PeopleWirePainter extends CustomPainter {
  const PeopleWirePainter({
    required this.birds,
    required this.color,
    this.textDirection = TextDirection.ltr,
  });

  final int birds;
  final Color color;
  final TextDirection textDirection;

  /// The silhouette's scale from its 120 units: the body about 21 dp tall.
  static const _scale = .3;

  /// From one bird to the next: the figure's width, tail to beak, and a
  /// little air.
  static const pitch = 36.0;

  /// How far the first bird's tail starts in from the wire's end.
  static const inset = 12.0;

  /// The wire's height at its ends, and how far it sags in the middle.
  static const _ends = 32.0;
  static const _sag = 4.0;

  static const stroke = 2.0;

  /// The silhouette's start, the tail's tip, and its end, the beak's tip,
  /// in its units.
  static const _tailTip = 3.70;
  static const _beakTip = 115.03;

  /// Where the body's top and foot are, in its units.
  static const _crown = 20.0;
  static const _bodyFoot = 90.0;

  /// Midway between the ends of the two legs: the point that stands on the
  /// wire's centreline.
  static const _feet = Offset(53, 103.4);

  /// Where bird [i]'s figure box starts across, from the start side.
  double _originX(int i) => inset + i * pitch - _tailTip * _scale;

  /// Where bird [i]'s drawing starts across, at its tail's tip.
  double inkStart(int i) => _originX(i) + _tailTip * _scale;

  /// Where bird [i] stands across: midway between its feet.
  double footAt(int i) => _originX(i) + _feet.dx * _scale;

  /// Where bird [i]'s figure box starts down, across [width].
  double _top(int i, double width) =>
      wireAt(footAt(i), width) - _feet.dy * _scale;

  /// The ends of bird [i]'s legs, across [width].
  double feetAt(int i, double width) => _top(i, width) + _feet.dy * _scale;

  /// The foot of bird [i]'s body, across [width].
  double bodyBottom(int i, double width) => _top(i, width) + _bodyFoot * _scale;

  /// The drawn height of one bird, crown to the legs' ends.
  double get birdHeight => (_feet.dy - _crown) * _scale;

  /// How far the birds run, from the first tail to the last beak.
  double get birdsWidth =>
      birds == 0 ? 0 : (birds - 1) * pitch + (_beakTip - _tailTip) * _scale;

  /// The wire's centreline at [x] across [width]: a quadratic whose
  /// control point sits twice the sag below the ends, mid-width. It is the
  /// same measured from either end.
  static double wireAt(double x, double width) {
    final t = width <= 0 ? 0.0 : (x / width).clamp(0.0, 1.0);
    return _ends + 2 * t * (1 - t) * (2 * _sag);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (textDirection == TextDirection.rtl) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final paint = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(0, _ends)
        ..quadraticBezierTo(
          size.width / 2,
          _ends + 2 * _sag,
          size.width,
          _ends,
        ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < birds; i++) {
      canvas.save();
      canvas.translate(_originX(i), _top(i, size.width));
      canvas.scale(_scale);
      canvas.drawPath(TeviPainter.oneColour, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PeopleWirePainter old) =>
      old.birds != birds ||
      old.color != color ||
      old.textDirection != textDirection;
}
