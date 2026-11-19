import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// A child's target sinks a little under the finger and comes back up
/// when it lifts, so a small hand feels the press land: down to
/// [PressSink.depthOf] its size over [Motion.press], up over the slower
/// [Motion.release]. Under reduced motion it is a cut.
///
/// Only the picture moves. The target still takes touches where it
/// stood, reads the same and keeps its focus, and a touch the screen is
/// not letting through yet never reaches it, so it does not sink either.
class PressSink extends StatefulWidget {
  const PressSink({super.key, required this.child, this.enabled = true});

  /// How far a large pressed target sinks: to 96 % of its size.
  static const depth = .96;

  /// The least each edge of a small target moves in, so the sink is felt
  /// under a fingertip; 4 % of a key would be under 2 dp.
  static const edge = 3.0;

  /// The deepest any target sinks: past this a press reads as a shrink.
  static const deepest = .9;

  /// How far a target of [size] sinks: to [depth], or deeper on a small
  /// one, so its shorter side gives up at least [edge] at each end.
  static double depthOf(Size size) {
    final side = size.shortestSide;
    if (side <= 0) return depth;
    return math.max(deepest, math.min(depth, 1 - 2 * edge / side));
  }

  final Widget child;

  /// A target that cannot act now does not sink.
  final bool enabled;

  @override
  State<PressSink> createState() => _PressSinkState();
}

class _PressSinkState extends State<PressSink>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: Motion.press,
    reverseDuration: Motion.release,
  );

  late final _sunk = CurvedAnimation(
    parent: _press,
    curve: Motion.settle,
    reverseCurve: Motion.settle.flipped,
  );

  /// The finger holding it down, and where it came down.
  int? _pointer;
  Offset _at = Offset.zero;

  /// How far it sinks, measured as the finger lands.
  double _depth = PressSink.depth;

  bool get _still => MediaQuery.disableAnimationsOf(context);

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _at = event.position;
    if (context.size case final size?) _depth = PressSink.depthOf(size);
    _still ? _press.value = 1 : _press.forward();
  }

  // A finger that slides away is scrolling or changing its mind.
  void _move(PointerMoveEvent event) {
    if (event.pointer == _pointer &&
        (event.position - _at).distance > kTouchSlop) {
      _lift();
    }
  }

  void _end(PointerEvent event) {
    if (event.pointer == _pointer) _lift();
  }

  void _lift() {
    _pointer = null;
    _still ? _press.value = 0 : _press.reverse();
  }

  @override
  void didUpdateWidget(PressSink old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _pointer != null) _lift();
  }

  @override
  void dispose() {
    _sunk.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: AnimatedBuilder(
      animation: _sunk,
      builder: (context, child) => Transform.scale(
        scale: 1 - (1 - _depth) * _sunk.value,
        // Touches land where the target stands, not where it is drawn.
        transformHitTests: false,
        child: child,
      ),
      child: widget.child,
    ),
  );
}
