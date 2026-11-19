import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';
import 'kid_layout.dart';

/// Where a door on the home stood when it was tapped, how to find it
/// again, and a picture of what it showed: what a page needs to grow out
/// of it and to shrink back onto it.
class DoorPlace {
  const DoorPlace(this.rect, {this.measure, this.face});

  /// Where the door stood on the screen when it was tapped.
  final Rect rect;

  /// Where the door stands now, if it still stands: the home may have
  /// read its catalogue again, or the screen turned, while the page was
  /// open.
  final Rect? Function()? measure;

  /// The door's glyph and covers as they were painted, without its
  /// ground.
  final ui.Image? face;

  /// Where the door stands now, else where it stood.
  Rect get now => measure?.call() ?? rect;
}

/// A page opening from the home's door: the door's ground grows from
/// where the door stood until it is the whole screen, the door's own
/// glyph and covers carried on it toward the page's large picture, and
/// the page shows on it as they fade; going back, it shrinks onto the
/// door where it stands then, so the child sees it is the same place.
/// Under reduced motion it is a cut; at rest it leaves [child] untouched.
class RoomTransition extends AnimatedWidget {
  const RoomTransition({
    super.key,
    required Animation<double> animation,
    required this.from,
    required this.ground,
    required this.child,
  }) : super(listenable: animation);

  static const duration = Duration(milliseconds: 300);

  /// The door the page opened from, if it opened from one.
  final DoorPlace? from;
  final Color ground;
  final Widget child;

  /// The page shows once the ground has grown past the door.
  static const _show = Interval(.3, 1);

  /// The door's picture fades as the page shows.
  static const _fade = Interval(.35, .85);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final from = this.from;
    if (from == null ||
        MediaQuery.disableAnimationsOf(context) ||
        animation.isCompleted) {
      return child;
    }
    final screen = MediaQuery.sizeOf(context);
    final v = animation.value;
    final t = Easing.standard.transform(v);
    final face = from.face;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipPath(
          clipper: RoomClipper(door: () => from.now, screen: screen, t: t),
          child: ColoredBox(
            color: ground,
            child: Opacity(opacity: _show.transform(v), child: child),
          ),
        ),
        if (face != null)
          IgnorePointer(
            child: CustomPaint(
              painter: RoomFacePainter(
                face: face,
                door: () => from.now,
                target: _target(context, screen),
                t: t,
                opacity: 1 - _fade.transform(v),
              ),
            ),
          ),
      ],
    );
  }

  /// Where the door's picture travels: toward the page's large picture,
  /// at the content's edge below the strip.
  static Rect _target(BuildContext context, Size screen) {
    final edge = KidLayout.edge(screen.width);
    final wide = screen.width >= FieldSizes.wideBreakpoint;
    final room = screen.width - 2 * edge;
    final width = wide ? room / 2 : room;
    final top = MediaQuery.paddingOf(context).top + KidLayout.stripHeight;
    return Rect.fromLTWH(edge, top, width, width * 9 / 16);
  }
}

/// Clips the page to the ground growing from the door, measured as it is
/// painted, so the door's place is where it stands at that moment.
class RoomClipper extends CustomClipper<Path> {
  const RoomClipper({
    required this.door,
    required this.screen,
    required this.t,
  });

  final Rect Function() door;
  final Size screen;
  final double t;

  RRect get rrect => RRect.lerp(
    RRect.fromRectAndRadius(door(), const Radius.circular(Radii.card)),
    RRect.fromRectAndRadius(Offset.zero & screen, Radius.zero),
    t,
  )!;

  @override
  Path getClip(Size size) => Path()..addRRect(rrect);

  // The door may have moved since the last frame.
  @override
  bool shouldReclip(RoomClipper old) => true;
}

/// Paints the door's picture on the growing ground: from the door's
/// place toward [target], keeping its proportions, at [opacity].
class RoomFacePainter extends CustomPainter {
  const RoomFacePainter({
    required this.face,
    required this.door,
    required this.target,
    required this.t,
    required this.opacity,
  });

  final ui.Image face;
  final Rect Function() door;
  final Rect target;
  final double t;
  final double opacity;

  /// Where the picture stands at [t].
  Rect get rect {
    final from = door();
    final to = Rect.fromLTWH(
      target.left,
      target.top,
      target.width,
      target.width * from.height / from.width,
    );
    return Rect.lerp(from, to, t)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    canvas.drawImageRect(
      face,
      Offset.zero & Size(face.width + .0, face.height + .0),
      rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }

  @override
  bool shouldRepaint(RoomFacePainter old) => true;
}

/// Marks what a door shows above its ground (its glyph, its covers), so
/// the door can be pictured as it was when tapped.
class DoorFace extends SingleChildRenderObjectWidget {
  const DoorFace({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDoorFace();
}

class _RenderDoorFace extends RenderRepaintBoundary {}

/// The picture of the door face under [context], as last painted; null
/// where there is none or it cannot be taken now.
ui.Image? faceOf(BuildContext context) {
  _RenderDoorFace? found;
  void visit(RenderObject o) {
    if (found != null) return;
    if (o is _RenderDoorFace) {
      found = o;
      return;
    }
    o.visitChildren(visit);
  }

  final root = context.findRenderObject();
  if (root == null) return null;
  visit(root);
  final face = found;
  if (face == null || !face.hasSize) return null;
  try {
    return face.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
  } on Object {
    // A picture is a nicety: without it the ground still grows.
    return null;
  }
}

/// The go_router page of a page opened from the home's door [from]
/// (popping it plays the reverse).
CustomTransitionPage<T> roomPage<T>({
  LocalKey? key,
  required DoorPlace? from,
  required Color ground,
  required Widget child,
}) => CustomTransitionPage<T>(
  key: key,
  transitionDuration: RoomTransition.duration,
  reverseTransitionDuration: RoomTransition.duration,
  child: child,
  transitionsBuilder: (context, animation, _, child) => RoomTransition(
    animation: animation,
    from: from,
    ground: ground,
    child: child,
  ),
);
