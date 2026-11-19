import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// How much of the mascot is drawn. The simplified figure leaves out the
/// tail, the legs and the eye's highlight, for sizes where they would
/// blur into noise.
enum TeviTier { full, simplified }

/// The mascot's expression: a few continuous parameters rather than
/// separate drawings, so one look can pass smoothly into another.
@immutable
class TeviLook {
  const TeviLook({
    this.lid = 0,
    this.sag = 0,
    this.gaze = 0,
    this.crest = 0,
    this.sleepMarks = false,
  });

  /// The eyelid: 0 open, 1 closed to a single curved line.
  final double lid;

  /// The closed eyelid's curve: 0 arches up (a wink), 1 sags down
  /// (sleep).
  final double sag;

  /// 0 looks ahead, past the beak; 1 looks back over its shoulder.
  final double gaze;

  /// 0 flat; 1 the two crest feathers raised and the eye wide open.
  final double crest;

  /// The two small "Z" marks above the head.
  final bool sleepMarks;

  static const watching = TeviLook();
  static const winking = TeviLook(lid: 1);
  static const lookingBack = TeviLook(gaze: 1);
  static const crestUp = TeviLook(crest: 1);
  static const asleep = TeviLook(lid: 1, sag: 1, sleepMarks: true);

  /// The look [t] of the way from [a] to [b]. The marks, which do not
  /// fade, switch halfway.
  static TeviLook lerp(TeviLook a, TeviLook b, double t) => TeviLook(
    lid: lerpDouble(a.lid, b.lid, t)!,
    sag: lerpDouble(a.sag, b.sag, t)!,
    gaze: lerpDouble(a.gaze, b.gaze, t)!,
    crest: lerpDouble(a.crest, b.crest, t)!,
    sleepMarks: t < .5 ? a.sleepMarks : b.sleepMarks,
  );

  @override
  bool operator ==(Object other) =>
      other is TeviLook &&
      other.lid == lid &&
      other.sag == sag &&
      other.gaze == gaze &&
      other.crest == crest &&
      other.sleepMarks == sleepMarks;

  @override
  int get hashCode => Object.hash(lid, sag, gaze, crest, sleepMarks);

  @override
  String toString() =>
      'TeviLook(lid: $lid, sag: $sag, gaze: $gaze, crest: $crest, '
      'sleepMarks: $sleepMarks)';
}

/// How far each part of the mascot has come out of its body, 0 not yet
/// to 1 in place: the app's opening builds the figure from the body
/// alone, as the launch screen shows it. A value past 1 overshoots, for a
/// part that springs into place.
@immutable
class TeviAssembly {
  const TeviAssembly({
    this.look = 1,
    this.eye = 1,
    this.legs = 1,
    this.ends = 1,
  });

  /// The head's crown, eyebrow and mask, wiping across from the tail's
  /// side.
  final double look;

  /// The eye, growing from its centre.
  final double eye;

  /// The legs, dropping from under the body.
  final double legs;

  /// The beak and the tail, sliding out from behind the body.
  final double ends;

  static const whole = TeviAssembly();
  static const body = TeviAssembly(look: 0, eye: 0, legs: 0, ends: 0);

  @override
  bool operator ==(Object other) =>
      other is TeviAssembly &&
      other.look == look &&
      other.eye == eye &&
      other.legs == legs &&
      other.ends == ends;

  @override
  int get hashCode => Object.hash(look, eye, legs, ends);

  @override
  String toString() =>
      'TeviAssembly(look: $look, eye: $eye, legs: $legs, ends: $ends)';
}

/// The mascot, facing right, drawn in its square
/// 132-unit box (the figure's 120 units with 6 of air on each side)
/// scaled to the canvas width.
///
/// The colours are the brand's own, not the theme's: the mascot is the
/// mark. On the darkest ground its dark parts (tail, crown, mask, legs
/// and pupil) would vanish, so [night] paints them in ink instead. The
/// marks of sleep float off the figure, on the ground itself: ink suits
/// a light ground, and [markColor] gives them one that shows on a dark
/// one.
class TeviPainter extends CustomPainter {
  const TeviPainter({
    this.look = TeviLook.watching,
    this.tier = TeviTier.full,
    this.night = false,
    this.markColor = BrandColors.ink,
    this.assembly = TeviAssembly.whole,
  });

  final TeviLook look;
  final TeviTier tier;
  final bool night;

  /// How much of the figure is out of its body.
  final TeviAssembly assembly;

  /// The two "Z" marks of sleep.
  final Color markColor;

  /// The box's side, in figure units.
  static const _box = 132.0;

  /// The figure's origin inside the box.
  static const _air = 6.0;

  /// Where the legs end, as a fraction of the box's height from its top:
  /// stand the figure on an edge by putting this line on it.
  static const perchY = (103.4 + _air) / _box;

  /// How far the legs run past the edge the figure stands on, so they are
  /// seen to land on it rather than hover.
  static const perchOverlap = 2.0;

  /// Where the body starts, from the start of what the figure stands on:
  /// the inset that field's own content keeps.
  static const perchInset = Space.xl;

  /// The highest any look draws, the raised crest's tips, as a fraction
  /// of the box's height from its top: a picture that must hold every
  /// look keeps this line inside it.
  static const top = (7.88 + _air) / _box;

  /// The middle of the whole figure's drawing, tail to beak and crown to
  /// feet, as fractions of the box: where a launch screen centres it.
  static const drawingCentre = Offset(
    ((3.70 + 115.03) / 2 + _air) / _box,
    ((20 + 103.4) / 2 + _air) / _box,
  );

  /// How far the beak and the tail sit behind the body before they come
  /// out: far enough to hide them whole.
  static const _tuckedEnds = 18.0;

  /// The body's rounded rectangle, as fractions of the box.
  static const body = Rect.fromLTRB(
    (14 + _air) / _box,
    (20 + _air) / _box,
    (98 + _air) / _box,
    (90 + _air) / _box,
  );

  static final _body = RRect.fromRectAndRadius(
    const Rect.fromLTWH(14, 20, 84, 70),
    const Radius.circular(26),
  );

  static final _tail = _roundedTriangle(const [
    Offset(21.27, 67.54),
    Offset(6.90, 76.74),
    Offset(22.42, 80.77),
  ], 3.2);

  static final _beak = _roundedTriangle(const [
    Offset(97.40, 47.60),
    Offset(111.63, 55.00),
    Offset(97.40, 62.40),
  ], 3.4);

  /// The dark band across the eye, sloping down towards the beak.
  static final _mask = Path()
    ..addPolygon(const [
      Offset(14, 46),
      Offset(14, 54.75),
      Offset(98, 59.28),
      Offset(98, 46),
      Offset(97.95, 44.5),
      Offset(14.05, 44.5),
    ], true);

  /// How far the sun runs up under the mask's lower edge: a hairline, so
  /// no seam of the ground opens between them.
  static const _sunTuck = 1.0;

  /// The sun of the body: only the part that shows, below the mask's
  /// slanted lower edge. Under the crown, the eyebrow or the mask it
  /// would show through their antialiased edges as a fringe. It runs past
  /// the body's sides and foot, so the body's outline alone cuts it.
  static final _sun = () {
    double edge(double x) =>
        54.75 + (59.28 - 54.75) * (x - 14) / (98 - 14) - _sunTuck;
    return Path()..addPolygon([
      Offset(10, edge(10)),
      Offset(102, edge(102)),
      const Offset(102, 94),
      const Offset(10, 94),
    ], true);
  }();

  static final _legs = [
    for (final x in [41.6, 59.6])
      RRect.fromRectAndRadius(
        Rect.fromLTRB(x, 87.6, x + 4.8, 103.4),
        const Radius.circular(2.4),
      ),
  ];

  /// Two feathers, their bases tucked 2 units behind the top of the head.
  static final _crest = Path()
    ..addPath(
      _roundedTriangle(const [
        Offset(43.05, 19.80),
        Offset(50.61, 19.80),
        Offset(46.29, 10.08),
      ], 2.2),
      Offset.zero,
    )
    ..addPath(
      _roundedTriangle(const [
        Offset(55.79, 19.80),
        Offset(62.66, 19.80),
        Offset(59.72, 12.93),
      ], 2.2),
      Offset.zero,
    );

  /// How far the folded crest sinks: its tips end behind the head.
  static const _crestSink = 14.2;

  static const _z = [
    Offset(0.40, 0.00),
    Offset(0.40, -2.72),
    Offset(5.42, -7.84),
    Offset(5.42, -7.96),
    Offset(0.50, -7.96),
    Offset(0.50, -10.56),
    Offset(9.20, -10.56),
    Offset(9.20, -7.82),
    Offset(4.18, -2.68),
    Offset(4.18, -2.60),
    Offset(9.26, -2.60),
    Offset(9.26, 0.00),
  ];

  static final _marks = [
    for (final (at, scale) in [
      (const Offset(96, 30), 1.0),
      (const Offset(108.4, 17.6), 0.7),
    ])
      Path()..addPolygon([for (final p in _z) at + p * scale], true),
  ];

  /// The width of the closed eyelid's line.
  static const _lidWidth = 4.6;

  /// Half the height of the opening an open eyelid leaves around the
  /// lid's line: enough to clear the widest eye in either curve. Closing,
  /// it narrows to the line's own half-width.
  static const _lidOpen = 16.0;

  /// From this far closed the pupil shrinks away, so the narrowing
  /// opening ends cream, like the line it becomes.
  static const _pupilFrom = .4;

  /// From this far closed the line itself fades in over the opening, so
  /// its round ends appear without a jump.
  static const _lineFrom = .8;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = night ? BrandColors.ink : BrandColors.dark;
    final full = tier == TeviTier.full;
    Paint fill(Color c) => Paint()..color = c;

    canvas.save();
    canvas.scale(size.width / _box);
    canvas.translate(_air, _air);

    final crest = look.crest.clamp(0.0, 1.0);
    if (crest > 0) {
      if (crest < 1) {
        canvas.save();
        canvas.translate(0, (1 - crest) * _crestSink);
      }
      canvas.drawPath(_crest, fill(dark));
      if (crest < 1) canvas.restore();
    }

    final parts = assembly;
    // Behind the body, the tail and the beak slide out of it.
    if (parts.ends > 0) {
      final tucked = (1 - parts.ends) * _tuckedEnds;
      if (full) {
        _moved(canvas, Offset(tucked, 0), () {
          canvas.drawPath(_tail, fill(dark));
        });
      }
      _moved(canvas, Offset(-tucked, 0), () {
        canvas.drawPath(_beak, fill(BrandColors.beak));
      });
    }
    canvas.save();
    canvas.clipRRect(_body);
    final wiping = parts.look < 1;
    if (wiping) {
      // The body still bare, as the launch screen shows it, with the look
      // wiping over it from the tail's side.
      canvas.drawRect(
        const Rect.fromLTRB(14, 20, 98, 90),
        fill(BrandColors.sun),
      );
    }
    if (parts.look > 0) {
      if (wiping) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, 14 + 84 * parts.look, _box));
      }
      canvas.drawPath(_sun, fill(BrandColors.sun));
      canvas.drawRect(const Rect.fromLTRB(14, 20, 98, 38), fill(dark));
      canvas.drawRect(
        const Rect.fromLTRB(14, 38, 98, 44.5),
        fill(BrandColors.cream),
      );
      canvas.drawPath(_mask, fill(dark));
      if (wiping) canvas.restore();
    }
    canvas.restore();

    if (full && parts.legs > 0) {
      void legs() {
        for (final leg in _legs) {
          canvas.drawRRect(leg, fill(dark));
        }
      }

      if (parts.legs < 1) {
        // Hanging from where they leave the body.
        canvas.save();
        canvas.translate(0, _legs.first.top);
        canvas.scale(1, parts.legs);
        canvas.translate(0, -_legs.first.top);
        legs();
        canvas.restore();
      } else {
        legs();
      }
    }

    if (parts.eye > 0) {
      if (parts.eye != 1) {
        canvas.save();
        canvas.translate(74, 52);
        canvas.scale(parts.eye);
        canvas.translate(-74, -52);
      }
      _eye(canvas, dark, full, crest);
      if (parts.eye != 1) canvas.restore();
    }

    if (look.sleepMarks) {
      for (final z in _marks) {
        canvas.drawPath(z, fill(markColor));
      }
    }
    canvas.restore();
  }

  void _eye(Canvas canvas, Color dark, bool full, double crest) {
    final lid = look.lid.clamp(0.0, 1.0);
    final sag = look.sag.clamp(0.0, 1.0);
    // The lid's line: from cap centre to cap centre, arched for a wink,
    // sagging for sleep.
    final ends = lerpDouble(55, 50, sag)!;
    final bend = lerpDouble(44, 59, sag)!;

    if (lid < 1) {
      final open = lid > 0;
      if (open) {
        final half = lerpDouble(_lidOpen, _lidWidth / 2, lid)!;
        canvas.save();
        canvas.clipPath(_opening(ends, bend, half));
      }
      final shift = -6.2 * look.gaze;
      final pupil = 1 - ((lid - _pupilFrom) / (1 - _pupilFrom)).clamp(0, 1);
      canvas.drawCircle(
        const Offset(74, 52),
        lerpDouble(10.5, 12.5, crest)!,
        Paint()..color = BrandColors.cream,
      );
      canvas.drawCircle(
        Offset(lerpDouble(77, 74, crest)! + shift, 52),
        lerpDouble(5, 4.2, crest)! * pupil,
        Paint()..color = dark,
      );
      if (full) {
        canvas.drawCircle(
          Offset(lerpDouble(79, 76, crest)! + shift, 50),
          1.7 * pupil,
          Paint()..color = BrandColors.cream,
        );
      }
      if (open) canvas.restore();
    }

    final line = ((lid - _lineFrom) / (1 - _lineFrom)).clamp(0.0, 1.0);
    if (line > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(65, ends)
          ..quadraticBezierTo(74, bend, 83, ends),
        Paint()
          ..color = line < 1
              ? BrandColors.cream.withValues(alpha: line)
              : BrandColors.cream
          ..style = PaintingStyle.stroke
          ..strokeWidth = _lidWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Draws with [draw] moved by [by], or in place when it is zero.
  static void _moved(Canvas canvas, Offset by, VoidCallback draw) {
    if (by == Offset.zero) return draw();
    canvas.save();
    canvas.translate(by.dx, by.dy);
    draw();
    canvas.restore();
  }

  /// What the eyelid leaves open: the band [half] above and below the
  /// lid's line, run flat past the eye on both sides.
  static Path _opening(double ends, double bend, double half) => Path()
    ..moveTo(50, ends - half)
    ..lineTo(65, ends - half)
    ..quadraticBezierTo(74, bend - half, 83, ends - half)
    ..lineTo(98, ends - half)
    ..lineTo(98, ends + half)
    ..lineTo(83, ends + half)
    ..quadraticBezierTo(74, bend + half, 65, ends + half)
    ..lineTo(50, ends + half)
    ..close();

  /// A triangle with its corners rounded: the outline around three discs
  /// of radius [r] centred at [c].
  static Path _roundedTriangle(List<Offset> c, double r) {
    final centre = (c[0] + c[1] + c[2]) / 3;
    // Each edge's outward normal, from corner i to corner i + 1.
    final normals = [
      for (var i = 0; i < 3; i++)
        () {
          final d = c[(i + 1) % 3] - c[i];
          var n = Offset(d.dy, -d.dx) / d.distance;
          final out = c[i] - centre;
          if (n.dx * out.dx + n.dy * out.dy < 0) n = -n;
          return n;
        }(),
    ];
    final path = Path()
      ..moveTo(c[0].dx + normals[0].dx * r, c[0].dy + normals[0].dy * r);
    for (var i = 0; i < 3; i++) {
      final corner = c[(i + 1) % 3];
      final from = normals[i], to = normals[(i + 1) % 3];
      path.lineTo(corner.dx + from.dx * r, corner.dy + from.dy * r);
      var sweep = to.direction - from.direction;
      while (sweep > math.pi) {
        sweep -= 2 * math.pi;
      }
      while (sweep <= -math.pi) {
        sweep += 2 * math.pi;
      }
      path.arcTo(
        Rect.fromCircle(center: corner, radius: r),
        from.direction,
        sweep,
        false,
      );
    }
    return path..close();
  }

  @override
  bool shouldRepaint(TeviPainter old) =>
      old.look != look ||
      old.tier != tier ||
      old.night != night ||
      old.markColor != markColor ||
      old.assembly != assembly;
}

/// The ground behind every mascot drawn below it, so each picks its
/// colours by what it stands on rather than by the theme: the darkest
/// grounds take the night colours, every other the day's.
class TeviGround extends InheritedWidget {
  const TeviGround({super.key, required this.color, required super.child});

  final Color color;

  /// Below this contrast with [ground] the figure's dark parts would sink
  /// into it, crown and mask lost.
  static const _seen = 1.5;

  /// Whether a mascot on [ground] wears its night colours.
  static bool nightOn(Color ground) {
    final a = BrandColors.dark.computeLuminance() + .05;
    final b = ground.computeLuminance() + .05;
    return (a > b ? a / b : b / a) < _seen;
  }

  /// Whether the ground below [context] asks for the night colours; null
  /// where no ground is set (the guardian's screens).
  static bool? maybeNightAt(BuildContext context) =>
      switch (context.dependOnInheritedWidgetOfExactType<TeviGround>()) {
        final ground? => nightOn(ground.color),
        null => null,
      };

  /// [maybeNightAt], day colours where no ground is set.
  static bool nightAt(BuildContext context) => maybeNightAt(context) ?? false;

  @override
  bool updateShouldNotify(TeviGround old) => old.color != color;
}

/// The mascot at [size] by [size]. It is decoration unless given a
/// [semanticLabel]: most places name the app or the moment in words
/// beside it.
///
/// A new [look] on a mascot already shown eases in over [Motion.change],
/// or [Motion.fallAsleep] when it goes to sleep, once and never again on
/// its own; under reduced motion it is a cut. With [blinks] it blinks
/// once as its screen arrives; while [searching] its gaze sweeps.
class Tevi extends StatefulWidget {
  const Tevi({
    super.key,
    required this.size,
    this.tier = TeviTier.full,
    this.look = TeviLook.watching,
    this.night = false,
    this.markColor = BrandColors.ink,
    this.semanticLabel,
    this.eases = true,
    this.blinks = false,
    this.searching = false,
    this.assembly = TeviAssembly.whole,
  });

  final double size;
  final TeviTier tier;
  final TeviLook look;

  /// How much of the figure is out of its body: whole but for the
  /// opening, which brings the parts out frame by frame.
  final TeviAssembly assembly;

  /// The night colours, for the darkest ground.
  final bool night;

  /// The marks of sleep: ink by default, for a light ground.
  final Color markColor;
  final String? semanticLabel;

  /// Whether a new [look] eases in. A caller that moves the look itself,
  /// frame by frame, draws each one as given.
  final bool eases;

  /// Whether it blinks once, over [Motion.blink], when its screen has
  /// arrived: a sign of life on the child's screens, never repeated while
  /// it stays. An eye already shut, or a platform asking for reduced
  /// motion, has no blink.
  final bool blinks;

  /// Whether its gaze sweeps slowly back over its shoulder and ahead
  /// again, once every [Motion.gaze]: what is loading, shown as someone
  /// looking for it. The one motion a mascot makes on its own, so it is
  /// kept for a screen that only waits, and runs only while shown; under
  /// reduced motion the mascot looks ahead, still.
  final bool searching;

  /// How long the passage to [look] takes: a sleepy eye closes slowly.
  static Duration lengthTo(TeviLook look) =>
      look.sleepMarks ? Motion.fallAsleep : Motion.change;

  @override
  State<Tevi> createState() => _TeviState();
}

class _TeviState extends State<Tevi> with TickerProviderStateMixin {
  late final _change = AnimationController(vsync: this);

  /// The eye shutting and opening again: 0 open, 1 shut, halfway in.
  late final _blink = AnimationController(vsync: this, duration: Motion.blink);
  late final Animation<double> _shut = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 1),
  ]).chain(CurveTween(curve: Motion.sway)).animate(_blink);

  /// The gaze sweeping: back in the first half, ahead in the second.
  late final _search = AnimationController(vsync: this, duration: Motion.gaze);
  late final Animation<double> _back = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 1),
  ]).chain(CurveTween(curve: Motion.sway)).animate(_search);

  /// Whether the arrival was already seen, blink or not.
  bool _arrived = false;

  /// The page this mascot arrives with, while it is still coming in.
  Animation<double>? _coming;

  /// Where the passage under way started.
  late TeviLook _from = widget.look;

  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _change,
    curve: Motion.settle,
  );

  TeviLook get _look {
    final look = _change.isAnimating
        ? TeviLook.lerp(_from, widget.look, _eased.value)
        : widget.look;
    if (!_blink.isAnimating && !_search.isAnimating) return look;
    final shut = _blink.isAnimating ? _shut.value : 0.0;
    final back = _search.isAnimating ? _back.value : 0.0;
    return TeviLook(
      lid: look.lid + (1 - look.lid) * shut,
      sag: look.sag,
      gaze: look.gaze + (1 - look.gaze) * back,
      crest: look.crest,
      sleepMarks: look.sleepMarks,
    );
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _searchOrNot() {
    if (!widget.searching || !Motion.loopsIn(context)) {
      _search.reset();
    } else if (!_search.isAnimating) {
      _search.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _searchOrNot();
    if (_arrived) return;
    _arrived = true;
    if (!widget.blinks || widget.look.lid > 0 || _still) {
      return;
    }
    _awaitArrival(ModalRoute.of(context));
  }

  /// Blinks once [route] has arrived. A page still growing in would hide
  /// most of a blink, so it waits for it; a page being laid out unseen,
  /// before its first shown frame, is not there yet either.
  void _awaitArrival(ModalRoute<Object?>? route) {
    if (!mounted) return;
    if (route == null) {
      _blink.forward();
    } else if (route.offstage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _awaitArrival(route));
    } else if (route.animation case final page? when !page.isCompleted) {
      _coming = page..addStatusListener(_pageMoved);
    } else {
      _blink.forward();
    }
  }

  void _pageMoved(AnimationStatus status) {
    if (status.isAnimating) return;
    _coming?.removeStatusListener(_pageMoved);
    _coming = null;
    if (status.isCompleted && widget.look.lid == 0) _blink.forward();
  }

  @override
  void didUpdateWidget(Tevi old) {
    super.didUpdateWidget(old);
    if (widget.searching != old.searching) _searchOrNot();
    if (widget.look == old.look) return;
    if (!widget.eases || _still) {
      _change.stop();
      return;
    }
    // From the look drawn now, so a change during a change never jumps.
    _from = _change.isAnimating
        ? TeviLook.lerp(_from, old.look, _eased.value)
        : old.look;
    _eased.curve = widget.look.sleepMarks ? Motion.sway : Motion.settle;
    _change
      ..duration = Tevi.lengthTo(widget.look)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _coming?.removeStatusListener(_pageMoved);
    _eased.dispose();
    _change.dispose();
    _blink.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final figure = AnimatedBuilder(
      animation: Listenable.merge([_change, _blink, _search]),
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: TeviPainter(
          look: _look,
          tier: widget.tier,
          night: widget.night,
          markColor: widget.markColor,
          assembly: widget.assembly,
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: figure);
    return Semantics(image: true, label: label, child: figure);
  }
}

/// The mascot standing in a child's screen: it faces the content, so it
/// is mirrored right to left, and takes its colours from the ground below
/// it unless told [night]. It blinks once as its screen arrives, unless
/// told not to [blinks].
class FacingTevi extends StatelessWidget {
  const FacingTevi({
    super.key,
    required this.size,
    this.look = TeviLook.watching,
    this.night,
    this.markColor = BrandColors.ink,
    this.blinks = true,
    this.searching = false,
  });

  final double size;
  final TeviLook look;
  final bool? night;
  final Color markColor;
  final bool blinks;

  /// As [Tevi.searching].
  final bool searching;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: Directionality.of(context) == TextDirection.rtl,
    child: Tevi(
      size: size,
      look: look,
      night: night ?? TeviGround.nightAt(context),
      markColor: markColor,
      blinks: blinks,
      searching: searching,
    ),
  );
}
