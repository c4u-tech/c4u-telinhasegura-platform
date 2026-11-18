import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';

/// One draw call: its name, its paint and its geometry in the figure's
/// own units (the painter's scale and translation are not applied).
typedef Draw = ({Symbol name, Paint paint, Object shape, Rect bounds});

/// The bounds of the outline [path] traces, not of its control points:
/// sampled along every contour at a hundredth of a unit.
Rect traced(Path path) {
  final points = <Offset>[
    for (final metric in path.computeMetrics())
      for (var at = 0.0; at <= metric.length; at += .01)
        metric.getTangentForOffset(at)!.position,
  ];
  var bounds = Rect.fromPoints(points.first, points.first);
  for (final p in points) {
    bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
  }
  return bounds;
}

/// Records every draw and every clip, save and restore in order.
class FigureLog implements Canvas {
  final draws = <Draw>[];

  /// Every clip, save and restore: how many draws came before it, its
  /// name, and a clip's shape.
  final layers = <(int, Symbol, Object?)>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.positionalArguments;
    final text = name.toString();
    if (text.contains('clip') || name == #save || name == #restore) {
      layers.add((draws.length, name, args.firstOrNull));
      return null;
    }
    if (!text.contains('draw')) return null;
    final paint = args.whereType<Paint>().single;
    final shape = args.first;
    final bounds = switch (shape) {
      Path() => traced(shape),
      RRect() => shape.outerRect,
      Rect() => shape,
      Offset() => Rect.fromCircle(center: shape, radius: args[1] as double),
      _ => Rect.zero,
    };
    draws.add((name: name, paint: paint, shape: shape, bounds: bounds));
    return null;
  }
}

FigureLog paintTevi({
  TeviLook look = TeviLook.watching,
  TeviTier tier = TeviTier.full,
  bool night = false,
  Color? markColor,
}) {
  final log = FigureLog();
  (markColor == null
          ? TeviPainter(look: look, tier: tier, night: night)
          : TeviPainter(
              look: look,
              tier: tier,
              night: night,
              markColor: markColor,
            ))
      .paint(log, const Size.square(132));
  return log;
}

int argb(Color c) => c.toARGB32();
List<int> colorsOf(FigureLog log) => [
  for (final d in log.draws) argb(d.paint.color),
];

Matcher rectNear(double l, double t, double r, double b) => isA<Rect>()
    .having((x) => x.left, 'left', closeTo(l, .02))
    .having((x) => x.top, 'top', closeTo(t, .02))
    .having((x) => x.right, 'right', closeTo(r, .02))
    .having((x) => x.bottom, 'bottom', closeTo(b, .02));

/// A circle drawn at [c] with radius [r].
void expectCircle(Draw d, Offset c, double r, Color color) {
  expect(d.name, #drawCircle);
  final at = d.shape as Offset;
  expect(at.dx, closeTo(c.dx, 1e-9));
  expect(at.dy, closeTo(c.dy, 1e-9));
  expect(d.bounds.width / 2, closeTo(r, 1e-9));
  expect(argb(d.paint.color), argb(color));
}

const dark = BrandColors.dark;
const cream = BrandColors.cream;

void main() {
  group('watching', () {
    final log = paintTevi();
    final d = log.draws;

    test('paints its eleven shapes in the figure\'s order, nothing else', () {
      expect(d, hasLength(11));
      expect(colorsOf(log), [
        argb(dark), // tail
        argb(BrandColors.beak),
        argb(BrandColors.sun), // body
        argb(dark), // crown
        argb(cream), // eyebrow
        argb(dark), // mask
        argb(dark), // leg
        argb(dark), // leg
        argb(cream), // eye
        argb(dark), // pupil
        argb(cream), // highlight
      ]);
    });

    test('the tail and the beak are the drawing\'s rounded triangles', () {
      expect(d[0].name, #drawPath);
      expect(d[0].bounds, rectNear(3.70, 64.35, 25.62, 83.97));
      expect(d[1].name, #drawPath);
      expect(d[1].bounds, rectNear(94.00, 44.20, 115.03, 65.80));
    });

    final clips = [
      for (final (at, name, shape) in log.layers)
        if (name.toString().contains('clip')) (at, shape),
    ];

    test('the body is 84 by 70 at radius 26: the outline every part of it '
        'is cut to', () {
      expect(clips, hasLength(1));
      expect(
        clips.single.$2,
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(14, 20, 84, 70),
          const Radius.circular(26),
        ),
      );
    });

    test('sun, crown, eyebrow and mask are cut to the body', () {
      expect(clips.single.$1, 2, reason: 'the clip comes before the sun');
      expect(d[2].name, #drawPath);
      expect(d[3].bounds, rectNear(14, 20, 98, 38));
      expect(d[4].bounds, rectNear(14, 38, 98, 44.5));
      expect(d[5].name, #drawPath);
      expect(d[5].bounds, rectNear(14, 44.5, 98, 59.28));
      expect(
        log.layers.where((l) => l.$2 == #restore && l.$1 == 6),
        isNotEmpty,
        reason: 'the clip ends after the mask, before the legs',
      );
    });

    test('sun lies only where it shows: below the eyebrow and the mask, '
        'never under the crown, whose antialiased edge it would fringe', () {
      final sun = d[2].shape as Path;
      // The eyebrow's lower edge, and the mask's slanted one under it.
      expect(d[2].bounds.top, greaterThan(44.5));
      double maskEdge(double x) => 54.75 + (59.28 - 54.75) * (x - 14) / 84;
      for (var x = 14.0; x <= 98; x += 2) {
        expect(
          sun.contains(Offset(x, maskEdge(x) + .05)),
          isTrue,
          reason: 'sun meets the mask at x $x, leaving no gap',
        );
        expect(
          sun.contains(Offset(x, maskEdge(x) - 1.5)),
          isFalse,
          reason: 'at most a hairline of sun tucked under the mask at x $x',
        );
      }
      for (final y in [20.5, 30.0, 38.0, 44.0, 50.0]) {
        expect(sun.contains(Offset(56, y)), isFalse, reason: 'y $y');
      }
      // Down to the body's foot, past both sides, so only the body's own
      // outline cuts it.
      expect(sun.contains(const Offset(14.01, 89.9)), isTrue);
      expect(sun.contains(const Offset(97.99, 89.9)), isTrue);
    });

    test('the legs are rounded bars ending at y 103.4', () {
      for (final (i, x) in [(6, 41.6), (7, 59.6)]) {
        expect(d[i].name, #drawRRect);
        expect(
          d[i].shape,
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x, 87.6, x + 4.8, 103.4),
            const Radius.circular(2.4),
          ),
        );
      }
    });

    test('the eye, the pupil and the highlight', () {
      expectCircle(d[8], const Offset(74, 52), 10.5, cream);
      expectCircle(d[9], const Offset(77, 52), 5, dark);
      expectCircle(d[10], const Offset(79, 50), 1.7, cream);
    });
  });

  test('the five looks are values of the same parameters', () {
    expect(TeviLook.watching, const TeviLook());
    expect(TeviLook.winking, const TeviLook(lid: 1));
    expect(TeviLook.lookingBack, const TeviLook(gaze: 1));
    expect(TeviLook.crestUp, const TeviLook(crest: 1));
    expect(TeviLook.asleep, const TeviLook(lid: 1, sag: 1, sleepMarks: true));
  });

  group('each look changes only what the mascot\'s drawing changes', () {
    final watching = paintTevi().draws;

    void expectBodyAsWatching(List<Draw> d, {int from = 0}) {
      for (var i = 0; i < 8; i++) {
        expect(d[from + i].name, watching[i].name, reason: 'part $i');
        expect(d[from + i].bounds, watching[i].bounds, reason: 'part $i');
        expect(
          argb(d[from + i].paint.color),
          argb(watching[i].paint.color),
          reason: 'part $i',
        );
      }
    }

    test('winking: the eye shut to one arch, ends low, apex high', () {
      final d = paintTevi(look: TeviLook.winking).draws;
      expect(d, hasLength(9));
      expectBodyAsWatching(d);
      final lid = d.last;
      expect(lid.name, #drawPath);
      expect(argb(lid.paint.color), argb(cream));
      expect(lid.paint.style, PaintingStyle.stroke);
      expect(lid.paint.strokeWidth, closeTo(4.6, 1e-6));
      expect(lid.paint.strokeCap, StrokeCap.round);
      // The centreline from cap centre to cap centre, apex at y 49.5.
      expect(lid.bounds, rectNear(65, 49.5, 83, 55));
      expect(d.where((x) => x.name == #drawCircle), isEmpty);
    });

    test('asleep: the eyelid sags and two marks float above', () {
      final d = paintTevi(look: TeviLook.asleep).draws;
      expect(d, hasLength(11));
      expectBodyAsWatching(d);
      expect(d[8].paint.style, PaintingStyle.stroke);
      expect(d[8].bounds, rectNear(65, 50, 83, 54.5));
      expect(d.where((x) => x.name == #drawCircle), isEmpty);
      for (final z in d.sublist(9)) {
        expect(argb(z.paint.color), argb(BrandColors.ink));
      }
      expect(d[9].bounds, rectNear(96.40, 19.44, 105.26, 30.00));
      expect(d[10].bounds, rectNear(108.68, 10.21, 114.88, 17.60));
    });

    test('asleep on a dark ground: the marks take the colour given, and '
        'nothing else changes', () {
      final ink = colorsOf(paintTevi(look: TeviLook.asleep));
      final sky = colorsOf(
        paintTevi(look: TeviLook.asleep, markColor: BrandColors.sky),
      );
      expect(sky.sublist(0, 9), ink.sublist(0, 9));
      expect(sky.sublist(9), [argb(BrandColors.sky), argb(BrandColors.sky)]);
    });

    test('looking back: the pupil and the highlight 6.2 to the rear', () {
      final d = paintTevi(look: TeviLook.lookingBack).draws;
      expect(d, hasLength(11));
      expectBodyAsWatching(d);
      expectCircle(d[8], const Offset(74, 52), 10.5, cream);
      expectCircle(d[9], const Offset(70.8, 52), 5, dark);
      expectCircle(d[10], const Offset(72.8, 50), 1.7, cream);
    });

    test('crest up: two feathers behind it all, the eye wider', () {
      final d = paintTevi(look: TeviLook.crestUp).draws;
      expect(d, hasLength(12));
      expect(d.first.name, #drawPath);
      expect(argb(d.first.paint.color), argb(dark));
      expect(d.first.bounds, rectNear(40.85, 7.88, 64.86, 22.00));
      expectBodyAsWatching(d, from: 1);
      expectCircle(d[9], const Offset(74, 52), 12.5, cream);
      expectCircle(d[10], const Offset(74, 52), 4.2, dark);
      expectCircle(d[11], const Offset(76, 50), 1.7, cream);
    });

    test('a half-closed lid covers the eye without moving it', () {
      final log = paintTevi(look: const TeviLook(lid: .5));
      final eye = log.draws.indexWhere((x) => x.name == #drawCircle);
      expectCircle(log.draws[eye], const Offset(74, 52), 10.5, cream);
      expect(
        log.layers.where(
          (l) => l.$1 == eye && l.$2.toString().contains('clip'),
        ),
        isNotEmpty,
        reason: 'the eye is clipped by the lid',
      );
    });
  });

  test('night paints exactly tail, crown, mask, legs and pupil in ink', () {
    final day = colorsOf(paintTevi());
    final night = colorsOf(paintTevi(night: true));
    const parts = [0, 3, 5, 6, 7, 9];
    for (var i = 0; i < day.length; i++) {
      expect(
        night[i],
        parts.contains(i) ? argb(BrandColors.ink) : day[i],
        reason: 'part $i',
      );
    }
    for (final look in [TeviLook.crestUp, TeviLook.asleep]) {
      expect(
        colorsOf(paintTevi(look: look, night: true)),
        isNot(contains(argb(dark))),
      );
    }
  });

  test('the simplified tier drops the tail, the legs and the highlight', () {
    final full = paintTevi().draws;
    final simple = paintTevi(tier: TeviTier.simplified).draws;
    expect(
      [for (final d in simple) d.bounds],
      [
        for (final i in [1, 2, 3, 4, 5, 8, 9]) full[i].bounds,
      ],
    );
  });

  test('it repaints only when an input changes', () {
    TeviPainter p({
      TeviLook look = TeviLook.watching,
      TeviTier tier = TeviTier.full,
      bool night = false,
      Color markColor = BrandColors.ink,
    }) =>
        TeviPainter(look: look, tier: tier, night: night, markColor: markColor);

    expect(p().shouldRepaint(p()), isFalse);
    expect(p(look: const TeviLook(lid: .3)).shouldRepaint(p()), isTrue);
    expect(p(tier: TeviTier.simplified).shouldRepaint(p()), isTrue);
    expect(p(night: true).shouldRepaint(p()), isTrue);
    expect(p(markColor: BrandColors.sky).shouldRepaint(p()), isTrue);
  });

  test('lerp reaches both looks and passes between them', () {
    const a = TeviLook.watching, b = TeviLook.asleep;
    expect(TeviLook.lerp(a, b, 0), a);
    expect(TeviLook.lerp(a, b, 1), b);
    final mid = TeviLook.lerp(TeviLook.lookingBack, TeviLook.crestUp, .5);
    expect(mid, const TeviLook(gaze: .5, crest: .5));
  });

  test('the figure\'s legs end at its perch, a fraction of the box', () {
    expect(TeviPainter.perchY, (103.4 + 6) / 132);
    expect(
      TeviPainter.body,
      const Rect.fromLTRB(20 / 132, 26 / 132, 104 / 132, 96 / 132),
    );
    // The raised crest's tips are the highest any look draws: the marks
    // of sleep stay below them.
    expect(TeviPainter.top, (7.88 + 6) / 132);
    final crest = paintTevi(look: TeviLook.crestUp).draws.first.bounds;
    expect(crest.top, closeTo(TeviPainter.top * 132 - 6, .02));
    final asleep = paintTevi(look: TeviLook.asleep).draws;
    expect(
      asleep.map((d) => d.bounds.top).reduce((a, b) => a < b ? a : b),
      greaterThan(crest.top),
    );
  });

  testWidgets('the widget sizes the figure and is silent unless labelled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Tevi(size: 66, night: true, markColor: BrandColors.sky),
        ),
      ),
    );
    expect(tester.getSize(find.byType(Tevi)), const Size.square(66));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(Tevi),
        matching: find.byType(CustomPaint),
      ),
    );
    expect((paint.painter! as TeviPainter).night, isTrue);
    expect((paint.painter! as TeviPainter).markColor, BrandColors.sky);
    expect(const Tevi(size: 66).markColor, BrandColors.ink);
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Tevi(size: 66, semanticLabel: 'Telinha Segura')),
      ),
    );
    expect(find.bySemanticsLabel('Telinha Segura'), findsOne);
    semantics.dispose();
  });

  group('the ground a mascot stands on picks its colours', () {
    test('night colours where its dark parts would sink into the ground, '
        'day colours wherever they show', () {
      expect(TeviGround.nightOn(BrandColors.dark), isTrue);
      expect(TeviGround.nightOn(Palette.kid.input), isTrue);
      expect(TeviGround.nightOn(BrandColors.ink), isFalse);
      expect(TeviGround.nightOn(ColourWorlds.lightInk), isFalse);
      expect(TeviGround.nightOn(BrandColors.sun), isFalse);
      expect(TeviGround.nightOn(BrandColors.cream), isFalse);
    });

    testWidgets('below a ground, a figure reads it; with none, day colours', (
      tester,
    ) async {
      late BuildContext at;
      Widget probe() => Builder(
        builder: (context) {
          at = context;
          return const SizedBox();
        },
      );
      await tester.pumpWidget(probe());
      expect(TeviGround.nightAt(at), isFalse);
      expect(TeviGround.maybeNightAt(at), isNull);

      await tester.pumpWidget(
        TeviGround(color: BrandColors.dark, child: probe()),
      );
      expect(TeviGround.nightAt(at), isTrue);

      await tester.pumpWidget(
        TeviGround(color: BrandColors.ink, child: probe()),
      );
      expect(TeviGround.nightAt(at), isFalse);
      expect(TeviGround.maybeNightAt(at), isFalse);
    });
  });
}
