import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'family.dart';
import 'labels.dart';

/// The only colours the avatars paint. Each avatar is a small ink field
/// (the same in both themes, like the field itself) with a cream figure,
/// dark details and one ink-tinted neutral. Sun stays the Espiadinha's.
abstract final class AvatarColors {
  static const ground = BrandColors.ink;
  static const figure = BrandColors.cream;
  static const detail = BrandColors.dark;

  /// Night Muted: light enough to read on ink, dark enough to read
  /// against cream.
  static final mist = Palette.dark.muted;

  static final all = {ground, figure, detail, mist};
}

/// A preset avatar: the animal drawn on a disc, labelled with its name.
/// Set [excludeSemantics] where the avatar repeats a label already read,
/// such as beside the child's nickname. On the kid ground, ink like the
/// disc, the disc keeps its edge with the dialect's outline tone.
class AvatarDisc extends StatelessWidget {
  const AvatarDisc(
    this.avatar, {
    super.key,
    this.size = 40,
    this.excludeSemantics = false,
  });

  final Avatar avatar;
  final double size;
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onInk = p.ground == AvatarColors.ground;
    final art = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: AvatarPainter(avatar, boundary: onInk ? p.outline : null),
      ),
    );
    if (excludeSemantics) return ExcludeSemantics(child: art);
    return Semantics(image: true, label: avatar.label, child: art);
  }
}

/// The twelve animals, cut from the Espiadinha's vocabulary (discs, the
/// 58 × 33 screen with its 10/33 corner, flat cuts) on a 64-unit grid,
/// flat: no gradients, no shadows. Each reads by silhouette alone.
class AvatarPainter extends CustomPainter {
  AvatarPainter(this.avatar, {this.boundary});

  final Avatar avatar;

  /// A 2 px circle on the disc's edge, drawn over the art, where the
  /// ground is the disc's own ink: the avatar's colours stay as they are.
  final Color? boundary;

  /// The boundary's width on screen.
  static const boundaryWidth = 2.0;

  static const grid = 64.0;

  static final _ground = Paint()..color = AvatarColors.ground;
  static final _figure = Paint()..color = AvatarColors.figure;
  static final _detail = Paint()..color = AvatarColors.detail;
  static final _mist = Paint()..color = AvatarColors.mist;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / grid;
    canvas.scale(scale);
    final disc = Path()
      ..addOval(Rect.fromCircle(center: const Offset(32, 32), radius: 32));
    canvas.clipPath(disc);
    canvas.drawPath(disc, _ground);
    // With the boundary, the animal stays clear inside it, a ring's width
    // of ink between them: an ear cut flush at the ring would read as
    // crossing it, the more the larger the disc.
    final width = boundaryWidth / scale;
    if (boundary != null) {
      canvas.save();
      canvas.clipPath(
        Path()..addOval(
          Rect.fromCircle(center: const Offset(32, 32), radius: 32 - 2 * width),
        ),
      );
    }
    switch (avatar) {
      case Avatar.fox:
        _fox(canvas);
      case Avatar.owl:
        _owl(canvas);
      case Avatar.cat:
        _cat(canvas);
      case Avatar.dog:
        _dog(canvas);
      case Avatar.rabbit:
        _rabbit(canvas);
      case Avatar.bear:
        _bear(canvas);
      case Avatar.turtle:
        _turtle(canvas);
      case Avatar.whale:
        _whale(canvas);
      case Avatar.lion:
        _lion(canvas);
      case Avatar.panda:
        _panda(canvas);
      case Avatar.frog:
        _frog(canvas);
      case Avatar.penguin:
        _penguin(canvas);
      case Avatar.unknown:
        _placeholder(canvas);
    }
    if (boundary case final color?) {
      canvas.restore();
      canvas.drawCircle(
        const Offset(32, 32),
        32 - width / 2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }
  }

  static void _disc(Canvas c, double x, double y, double r, Paint p) =>
      c.drawCircle(Offset(x, y), r, p);

  static void _oval(
    Canvas c,
    double x,
    double y,
    double w,
    double h,
    Paint p, {
    double turn = 0,
  }) {
    c.save();
    c.translate(x, y);
    c.rotate(turn * math.pi / 180);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: w, height: h), p);
    c.restore();
  }

  static void _poly(Canvas c, List<Offset> points, Paint p) =>
      c.drawPath(Path()..addPolygon(points, true), p);

  /// The mark's screen: a rounded rectangle with a 10/33 corner.
  static void _screen(Canvas c, Rect r, Paint p) => c.drawRRect(
    RRect.fromRectAndRadius(r, Radius.circular(r.height * Radii.screenRatio)),
    p,
  );

  /// The same shape mirrored across the disc's vertical axis.
  static List<Offset> _mirror(List<Offset> points) => [
    for (final o in points) Offset(grid - o.dx, o.dy),
  ];

  static void _pair(Canvas c, List<Offset> points, Paint p) {
    _poly(c, points, p);
    _poly(c, _mirror(points), p);
  }

  static void _eyes(Canvas c, double dx, double y, double w, double h) {
    _oval(c, 32 - dx, y, w, h, _detail);
    _oval(c, 32 + dx, y, w, h, _detail);
  }

  void _fox(Canvas c) {
    // Tall pointed ears with dark backs, a mist head, a cream V of cheeks.
    _pair(c, const [Offset(12, 5), Offset(10, 32), Offset(29, 22)], _mist);
    _pair(c, const [Offset(13, 10), Offset(12.5, 26), Offset(22, 21)], _detail);
    _disc(c, 32, 33, 16, _mist);
    _poly(c, const [
      Offset(14, 30),
      Offset(50, 30),
      Offset(38, 48),
      Offset(32, 56),
      Offset(26, 48),
    ], _mist);
    _poly(c, const [
      Offset(13, 34),
      Offset(25, 37),
      Offset(32, 43),
      Offset(39, 37),
      Offset(51, 34),
      Offset(32, 57),
    ], _figure);
    _eyes(c, 7.5, 31, 4.4, 5.6);
    _disc(c, 32, 52.5, 3, _detail);
  }

  void _owl(Canvas c) {
    // Ear tufts, two big facial discs, a beak: the body is mist.
    _pair(c, const [Offset(12, 6), Offset(13, 28), Offset(27, 19)], _mist);
    _oval(c, 32, 42, 42, 48, _mist);
    _disc(c, 23.5, 31, 9.5, _figure);
    _disc(c, 40.5, 31, 9.5, _figure);
    _disc(c, 23.5, 32, 4.6, _detail);
    _disc(c, 40.5, 32, 4.6, _detail);
    _poly(c, const [
      Offset(28.5, 39),
      Offset(35.5, 39),
      Offset(32, 47),
    ], _detail);
    // Breast feathers: three flat-cut cream scallops.
    for (final x in [24.0, 32.0, 40.0]) {
      c.save();
      c.clipRect(Rect.fromLTRB(x - 4, 50, x + 4, 54));
      _disc(c, x, 50, 4, _figure);
      c.restore();
    }
  }

  void _cat(Canvas c) {
    // Short wide ears, a round face, tall eyes and whiskers.
    _pair(c, const [Offset(13, 9), Offset(12, 34), Offset(29, 23)], _figure);
    _pair(c, const [Offset(15.5, 15), Offset(15, 29), Offset(24, 23.5)], _mist);
    _oval(c, 32, 38, 40, 32, _figure);
    _eyes(c, 7.5, 35, 4.6, 7);
    _poly(c, const [Offset(29, 42), Offset(35, 42), Offset(32, 45.5)], _detail);
    final whisker = Paint()
      ..color = AvatarColors.detail
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in const [
      (Offset(25, 45), Offset(15, 43)),
      (Offset(25, 48), Offset(15.5, 50)),
    ]) {
      c.drawLine(a, b, whisker);
      c.drawLine(Offset(grid - a.dx, a.dy), Offset(grid - b.dx, b.dy), whisker);
    }
  }

  void _dog(Canvas c) {
    // Floppy mist ears, a patch over one eye, a big nose.
    _disc(c, 32, 35, 16, _figure);
    _oval(c, 32, 45, 22, 15, _figure);
    _oval(c, 15, 34, 11, 26, _mist, turn: 18);
    _oval(c, 49, 34, 11, 26, _mist, turn: -18);
    _oval(c, 39.5, 31.5, 11, 12, _mist);
    _disc(c, 25, 32, 2.8, _detail);
    _disc(c, 39.5, 32, 2.8, _detail);
    _oval(c, 32, 42, 10, 7, _detail);
    final mouth = Paint()
      ..color = AvatarColors.detail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    c.drawPath(
      Path()
        ..moveTo(32, 45)
        ..lineTo(32, 48)
        ..moveTo(27, 48)
        ..quadraticBezierTo(32, 52, 37, 48),
      mouth,
    );
  }

  void _rabbit(Canvas c) {
    // Long upright ears are the whole silhouette.
    _oval(c, 24, 19, 10, 32, _figure, turn: -8);
    _oval(c, 40, 19, 10, 32, _figure, turn: 8);
    _oval(c, 24, 20, 4.5, 22, _mist, turn: -8);
    _oval(c, 40, 20, 4.5, 22, _mist, turn: 8);
    _disc(c, 32, 43, 14.5, _figure);
    _eyes(c, 6, 41, 4, 5.2);
    _poly(c, const [
      Offset(29.5, 47),
      Offset(34.5, 47),
      Offset(32, 50),
    ], _detail);
    _screen(c, const Rect.fromLTWH(29.5, 51.5, 5, 4.5), _mist);
  }

  void _bear(Canvas c) {
    // Round ears on top, a mist muzzle.
    _disc(c, 17, 19, 7.5, _figure);
    _disc(c, 47, 19, 7.5, _figure);
    _disc(c, 17, 19, 3.8, _mist);
    _disc(c, 47, 19, 3.8, _mist);
    _disc(c, 32, 36, 17.5, _figure);
    _oval(c, 32, 44, 17, 13, _mist);
    _eyes(c, 7.5, 32, 4.2, 4.8);
    _oval(c, 32, 41, 7.5, 5, _detail);
  }

  void _turtle(Canvas c) {
    // A dome cut flat, shell plates as screens, a head out in front.
    _screen(c, const Rect.fromLTWH(17, 41, 8, 9), _figure);
    _screen(c, const Rect.fromLTWH(37, 41, 8, 9), _figure);
    _poly(c, const [Offset(10, 41), Offset(14, 37), Offset(15, 43)], _figure);
    _oval(c, 51, 37, 15, 12, _figure);
    _disc(c, 53.5, 35.5, 1.9, _detail);
    final dome = Path()
      ..addArc(
        Rect.fromCircle(center: const Offset(30, 42), radius: 19),
        math.pi,
        math.pi,
      )
      ..close();
    c.drawPath(dome, _figure);
    _screen(c, const Rect.fromLTWH(11, 39, 38, 5), _mist);
    _screen(c, const Rect.fromLTWH(23.5, 27, 13, 9), _mist);
    _screen(c, const Rect.fromLTWH(14.5, 31, 7, 6), _mist);
    _screen(c, const Rect.fromLTWH(38.5, 31, 7, 6), _mist);
  }

  void _whale(Canvas c) {
    // A long body, a fluke raised behind, a spout above the head.
    final body = Path()
      ..addOval(
        Rect.fromCenter(center: const Offset(28, 40), width: 42, height: 26),
      );
    _poly(c, const [
      Offset(40, 34),
      Offset(50, 22),
      Offset(55, 23),
      Offset(46, 46),
    ], _figure);
    _oval(c, 47, 20, 15, 8.5, _figure, turn: -30);
    _oval(c, 57.5, 21, 15, 8.5, _figure, turn: 30);
    c.drawPath(body, _figure);
    c.save();
    c.clipPath(body);
    c.drawRect(const Rect.fromLTRB(0, 45, grid, grid), _mist);
    c.restore();
    _disc(c, 18, 37, 2.6, _detail);
    for (final (x, y, r) in const [
      (19.0, 14.5, 2.6),
      (14.0, 10.0, 2.2),
      (24.0, 10.0, 2.2),
      (19.0, 21.0, 2.2),
    ]) {
      _disc(c, x, y, r, _mist);
    }
  }

  void _lion(Canvas c) {
    // A scalloped mist mane ringing a cream face.
    const centre = Offset(32, 34);
    _disc(c, centre.dx, centre.dy, 20, _mist);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      _disc(
        c,
        centre.dx + 20 * math.cos(a),
        centre.dy + 20 * math.sin(a),
        6.5,
        _mist,
      );
    }
    _disc(c, 22, 23, 4.5, _figure);
    _disc(c, 42, 23, 4.5, _figure);
    _disc(c, 32, 35, 13, _figure);
    _eyes(c, 5.5, 32, 3.8, 4.6);
    _poly(c, const [
      Offset(28.5, 38),
      Offset(35.5, 38),
      Offset(32, 42),
    ], _detail);
    final mouth = Paint()
      ..color = AvatarColors.detail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    c.drawPath(
      Path()
        ..moveTo(28, 43.5)
        ..quadraticBezierTo(32, 46.5, 36, 43.5),
      mouth,
    );
  }

  void _panda(Canvas c) {
    // Dark round ears and tilted eye patches on a cream face.
    _disc(c, 17, 19, 7.5, _detail);
    _disc(c, 47, 19, 7.5, _detail);
    _disc(c, 32, 36, 17.5, _figure);
    _oval(c, 24.5, 35, 9, 12.5, _detail, turn: 35);
    _oval(c, 39.5, 35, 9, 12.5, _detail, turn: -35);
    _disc(c, 25.5, 33.5, 1.9, _figure);
    _disc(c, 38.5, 33.5, 1.9, _figure);
    _oval(c, 32, 43, 6, 4, _detail);
  }

  void _frog(Canvas c) {
    // Eyes bulging on top of a wide head cut flat, and a wide smile.
    final head = Path()
      ..addOval(
        Rect.fromCenter(center: const Offset(32, 42), width: 50, height: 30),
      );
    c.save();
    c.clipRect(const Rect.fromLTRB(0, 0, grid, 54));
    c.drawPath(head, _figure);
    c.restore();
    _disc(c, 20, 25, 9, _figure);
    _disc(c, 44, 25, 9, _figure);
    _disc(c, 20, 25, 4.8, _detail);
    _disc(c, 44, 25, 4.8, _detail);
    _disc(c, 29, 37, 1.2, _detail);
    _disc(c, 35, 37, 1.2, _detail);
    final smile = Paint()
      ..color = AvatarColors.detail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    c.drawPath(
      Path()
        ..moveTo(16, 42)
        ..quadraticBezierTo(32, 52, 48, 42),
      smile,
    );
  }

  void _penguin(Canvas c) {
    // A dark body with a cream face and belly, flippers out, a beak.
    _oval(c, 12, 46, 8, 20, _detail, turn: 25);
    _oval(c, 52, 46, 8, 20, _detail, turn: -25);
    _disc(c, 32, 27, 15, _detail);
    _oval(c, 32, 46, 36, 40, _detail);
    _disc(c, 27, 27, 7.5, _figure);
    _disc(c, 37, 27, 7.5, _figure);
    _oval(c, 32, 48, 24, 30, _figure);
    _eyes(c, 5, 26, 3.6, 4.6);
    _poly(c, const [Offset(28.5, 32), Offset(35.5, 32), Offset(32, 38)], _mist);
  }

  void _placeholder(Canvas c) {
    // A neutral head and shoulders: no animal chosen or known.
    _disc(c, 32, 26, 10, _mist);
    _oval(c, 32, 60, 40, 30, _mist);
  }

  @override
  bool shouldRepaint(AvatarPainter old) =>
      old.avatar != avatar || old.boundary != boundary;
}
