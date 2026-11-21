import 'package:flutter/material.dart';

import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// Where the player will go, empty for now: the mascot watching from the
/// top of an empty screen, and one short line the child need not read to
/// do anything. While [alerted] (a warning shows above it) the mascot
/// raises its crest, and lowers it again once the warning has gone.
class EmptyShelf extends StatelessWidget {
  const EmptyShelf({super.key, this.scale = 1, this.alerted = false});

  /// Grows the drawing with the child home's avatar on wide screens.
  final double scale;

  final bool alerted;

  static const line = 'Logo tem vídeo aqui';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Grown, the line takes two type steps up (the title's size and
    // leading) in the body's voice, so the shelf scales as one.
    final step = scale > 1 ? text.titleLarge : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShelfPicture(
          look: alerted ? TeviLook.crestUp : TeviLook.watching,
          scale: scale,
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

/// What the mascot stands on in a [ShelfPicture].
enum Perch {
  /// The top edge of a screen, hollow as a free module is, or holding a
  /// picture.
  screen,

  /// A single line across the screen's width, sagging a little, like a
  /// wire: the screen is gone, and the day with it.
  wire,
}

/// The picture every child state shows in the shelf's place: the mascot
/// in [look], perched at the start side of a screen or a wire, as it
/// stands on the guardian's field. Its legs land a little into the line,
/// and every look, the raised crest too, stays inside the picture. The
/// figure takes its colours from the ground it stands on (the night's
/// on the darkest), where a wire is drawn in ink, a thin line in the
/// dark; the marks of sleep are drawn in sky so they show.
class ShelfPicture extends StatelessWidget {
  const ShelfPicture({
    super.key,
    required this.look,
    this.perch = Perch.screen,
    this.scale = 1,
    this.blinks = true,
    this.arrivesFrom,
    this.fallsAsleep = false,
  });

  final TeviLook look;
  final Perch perch;

  /// As [Tevi.fallsAsleep].
  final bool fallsAsleep;

  /// As [Tevi.arrivesFrom].
  final TeviLook? arrivesFrom;

  /// Whether the mascot blinks once as its screen arrives: not where the
  /// picture answers a problem rather than a place.
  final bool blinks;

  /// The whole picture's scale: [size] at 1.
  final double scale;

  static const size = Size(192, 165);

  /// The screen, in the picture's own units: the room above it is the
  /// mascot's.
  static const screen = Rect.fromLTWH(9, 66, 174, 99);

  /// The width of the line the screen or the wire is drawn with.
  static const stroke = 4.5;

  /// The mascot's box: as large as lets the raised crest's tips reach the
  /// picture's top while its legs land on the screen.
  static const figure =
      (66 + TeviPainter.perchOverlap) / (TeviPainter.perchY - TeviPainter.top);

  /// The wire's ends and how far its middle sags below them.
  static const _wireEnds = 114.0;
  static const _wireSag = 3.0;

  /// The figure's feet, midway between its legs, as a fraction of its box.
  static const _feet = (53 + 6) / 132;

  /// The wire's centreline at [x], both in the picture's own units: it
  /// runs across the screen's middle, from its start to its end.
  static double wireAt(double x) {
    final t = (x - screen.left) / screen.width;
    return _wireEnds + 4 * _wireSag * t * (1 - t);
  }

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final side = figure * s;
    final start =
        (screen.left + TeviPainter.perchInset) * s -
        side * TeviPainter.body.left;
    // The wire is even end to end, so the stand is the same mirrored.
    final stand = switch (perch) {
      Perch.screen => screen.top,
      Perch.wire => wireAt((start + side * _feet) / s) - stroke / 2,
    };
    final top =
        (stand + TeviPainter.perchOverlap) * s - side * TeviPainter.perchY;
    final night = TeviGround.nightAt(context);
    final line = night && perch == Perch.wire
        ? BrandColors.ink
        : context.palette.onField;
    return ExcludeSemantics(
      child: SizedBox.fromSize(
        size: size * s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PerchPainter(perch: perch, color: line),
              ),
            ),
            // The figure paints after what it stands on, so its legs show
            // over the line. It faces the content: mirrored right to left.
            PositionedDirectional(
              start: start,
              top: top,
              width: side,
              height: side,
              child: FacingTevi(
                size: side,
                look: look,
                night: night,
                markColor: BrandColors.sky,
                blinks: blinks,
                arrivesFrom: arrivesFrom,
                fallsAsleep: fallsAsleep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hollow screen, stroked inside its outline, or the wire.
class _PerchPainter extends CustomPainter {
  const _PerchPainter({required this.perch, required this.color});

  final Perch perch;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const screen = ShelfPicture.screen;
    final s = size.width / ShelfPicture.size.width;
    final stroke = ShelfPicture.stroke * s;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    switch (perch) {
      case Perch.screen:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              screen.left * s,
              screen.top * s,
              screen.right * s,
              screen.bottom * s,
            ).deflate(stroke / 2),
            Radius.circular(
              (screen.height * Radii.screenRatio - ShelfPicture.stroke / 2) * s,
            ),
          ),
          line,
        );
      case Perch.wire:
        final ends = ShelfPicture.wireAt(screen.left);
        // The quadratic's control point lies twice as far below the ends
        // as the centreline's lowest point.
        final control = 2 * ShelfPicture.wireAt(screen.center.dx) - ends;
        canvas.drawPath(
          Path()
            ..moveTo(screen.left * s, ends * s)
            ..quadraticBezierTo(
              screen.center.dx * s,
              control * s,
              screen.right * s,
              ends * s,
            ),
          line..strokeCap = StrokeCap.round,
        );
    }
  }

  @override
  bool shouldRepaint(_PerchPainter old) =>
      old.perch != perch || old.color != color;
}
