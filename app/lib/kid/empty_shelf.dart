import 'package:flutter/material.dart';

import '../design/espiadinha.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// Where the player will go, empty for now: the
/// Espiadinha peeking into an empty screen, and one short line the child
/// need not read to do anything.
class EmptyShelf extends StatelessWidget {
  const EmptyShelf({super.key, this.scale = 1});

  /// Grows the drawing with the child home's avatar on wide screens.
  final double scale;

  static const line = 'Logo tem vídeo aqui';

  /// The mark's 64 units wide, from the head's top to the screen's foot
  /// (55 units), at 3 dp a unit.
  static const size = Size(192, 165);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Grown, the line takes two type steps up (the title's size and
    // leading) in the body's voice, so the shelf scales as one.
    final step = scale > 1 ? text.titleLarge : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: CustomPaint(
            size: size * scale,
            painter: const EmptyShelfPainter(),
          ),
        ),
        const SizedBox(height: Space.lg),
        Text(
          line,
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(
            color: context.palette.muted,
            fontSize: step?.fontSize,
            height: step?.height,
          ),
        ),
      ],
    );
  }
}

/// The Espiadinha on the kid ground (head and fingers in sun, standing
/// alone, eyes in dark looking down) over its screen, hollow as a free
/// module is: a cream outline with nothing inside. Sun stays the head's
/// and the fingers'.
class EmptyShelfPainter extends CustomPainter {
  const EmptyShelfPainter({this.asleep = false, this.waving = false});

  /// Its eyes closed: the sleeping telinha.
  final bool asleep;

  /// Its hands up: a pacotinho's goodbye.
  final bool waving;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / EspiadinhaPainter.width;
    canvas.save();
    EspiadinhaPainter(
      palette: Palette.kid,
      asleep: asleep,
      waving: waving,
    ).paint(canvas, Size(size.width, EspiadinhaPainter.height * u));
    canvas.restore();
    // The screen: 58 × 33 at its 10-unit corner, its top edge where the
    // fingers grip, the stroke kept inside its outline.
    const stroke = 1.5;
    canvas.save();
    canvas.scale(u);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(
          3 + stroke / 2,
          EspiadinhaPainter.height + stroke / 2,
          58 - stroke,
          33 - stroke,
        ),
        const Radius.circular(10 - stroke / 2),
      ),
      Paint()
        ..color = BrandColors.cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(EmptyShelfPainter old) =>
      old.asleep != asleep || old.waving != waving;
}
