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

/// A theme's colour world: the ground of its block and its page, and the
/// figure drawn on it.
ColourWorld worldOf(VideoTheme theme) => switch (theme) {
  VideoTheme.bichos => ColourWorlds.bichos,
  VideoTheme.musica => ColourWorlds.musica,
  VideoTheme.historias => ColourWorlds.historias,
  VideoTheme.aprender => ColourWorlds.aprender,
  VideoTheme.brincar => ColourWorlds.brincar,
  VideoTheme.natureza => ColourWorlds.natureza,
  // Never shown: the catalogue leaves an unknown theme out.
  VideoTheme.unknown => ColourWorlds.home,
};

/// A theme drawn, read by its name, never a target: one solid silhouette
/// in [color] (the kid ground's cream by default), what separates its
/// parts cut clear through to whatever lies beneath. [ground] is kept for
/// callers that name the world it stands on; the cuts no longer need it.
class ThemeGlyph extends StatelessWidget {
  const ThemeGlyph(
    this.theme, {
    super.key,
    this.size = KidSizes.target,
    this.color,
    this.ground,
  });

  final VideoTheme theme;
  final double size;
  final Color? color;
  final Color? ground;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: themeName(theme),
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: ThemeGlyphPainter(theme, color: color, ground: ground),
      ),
    ),
  );
}

/// The six themes, cut from the avatars' vocabulary (discs, a rounded
/// screen at the shape ratio's corner, flat cuts) on the same 64-unit
/// grid, every one in a single colour: no mid tone and no inner detail
/// that a 24 dp glyph would blur, so each reads by its silhouette alone
/// and weighs about as much as the others on its block.
class ThemeGlyphPainter extends CustomPainter {
  const ThemeGlyphPainter(this.theme, {this.color, this.ground});

  final VideoTheme theme;
  final Color? color;
  final Color? ground;

  static const grid = 64.0;

  Paint get _figure => Paint()..color = color ?? AvatarColors.figure;

  /// Cuts through the figure, showing whatever lies beneath it.
  static final _cut = Paint()..blendMode = BlendMode.clear;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(size.shortestSide / grid);
    switch (theme) {
      case VideoTheme.bichos:
        _paw(canvas);
      case VideoTheme.musica:
        _notes(canvas);
      case VideoTheme.historias:
        _book(canvas);
      case VideoTheme.aprender:
        _shapes(canvas);
      case VideoTheme.brincar:
        _ball(canvas);
      case VideoTheme.natureza:
        _tree(canvas);
      case VideoTheme.unknown:
        break;
    }
    canvas.restore();
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

  /// A screen: a rounded rectangle at the shape ratio's corner.
  static void _screen(Canvas c, Rect r, Paint p) => c.drawRRect(
    RRect.fromRectAndRadius(
      r,
      Radius.circular(r.shortestSide * Radii.screenRatio),
    ),
    p,
  );

  void _paw(Canvas c) {
    // A pad and four toes, the outer two turned out.
    _oval(c, 32, 43, 32, 26, _figure);
    _oval(c, 13, 27, 12, 15, _figure, turn: -25);
    _oval(c, 25, 15, 12, 16, _figure, turn: -8);
    _oval(c, 39, 15, 12, 16, _figure, turn: 8);
    _oval(c, 51, 27, 12, 15, _figure, turn: 25);
  }

  void _notes(Canvas c) {
    // Two beamed notes: heads, stems and a flat-cut beam, one shape.
    _screen(c, const Rect.fromLTWH(23, 7, 35, 11), _figure);
    _screen(c, const Rect.fromLTWH(23, 7, 7, 40), _figure);
    _screen(c, const Rect.fromLTWH(51, 7, 7, 34), _figure);
    _oval(c, 18, 47, 21, 16, _figure, turn: -20);
    _oval(c, 46, 41, 21, 16, _figure, turn: -20);
  }

  void _book(Canvas c) {
    // An open book seen from the front: two pages whose top edges dip
    // to the spine, parted there by a cut wide enough to hold at 24 dp.
    Path page(double outer, double inner) => Path()
      ..moveTo(outer, 16)
      ..quadraticBezierTo((outer + inner) / 2, 11, inner, 19)
      ..lineTo(inner, 50)
      ..quadraticBezierTo((outer + inner) / 2, 43, outer, 48)
      ..close();
    c.drawPath(page(7, 30), _figure);
    c.drawPath(page(57, 34), _figure);
  }

  void _shapes(Canvas c) {
    // Three shapes to learn, whole: a disc, a screen and a wedge.
    _disc(c, 18, 19, 12, _figure);
    _screen(c, const Rect.fromLTWH(35, 8, 22, 22), _figure);
    c.drawPath(
      Path()..addPolygon(const [
        Offset(32, 33),
        Offset(47, 58),
        Offset(17, 58),
      ], true),
      _figure,
    );
  }

  void _ball(Canvas c) {
    // A beach ball: a disc cut hollow, a rim left, and two gores curving
    // from a pole up to the left, so its roundness reads by silhouette
    // without a solid disc outweighing the other glyphs.
    const centre = Offset(32, 32);
    const r = 26.0;
    _disc(c, centre.dx, centre.dy, r, _figure);
    _disc(c, centre.dx, centre.dy, r - _rim, _cut);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: r)));
    const pole = Offset(20, 17);
    for (final sweep in [0.0, 120.0]) {
      c.save();
      c.translate(pole.dx, pole.dy);
      c.rotate(sweep * math.pi / 180);
      c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(46, 6, 52, 46)
          ..quadraticBezierTo(22, 40, 0, 0)
          ..close(),
        _figure,
      );
      c.restore();
    }
    c.restore();
    _disc(c, pole.dx, pole.dy, 4, _figure);
  }

  /// The hollow ball's rim.
  static const _rim = 4.0;

  void _tree(Canvas c) {
    // Three discs of leaves over a trunk cut flat at the ground.
    _screen(c, const Rect.fromLTWH(28, 34, 8, 26), _figure);
    _disc(c, 22, 31, 12, _figure);
    _disc(c, 42, 31, 12, _figure);
    _disc(c, 32, 19, 13, _figure);
  }

  @override
  bool shouldRepaint(ThemeGlyphPainter old) =>
      old.theme != theme || old.color != color || old.ground != ground;
}
