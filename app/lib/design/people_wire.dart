import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tevi.dart';
import 'theme.dart';

/// The people who approved something, as birds perched on a gently
/// sagging wire: one bird per person, [drawnAtMost] at most, and the rest
/// as "+N" beside them. The birds are the mascot's one-colour silhouette
/// in the text colour, so they count people rather than add mascots.
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
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = PeopleWirePainter(birds: birds, color: color);
            final width = constraints.maxWidth;
            final after = painter.birdsWidth + PeopleWirePainter.pitch * .15;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: CustomPaint(painter: painter)),
                if (rest > 0)
                  Positioned(
                    left: after,
                    // On the wire, beside the last bird's body.
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
/// start side, each standing where its feet would meet the wire.
class PeopleWirePainter extends CustomPainter {
  const PeopleWirePainter({required this.birds, required this.color});

  final int birds;
  final Color color;

  /// The silhouette's scale from its 120 units.
  static const _scale = .3;

  /// From one bird to the next: the figure's width and a little air.
  static const pitch = 34.0;

  /// The wire's height at its ends, and how far it sags in the middle.
  static const _ends = 32.0;
  static const _sag = 4.0;

  static const stroke = 2.0;

  /// The silhouette's left edge (the body's side), in its units.
  static const _left = 14.0;

  /// The middle of the body's foot, which sits on the wire's centreline:
  /// without legs, a bird set higher would hover over it.
  static const _foot = Offset(53, 90);

  /// Where bird [i]'s figure box starts across.
  double _originX(int i) => i * pitch - _left * _scale;

  /// Where bird [i] stands across: midway under its body.
  double footAt(int i) => _originX(i) + _foot.dx * _scale;

  /// Where bird [i]'s figure box starts down, across [width].
  double _top(int i, double width) =>
      wireAt(footAt(i), width) - _foot.dy * _scale;

  /// The foot of bird [i]'s body, across [width].
  double bodyBottom(int i, double width) => _top(i, width) + 90 * _scale;

  /// The drawn height of one bird, crown to body's foot.
  double get birdHeight => (90 - 20) * _scale;

  /// How far the birds run from the start side.
  double get birdsWidth =>
      birds == 0 ? 0 : (birds - 1) * pitch + (115.03 - _left) * _scale;

  /// The wire's centreline at [x] across [width]: a quadratic whose
  /// control point sits twice the sag below the ends, mid-width.
  static double wireAt(double x, double width) {
    final t = width <= 0 ? 0.0 : (x / width).clamp(0.0, 1.0);
    return _ends + 2 * t * (1 - t) * (2 * _sag);
  }

  @override
  void paint(Canvas canvas, Size size) {
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
      old.birds != birds || old.color != color;
}
