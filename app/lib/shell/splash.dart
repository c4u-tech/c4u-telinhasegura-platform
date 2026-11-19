import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tevi.dart';
import '../design/tokens.dart';

/// Shown while the app does not yet know who it is in front of:
/// the plain ground, nothing to read
/// or press. Only a failed read of the mode says so and offers
/// "Tentar de novo", which calls [onRetry].
///
/// At the app's start it is the opening instead: the ink ground of the
/// launch screen with [mascot] standing on it.
class Splash extends StatelessWidget {
  const Splash({super.key, this.onRetry, this.mascot});

  final VoidCallback? onRetry;

  /// The opening's mascot, already placed on the screen.
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
            child: ColoredBox(color: BrandColors.ink, child: mascot),
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
/// known ([ready]), the ground lifts away from [child], the first screen,
/// over [Motion.band]. A mode known early waits for the assembly; a mode
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
      _stage = _stage == _Stage.lifting ? _Stage.done : _Stage.waiting;
      _advance();
    });
  }

  /// Moves on from waiting once the mode is known or its read failed.
  void _advance() {
    if (_stage != _Stage.waiting) return;
    if (widget.failed) {
      _stage = _Stage.done;
    } else if (widget.ready) {
      if (_still) {
        _stage = _Stage.done;
      } else {
        _stage = _Stage.lifting;
        _lift.forward();
      }
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cover = switch (_stage) {
      _Stage.done when widget.ready => null,
      _Stage.done => Splash(onRetry: widget.failed ? widget.onRetry : null),
      _Stage.lifting => ExcludeSemantics(
        child: SlideTransition(
          position: _lift.drive(
            Tween(
              begin: Offset.zero,
              end: const Offset(0, -1),
            ).chain(CurveTween(curve: Motion.settle)),
          ),
          child: _ground(),
        ),
      ),
      _ => _ground(),
    };
    final hidden = _stage == _Stage.assembling || _stage == _Stage.waiting;
    // The first screen lies beneath the ground from the moment the mode is
    // known, so it is ready when the ground lifts. Its key keeps it, state
    // and all, when the ground goes and it stands alone, with nothing
    // painted over it.
    final screen = KeyedSubtree(
      key: _screen,
      child: ExcludeSemantics(excluding: hidden, child: widget.child),
    );
    if (!widget.ready) return cover!;
    if (cover == null) return screen;
    return Stack(fit: StackFit.expand, children: [screen, cover]);
  }

  Widget _ground() => Splash(
    mascot: AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final (assembly, look) = _stage == _Stage.assembling
            ? openingAt(_clock.value * Motion.opening.inMilliseconds)
            : (TeviAssembly.whole, TeviLook.watching);
        return _Placed(
          side: Opening.markSide,
          child: Tevi(
            size: Opening.markSide,
            assembly: assembly,
            look: look,
            eases: false,
            searching: _stage == _Stage.waiting && !widget.ready,
          ),
        );
      },
    ),
  );
}

/// The opening at [ms] from its start: the look wipes across (260-520),
/// the eye opens and the legs drop (460-660), the beak and the tail come
/// out (580-800), and the eye blinks once (840-1000).
@visibleForTesting
(TeviAssembly, TeviLook) openingAt(double ms) {
  double part(double from, double to, Curve curve) =>
      curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));
  final blink = part(840, 1000, Curves.linear);
  return (
    TeviAssembly(
      look: part(260, 520, Motion.wipe),
      eye: part(460, 660, Motion.pop),
      legs: part(500, 660, Motion.settle),
      ends: part(580, 800, Motion.spring),
    ),
    TeviLook(
      lid: Motion.sway.transform(blink < .5 ? blink * 2 : (1 - blink) * 2),
    ),
  );
}

/// [child], a mascot's box [side] across, placed so the middle of the
/// figure's drawing sits at the middle of the screen, as the launch
/// screen centres its image.
class _Placed extends StatelessWidget {
  const _Placed({required this.side, required this.child});

  final double side;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomSingleChildLayout(delegate: _CentreDrawing(side), child: child);
}

class _CentreDrawing extends SingleChildLayoutDelegate {
  const _CentreDrawing(this.side);

  final double side;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(Size.square(side));

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      size.center(Offset.zero) - TeviPainter.drawingCentre * side;

  @override
  bool shouldRelayout(_CentreDrawing old) => old.side != side;
}
