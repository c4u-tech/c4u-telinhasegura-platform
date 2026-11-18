import 'package:flutter/material.dart';

import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// Where the player will go, empty for now: the mascot watching from the
/// top of an empty screen, and one short line the child need not read to
/// do anything.
class EmptyShelf extends StatelessWidget {
  const EmptyShelf({super.key, this.scale = 1});

  /// Grows the drawing with the child home's avatar on wide screens.
  final double scale;

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
        ShelfPicture(look: TeviLook.watching, scale: scale),
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
    this.across = false,
  });

  final TeviLook look;
  final Perch perch;

  /// The wire runs across the whole screen, edge to edge, rather than
  /// only across the picture: the day's end takes the screen, a note
  /// keeps to its own place. The mascot stands where it would on the
  /// short wire.
  final bool across;

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
            if (perch == Perch.wire && across)
              Positioned.fill(
                child: ScreenWire(
                  feet: start + side * _feet,
                  centre: wireAt((start + side * _feet) / s) * s,
                  stroke: stroke * s,
                  color: line,
                ),
              )
            else
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
              child: Transform.flip(
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: Tevi(
                  size: side,
                  look: look,
                  night: night,
                  markColor: BrandColors.sky,
                ),
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

/// A wire across the whole screen, edge to edge, sagging gently at the
/// screen's middle and passing through [centre] (the wire's centreline,
/// down from this box's top) at [feet] (across from its start), where
/// the mascot stands. It is laid out in its picture's box and paints
/// past it, measuring where that box lies on the screen.
class ScreenWire extends LeafRenderObjectWidget {
  const ScreenWire({
    super.key,
    required this.feet,
    required this.centre,
    required this.stroke,
    required this.color,
  });

  final double feet;
  final double centre;
  final double stroke;
  final Color color;

  /// How far the middle sags, for every unit of the wire's length: the
  /// picture's own short wire's.
  static final sag = ShelfPicture._wireSag / ShelfPicture.screen.width;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScreenWire(
    this,
    MediaQuery.sizeOf(context).width,
    Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderScreenWire)
        ..wire = this
        ..screen = MediaQuery.sizeOf(context).width
        ..direction = Directionality.of(context);
}

class _RenderScreenWire extends RenderBox {
  _RenderScreenWire(this._wire, this._screen, this._direction);

  ScreenWire _wire;
  set wire(ScreenWire v) {
    if (v.feet == _wire.feet &&
        v.centre == _wire.centre &&
        v.stroke == _wire.stroke &&
        v.color == _wire.color) {
      return;
    }
    _wire = v;
    markNeedsPaint();
  }

  /// The screen's width.
  double _screen;
  set screen(double v) {
    if (v == _screen) return;
    _screen = v;
    markNeedsPaint();
  }

  TextDirection _direction;
  set direction(TextDirection v) {
    if (v == _direction) return;
    _direction = v;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Where this box starts on the screen: the wire runs from the
    // screen's left edge to its right, whatever the box's place.
    final left = -localToGlobal(Offset.zero).dx;
    final width = _screen;
    final wire = _wire;
    final feet = _direction == TextDirection.rtl
        ? size.width - wire.feet
        : wire.feet;
    // The centreline is a parabola over the screen's width, lowest at
    // its middle, lifted so it passes under the mascot's feet.
    final sag = width * ScreenWire.sag;
    double drop(double x) {
      final t = (x - left) / width;
      return 4 * sag * t * (1 - t);
    }

    final ends = wire.centre - drop(feet);
    // The quadratic's control point lies twice as far below the ends as
    // the centreline's lowest point.
    final control = ends + 2 * sag;
    context.canvas.drawPath(
      Path()
        ..moveTo(offset.dx + left, offset.dy + ends)
        ..quadraticBezierTo(
          offset.dx + left + width / 2,
          offset.dy + control,
          offset.dx + left + width,
          offset.dy + ends,
        ),
      Paint()
        ..color = wire.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = wire.stroke,
    );
  }
}
