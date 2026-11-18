import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';

/// Where the figure's tail starts and its beak ends, as fractions of its
/// box's width.
const _tail = (3.70 + 6) / 132;
const _beak = (115.03 + 6) / 132;

/// Midway between the legs, as a fraction of the box's width.
const _feet = (53 + 6) / 132;

/// Expects [within] to hold one state picture: the mascot in [look], whole
/// inside the picture, in its day colours with sky marks of sleep (the
/// child's ground is ink), standing at the start side of what it perches
/// on, its legs landing a little into it, as on the guardian's field.
/// A wire runs [across] the whole screen, or only across the
/// picture's own screen. A figure on a dark stage wears its [night]
/// colours. Returns the picture's finder.
Finder expectPerched(
  WidgetTester tester,
  Finder within,
  TeviLook look, {
  Perch perch = Perch.screen,
  bool across = false,
  bool night = false,
}) {
  final picture = find.descendant(
    of: within,
    matching: find.byType(ShelfPicture),
  );
  expect(picture, findsOneWidget);
  final figure = find.descendant(of: picture, matching: find.byType(Tevi));
  expect(figure, findsOneWidget);
  final tevi = tester.widget<Tevi>(figure);
  expect(
    (tevi.look, tevi.tier, tevi.night, tevi.markColor),
    (look, TeviTier.full, night, BrandColors.sky),
  );

  final box = tester.getRect(picture);
  final s = box.width / ShelfPicture.size.width;
  expect(box.height, closeTo(ShelfPicture.size.height * s, 1e-6));
  final at = tester.getRect(figure);
  final feetX = at.left + at.width * _feet;
  final stand = switch (perch) {
    Perch.screen => ShelfPicture.screen.top,
    Perch.wire =>
      ShelfPicture.wireAt((feetX - box.left) / s) - ShelfPicture.stroke / 2,
  };
  expect(
    at.top + at.height * TeviPainter.perchY,
    closeTo(box.top + (stand + TeviPainter.perchOverlap) * s, 1e-6),
    reason: 'the legs land on what the mascot stands on',
  );
  expect(
    at.left + at.width * TeviPainter.body.left,
    closeTo(
      box.left + (ShelfPicture.screen.left + TeviPainter.perchInset) * s,
      1e-6,
    ),
    reason: 'the body starts at the start side, as on the guardian\'s field',
  );
  // Whole: every look's drawing stays inside the picture.
  expect(at.top + at.height * TeviPainter.top, greaterThanOrEqualTo(box.top));
  expect(at.left + at.width * _tail, greaterThanOrEqualTo(box.left));
  expect(at.left + at.width * _beak, lessThanOrEqualTo(box.right));

  // Painted in the picture's own scale: a box around it (the goodbye's
  // at large text) may shrink it on screen.
  final local = tester.widget<ShelfPicture>(picture).scale;
  final ground = find.descendant(
    of: picture,
    matching: find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is! TeviPainter,
    ),
  );
  final screen = RRect.fromRectAndRadius(
    Rect.fromLTRB(
      ShelfPicture.screen.left * local,
      ShelfPicture.screen.top * local,
      ShelfPicture.screen.right * local,
      ShelfPicture.screen.bottom * local,
    ).deflate(ShelfPicture.stroke * local / 2),
    Radius.circular(
      (ShelfPicture.screen.height * Radii.screenRatio -
              ShelfPicture.stroke / 2) *
          local,
    ),
  );
  // The line in the figure colour, at the screen's stroke, within float
  // precision of the picture's scale; a wire in the dark is ink, a thin
  // line there.
  final colour = night && perch == Perch.wire
      ? BrandColors.ink
      : Palette.kid.onField;
  bool line(List<dynamic> args) {
    final paint = args.whereType<Paint>().single;
    return paint.color.toARGB32() == colour.toARGB32() &&
        paint.style == PaintingStyle.stroke &&
        (paint.strokeWidth - ShelfPicture.stroke * local).abs() < 1e-4;
  }

  bool near(RRect a, RRect b) =>
      (a.left - b.left).abs() < 1e-4 &&
      (a.top - b.top).abs() < 1e-4 &&
      (a.right - b.right).abs() < 1e-4 &&
      (a.bottom - b.bottom).abs() < 1e-4 &&
      (a.tlRadiusX - b.tlRadiusX).abs() < 1e-4;

  switch (perch) {
    case Perch.screen:
      expect(
        ground,
        paints..something(
          (method, args) =>
              method == #drawRRect &&
              near(args.first as RRect, screen) &&
              line(args),
        ),
      );
    case Perch.wire:
      final long = find.descendant(
        of: picture,
        matching: find.byType(ScreenWire),
      );
      if (!across) {
        expect(long, findsNothing, reason: 'the short wire, in the picture');
        expect(
          ground,
          paints
            ..something((method, args) => method == #drawPath && line(args)),
        );
        expect(ground, isNot(paints..rrect()));
        break;
      }
      expect(ground, findsNothing, reason: 'no short wire under the long one');
      expect(long, findsOneWidget);
      late Path wire;
      expect(
        long,
        paints..something((method, args) {
          if (method != #drawPath || !line(args)) return false;
          wire = args.first as Path;
          return true;
        }),
      );
      // The wire, sampled along its length, in the screen's coordinates.
      final origin = tester.getTopLeft(long);
      final points = [
        for (final metric in wire.computeMetrics())
          for (var at = 0.0; at <= metric.length; at += .25)
            metric.getTangentForOffset(at)!.position + origin,
      ];
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final xs = points.map((p) => p.dx);
      expect(xs.reduce(math.min), closeTo(0, .3), reason: 'edge');
      expect(xs.reduce(math.max), closeTo(width, .3), reason: 'to edge');
      final ys = points.map((p) => p.dy);
      final ends = points.first.dy;
      expect(points.last.dy, closeTo(ends, .1), reason: 'level ends');
      final sag = ys.reduce(math.max) - ends;
      expect(sag, greaterThan(0), reason: 'it sags');
      expect(sag, lessThan(width / 40), reason: 'gently');
      // The mascot stands where it stood: on the wire's centreline under
      // its feet.
      final under = points.reduce(
        (a, b) => (a.dx - feetX).abs() < (b.dx - feetX).abs() ? a : b,
      );
      expect(
        under.dy,
        closeTo(box.top + ShelfPicture.wireAt((feetX - box.left) / s) * s, .1),
      );
  }
  return picture;
}
