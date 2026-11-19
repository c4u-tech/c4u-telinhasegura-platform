import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/band_transition.dart';
import '../design/theme.dart';
import '../design/tevi.dart';
import '../design/tokens.dart';

/// Shown while the app does not yet know who it is in front of:
/// the plain ground, nothing to read
/// or press. Only a failed read of the mode says so and offers
/// "Tentar de novo", which calls [onRetry].
///
/// At the app's start it is the opening instead: [mascot], the ink ground
/// of the launch screen with the mascot standing on it.
class Splash extends StatelessWidget {
  const Splash({super.key, this.onRetry, this.mascot});

  final VoidCallback? onRetry;

  /// The opening's scene: the launch screen's ink ground and the mascot
  /// placed on it, which it draws itself, so it can lift the ground away.
  final Widget? mascot;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    if (retry == null) {
      if (mascot case final mascot?) {
        return Semantics(
          label: 'Carregando',
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: mascot,
          ),
        );
      }
      return Semantics(
        label: 'Carregando',
        child: ColoredBox(color: context.palette.ground),
      );
    }
    return Material(
      color: context.palette.ground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ErrorNote(Copy.genericRetry),
                  const SizedBox(height: Space.lg),
                  PrimaryButton(label: 'Tentar de novo', onPressed: retry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the opening stands.
enum _Stage {
  /// The mascot coming out of its body.
  assembling,

  /// Assembled, waiting for the mode.
  waiting,

  /// The ground lifting away from the first screen.
  lifting,

  /// Over: from here on the app shows its screen, or [Splash] as it
  /// always has.
  done,
}

/// The app from its start: the launch screen's ground and the mascot's
/// body, which assembles over [Motion.opening]; then, once the mode is
/// known ([ready]), the ground gives way to [child], the first screen,
/// over [Motion.band]. Where that screen has a mascot of its own (a
/// [TeviLanding]), the opening's travels onto it, in one movement, and the
/// ground closes onto the ink field it stands on, if any; elsewhere the
/// ground lifts away with the mascot. A mode known early waits for the
/// assembly; a mode
/// that takes longer leaves the mascot searching until it is known; a
/// failed read ([failed]) shows the note and its retry, [onRetry].
///
/// It plays once, as the process starts: a retry, a return from the
/// background or a later wait for the mode shows [Splash] as before.
/// Under reduced motion the mascot stands whole and still, and the
/// first screen cuts in.
class Opening extends StatefulWidget {
  const Opening({
    super.key,
    required this.ready,
    required this.failed,
    required this.onRetry,
    required this.child,
  });

  final bool ready;
  final bool failed;
  final VoidCallback onRetry;
  final Widget child;

  /// The side of the mascot's box on the launch screen, so the body the
  /// opening starts from lands on the one it showed. Every launch screen
  /// gives it the same box: iOS, Android below 12 and the web show a
  /// 192 dp image that is the box; Android 12 and later a 288 dp icon,
  /// the box two thirds of it, inside the 192 dp circle shown.
  static const markSide = 192.0;

  @override
  State<Opening> createState() => _OpeningState();
}

class _OpeningState extends State<Opening> with TickerProviderStateMixin {
  late final _clock = AnimationController(vsync: this, duration: Motion.opening)
    ..addStatusListener(_moved);
  late final _lift = AnimationController(vsync: this, duration: Motion.band)
    ..addStatusListener(_moved);

  _Stage _stage = _Stage.assembling;
  final _screen = GlobalKey();

  /// The ground keeps its element, and "Carregando" its node, when the
  /// first screen comes in beneath it, so nothing is read out twice.
  final _cover = GlobalKey();

  /// Holds the first screen's mascots back, unseen, until the opening's
  /// lands on them; the opening is then over.
  final _handoff = TeviHandoff();

  bool get _still => !Motion.opensIn(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stage != _Stage.assembling || _clock.isAnimating) return;
    if (_still) {
      _stage = _Stage.waiting;
      _advance();
    } else {
      _clock.forward();
    }
  }

  @override
  void didUpdateWidget(Opening old) {
    super.didUpdateWidget(old);
    if (widget.ready != old.ready || widget.failed != old.failed) _advance();
  }

  void _moved(AnimationStatus status) {
    if (!status.isCompleted) return;
    setState(() {
      if (_stage == _Stage.lifting) {
        _end();
      } else {
        _stage = _Stage.waiting;
        _advance();
      }
    });
  }

  void _end() {
    _stage = _Stage.done;
    _handoff.release();
  }

  /// Moves on from waiting once the mode is known or its read failed.
  void _advance() {
    if (_stage != _Stage.waiting) return;
    if (widget.failed) {
      _end();
    } else if (widget.ready) {
      if (_still) {
        _end();
      } else {
        _stage = _Stage.lifting;
        _lift.forward();
        // Once the screen can take focus again, the frame after this one.
        WidgetsBinding.instance.addPostFrameCallback((_) => _autofocus());
      }
    }
  }

  /// Gives the first screen the focus it asked for as it was built. It was
  /// built under the ground, where nothing takes focus, so a field that
  /// asked for it then was turned down; it asks again now, as it would
  /// have, through its scope.
  void _autofocus() {
    if (!mounted) return;
    void visit(Element element) {
      final widget = element.widget;
      FocusNode? asked;
      if (widget is EditableText && widget.autofocus) {
        asked = widget.focusNode;
      } else if (widget is Focus && widget.autofocus) {
        asked = widget.focusNode;
        element.visitChildren(
          (child) => asked ??= Focus.maybeOf(
            child,
            scopeOk: true,
            createDependency: false,
          ),
        );
      }
      if (asked case final node?) FocusScope.of(element).autofocus(node);
      element.visitChildren(visit);
    }

    _screen.currentContext?.visitChildElements(visit);
  }

  @override
  void dispose() {
    _clock.dispose();
    _lift.dispose();
    _handoff.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cover = switch (_stage) {
      _Stage.done when widget.ready => null,
      _Stage.done => Splash(onRetry: widget.failed ? widget.onRetry : null),
      // Lifting, the first screen is read; the ground is on its way.
      _ => ExcludeSemantics(
        excluding: _stage == _Stage.lifting,
        child: Splash(
          mascot: AnimatedBuilder(
            animation: Listenable.merge([_clock, _lift]),
            builder: (context, _) =>
                LayoutBuilder(builder: (context, box) => _scene(box.biggest)),
          ),
        ),
      ),
    };
    final hidden = _stage == _Stage.assembling || _stage == _Stage.waiting;
    // The first screen lies beneath the ground from the moment the mode is
    // known, so it is ready when the ground lifts: its reads already under
    // way, but nothing in it read out, focused or typed into until then.
    // Its key keeps it, state and all, when the ground goes and it stands
    // alone, with nothing painted over it.
    final screen = KeyedSubtree(
      key: _screen,
      child: TeviHandoffScope(
        handoff: _handoff,
        child: ExcludeFocus(
          excluding: hidden,
          child: ExcludeSemantics(excluding: hidden, child: widget.child),
        ),
      ),
    );
    if (cover == null) return screen;
    final kept = KeyedSubtree(key: _cover, child: cover);
    if (!widget.ready) return kept;
    return Stack(fit: StackFit.expand, children: [screen, kept]);
  }

  /// The first screen's own mascot, where it stands now, if it has one.
  TeviSpot? _spot() {
    final opening = context.findRenderObject();
    if (opening is! RenderBox || !opening.hasSize) return null;
    return _handoff.spotIn(opening);
  }

  /// The ground and the mascot on a screen of [size]: assembling, waiting
  /// or giving way to the first screen.
  Widget _scene(Size size) {
    final start =
        (size.center(Offset.zero) -
            TeviPainter.drawingCentre * Opening.markSide) &
        const Size.square(Opening.markSide);
    final (assembly, look) = _stage == _Stage.assembling
        ? openingAt(_clock.value * Motion.opening.inMilliseconds)
        : (TeviAssembly.whole, TeviLook.watching);
    final lifting = _stage == _Stage.lifting;
    final v = lifting ? _lift.value : 0.0;
    final t = Motion.settle.transform(v);
    final spot = lifting ? _spot() : null;
    final screen = RRect.fromRectAndRadius(Offset.zero & size, Radius.zero);
    final field = spot?.field;
    // With nowhere to land, the mascot rides the ground away.
    final slide = spot == null ? t * size.height : 0.0;
    final box = spot == null
        ? start.shift(Offset(0, -slide))
        : Rect.lerp(start, spot.box, t)!;
    final shown = spot == null ? look : TeviLook.lerp(look, spot.look, t);
    // Its colours turn to the landing's on the way, if they differ.
    final night = spot != null && spot.night ? t : 0.0;
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            // Closed onto the field, it fades into it, uncovering what
            // the field holds rather than cutting to it.
            opacity: field == null ? 1 : 1 - _intoField.transform(v),
            child: ClipPath(
              clipper: BandClipper(
                field == null ? screen : RRect.lerp(screen, field, t)!,
              ),
              child: Transform.translate(
                offset: Offset(0, -slide),
                child: const ColoredBox(color: BrandColors.ink),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: box,
          child: Transform.flip(
            flipX: spot?.flipped ?? false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Tevi(
                  size: box.width,
                  assembly: assembly,
                  look: shown,
                  eases: false,
                  searching: _stage == _Stage.waiting && !widget.ready,
                ),
                if (night > 0)
                  Opacity(
                    opacity: night,
                    child: Tevi(
                      size: box.width,
                      look: shown,
                      night: true,
                      eases: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// When, over the hand-off, the ground closed onto a field fades into it.
  static const _intoField = Interval(.6, 1);
}

/// When each part of the opening plays, in ms from its start. The parts
/// overlap, so the figure builds in one movement rather than in steps;
/// the blink closes it, over the mascot's own blink.
abstract final class _Beats {
  static const look = (260.0, 520.0);
  static const eye = (460.0, 660.0);
  static const legs = (500.0, 660.0);
  static const ends = (580.0, 800.0);
  static final blink = (
    (Motion.opening - Motion.blink).inMilliseconds.toDouble(),
    Motion.opening.inMilliseconds.toDouble(),
  );
}

/// The opening at [ms] from its start: the look wipes across, the eye
/// opens and the legs drop, the beak and the tail come out, and the eye
/// blinks once ([_Beats]).
@visibleForTesting
(TeviAssembly, TeviLook) openingAt(double ms) {
  double part((double, double) beat, Curve curve) {
    final (from, to) = beat;
    return curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));
  }

  final blink = part(_Beats.blink, Curves.linear);
  return (
    TeviAssembly(
      look: part(_Beats.look, Motion.wipe),
      eye: part(_Beats.eye, Motion.pop),
      legs: part(_Beats.legs, Motion.settle),
      ends: part(_Beats.ends, Motion.spring),
    ),
    TeviLook(
      lid: Motion.sway.transform(blink < .5 ? blink * 2 : (1 - blink) * 2),
    ),
  );
}
