import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// The player's glyphs: the universal back, play and pause shapes, cut at
/// the shape ratio's corner.
enum PlayerGlyph { back, play, pause }

/// One of the player's controls, round, [size] across (64 dp at least):
/// the quiet key in ink with its glyph in sky, the filled one a sun disc
/// with a dark glyph, the play disc grown into a key. Read by its one
/// verb; the child finds it by its glyph.
class PlayerKey extends StatefulWidget {
  const PlayerKey({
    super.key,
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.size = KidSizes.target,
  });

  final PlayerGlyph glyph;
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final double size;

  @override
  State<PlayerKey> createState() => _PlayerKeyState();
}

class _PlayerKeyState extends State<PlayerKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fill = widget.filled ? p.action : BrandColors.ink;
    final glyph = widget.filled ? p.onAction : BrandColors.sky;
    final ring =
        (_focused ? focusRing(p).resolve({WidgetState.focused}) : null) ??
        BorderSide.none;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(shape: CircleBorder(side: ring)),
            child: Material(
              color: fill,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onPressed,
                onFocusChange: (f) => setState(() => _focused = f),
                focusColor: Colors.transparent,
                hoverColor: glyph.withValues(alpha: .08),
                highlightColor: glyph.withValues(alpha: .12),
                splashColor: glyph.withValues(alpha: .12),
                child: CustomPaint(
                  // The glyph keeps its share of the key as the key grows.
                  painter: PlayerGlyphPainter(
                    widget.glyph,
                    glyph,
                    side: 28 * widget.size / KidSizes.target,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a [PlayerGlyph] [side] dp square in the canvas's middle: 28 in a
/// key, as the PIN pad's confirm arrow sits.
class PlayerGlyphPainter extends CustomPainter {
  const PlayerGlyphPainter(this.glyph, this.color, {this.side = 28});

  final PlayerGlyph glyph;
  final Color color;
  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final box = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    switch (glyph) {
      case PlayerGlyph.pause:
        // Two bars, each a tall screen at the shape ratio's corner.
        final w = side * .3;
        for (final left in [
          box.left + side * .12,
          box.right - side * .12 - w,
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, box.top + side * .08, w, side * .84),
              Radius.circular(w * Radii.screenRatio * 1.4),
            ),
            paint,
          );
        }
      case PlayerGlyph.play:
        // The triangle, its corners softened by the same ratio.
        final r = side * Radii.screenRatio * .35;
        final a = Offset(box.left + side * .2, box.top + side * .08);
        final b = Offset(box.right - side * .04, box.center.dy);
        final c = Offset(box.left + side * .2, box.bottom - side * .08);
        canvas.drawPath(_rounded([a, b, c], r), paint);
      case PlayerGlyph.back:
        // An arrow leaving to the start: a stem and a head, flat cuts.
        final stroke = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = side * .14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final tip = Offset(box.left + side * .16, box.center.dy);
        canvas.drawLine(
          tip,
          Offset(box.right - side * .14, box.center.dy),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx + side * .3, box.top + side * .2)
            ..lineTo(tip.dx, box.center.dy)
            ..lineTo(tip.dx + side * .3, box.bottom - side * .2),
          stroke,
        );
    }
  }

  /// A polygon whose corners are rounded by [r].
  static Path _rounded(List<Offset> points, double r) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final prev = points[(i - 1 + points.length) % points.length];
      final at = points[i];
      final next = points[(i + 1) % points.length];
      final into = at + (prev - at) / (prev - at).distance * r;
      final out = at + (next - at) / (next - at).distance * r;
      if (i == 0) {
        path.moveTo(into.dx, into.dy);
      } else {
        path.lineTo(into.dx, into.dy);
      }
      path.quadraticBezierTo(at.dx, at.dy, out.dx, out.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(PlayerGlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.side != side;
}
