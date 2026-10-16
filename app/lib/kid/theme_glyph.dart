import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../curation/curation.dart' show VideoTheme;
import '../design/tokens.dart';
import '../family/avatars.dart' show AvatarColors;

/// A theme's name, for assistive technology only: a pre-reader finds the
/// shelf by its glyph.
String themeName(VideoTheme theme) => switch (theme) {
  VideoTheme.bichos => 'Bichos',
  VideoTheme.musica => 'Música',
  VideoTheme.historias => 'Histórias',
  VideoTheme.aprender => 'Aprender',
  VideoTheme.brincar => 'Brincar',
  VideoTheme.natureza => 'Natureza',
  VideoTheme.unknown => '',
};

/// A shelf's label: the theme drawn, read by its name, never a target.
class ThemeGlyph extends StatelessWidget {
  const ThemeGlyph(this.theme, {super.key, this.size = KidSizes.target});

  final VideoTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: themeName(theme),
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: ThemeGlyphPainter(theme)),
    ),
  );
}

/// The six themes, cut from the Espiadinha's vocabulary like the avatars
/// (discs, the 58 × 33 screen at its 10/33 corner, flat cuts) on the same
/// 64-unit grid, straight on the kid ground: a cream figure, dark details
/// and the one mid tone. Each reads by silhouette alone; sun stays the
/// Espiadinha's.
class ThemeGlyphPainter extends CustomPainter {
  const ThemeGlyphPainter(this.theme);

  final VideoTheme theme;

  static const grid = 64.0;

  static final _figure = Paint()..color = AvatarColors.figure;
  static final _detail = Paint()..color = AvatarColors.detail;
  static final _mist = Paint()..color = AvatarColors.mist;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / grid);
    switch (theme) {
      case VideoTheme.bichos:
        _paw(canvas);
      case VideoTheme.musica:
        _notes(canvas);
      case VideoTheme.historias:
        _book(canvas);
      case VideoTheme.aprender:
        _blocks(canvas);
      case VideoTheme.brincar:
        _ball(canvas);
      case VideoTheme.natureza:
        _tree(canvas);
      case VideoTheme.unknown:
        break;
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

  /// The mark's screen: a rounded rectangle with a 10/33 corner.
  static void _screen(Canvas c, Rect r, Paint p) => c.drawRRect(
    RRect.fromRectAndRadius(
      r,
      Radius.circular(r.shortestSide * Radii.screenRatio),
    ),
    p,
  );

  void _paw(Canvas c) {
    // A pad and four toes, the outer two turned out.
    _oval(c, 32, 42, 30, 24, _figure);
    _oval(c, 14, 27, 10, 13, _figure, turn: -25);
    _oval(c, 25, 16, 10, 14, _figure, turn: -8);
    _oval(c, 39, 16, 10, 14, _figure, turn: 8);
    _oval(c, 50, 27, 10, 13, _figure, turn: 25);
  }

  void _notes(Canvas c) {
    // Two beamed notes: mist heads, cream stems under a flat-cut beam.
    _screen(c, const Rect.fromLTWH(24, 8, 32, 8), _figure);
    _screen(c, const Rect.fromLTWH(24, 8, 5, 38), _figure);
    _screen(c, const Rect.fromLTWH(51, 8, 5, 32), _figure);
    _oval(c, 19, 47, 16, 12, _figure, turn: -20);
    _oval(c, 46, 41, 16, 12, _figure, turn: -20);
  }

  void _book(Canvas c) {
    // An open book: two cream pages on a mist cover, a dark spine.
    _screen(c, const Rect.fromLTWH(4, 16, 56, 38), _mist);
    _screen(c, const Rect.fromLTWH(7, 12, 24, 38), _figure);
    _screen(c, const Rect.fromLTWH(33, 12, 24, 38), _figure);
    c.drawRect(const Rect.fromLTWH(31, 14, 2, 38), _detail);
    // Lines of story, in the mist tone, cut short.
    for (final y in [22.0, 29.0, 36.0]) {
      _screen(c, Rect.fromLTWH(11, y, 16, 3), _mist);
      _screen(c, Rect.fromLTWH(37, y, 16, 3), _mist);
    }
  }

  void _blocks(Canvas c) {
    // Three stacked blocks, each with a shape cut in: a disc, a screen, a
    // wedge.
    _screen(c, const Rect.fromLTWH(6, 34, 25, 25), _figure);
    _screen(c, const Rect.fromLTWH(33, 34, 25, 25), _mist);
    _screen(c, const Rect.fromLTWH(19.5, 7, 25, 25), _figure);
    _disc(c, 18.5, 46.5, 6.5, _detail);
    _screen(c, const Rect.fromLTWH(38, 42, 15, 9), _detail);
    c.drawPath(
      Path()..addPolygon(const [
        Offset(32, 12.5),
        Offset(39.5, 26),
        Offset(24.5, 26),
      ], true),
      _detail,
    );
  }

  void _ball(Canvas c) {
    // A beach ball: a cream disc whose gores, two in the mid tone, curve
    // from a pole up to the left, so its roundness reads by silhouette.
    const centre = Offset(32, 32);
    const r = 26.0;
    _disc(c, centre.dx, centre.dy, r, _figure);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: r)));
    const pole = Offset(20, 17);
    for (final (sweep, paint) in [(0.0, _mist), (120.0, _mist)]) {
      c.save();
      c.translate(pole.dx, pole.dy);
      c.rotate(sweep * math.pi / 180);
      c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(46, 6, 52, 46)
          ..quadraticBezierTo(22, 40, 0, 0)
          ..close(),
        paint,
      );
      c.restore();
    }
    c.restore();
    _disc(c, pole.dx, pole.dy, 4, _figure);
  }

  void _tree(Canvas c) {
    // Three discs of leaves over a mist trunk cut flat at the ground.
    _screen(c, const Rect.fromLTWH(27, 34, 10, 26), _mist);
    _disc(c, 22, 30, 14, _figure);
    _disc(c, 42, 30, 14, _figure);
    _disc(c, 32, 18, 15, _figure);
  }

  @override
  bool shouldRepaint(ThemeGlyphPainter old) => old.theme != theme;
}
