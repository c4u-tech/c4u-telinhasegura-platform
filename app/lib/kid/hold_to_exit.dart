import 'dart:math' as math;
import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// The child side's only control: an icon in a top
/// corner that exits only after a continuous 2-second press, its ring
/// filling as it goes; releasing early empties it. Friction for small
/// hands, not security: the PIN after it is the barrier. Assistive
/// technology cannot hold, so it gets a long-press action that exits at
/// once.
class HoldToExit extends StatefulWidget {
  const HoldToExit({super.key, required this.onExit});

  static const label = 'Sair do modo criança';
  static const hold = Duration(seconds: 2);

  final VoidCallback onExit;

  @override
  State<HoldToExit> createState() => _HoldToExitState();
}

class _HoldToExitState extends State<HoldToExit>
    with SingleTickerProviderStateMixin {
  // The ring is feedback, not decoration: it fills over the full 2 s
  // even under reduced motion, never shortened by the platform.
  late final _ring = AnimationController(
    vsync: this,
    duration: HoldToExit.hold,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_done);

  bool _focused = false;

  void _done(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _ring.value = 0;
      widget.onExit();
    }
  }

  void _press() => _ring.forward(from: 0);

  void _release() {
    _ring.stop();
    _ring.value = 0;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    switch (event) {
      case KeyDownEvent():
        _press();
      case KeyUpEvent():
        _release();
      case _:
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      button: true,
      label: HoldToExit.label,
      onLongPress: widget.onExit,
      child: ExcludeSemantics(
        child: Focus(
          onKeyEvent: _onKey,
          onFocusChange: (on) {
            if (!on) _release();
            setState(() => _focused = on);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _press(),
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: SizedBox.square(
              dimension: KidSizes.target,
              child: AnimatedBuilder(
                animation: _ring,
                builder: (context, _) => CustomPaint(
                  painter: ExitRingPainter(
                    progress: _ring.value,
                    track: p.outline,
                    fill: p.action,
                    focus: _focused ? p.muted : null,
                  ),
                  child: Center(
                    child: CustomPaint(
                      size: const Size.square(32),
                      painter: ExitGlyphPainter(color: p.outline),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring around the exit control: empty at rest, filling clockwise
/// from the top while held.
class ExitRingPainter extends CustomPainter {
  ExitRingPainter({
    required this.progress,
    required this.track,
    required this.fill,
    this.focus,
  });

  final double progress;
  final Color track;
  final Color fill;

  /// The keyboard focus ring's colour, when focused.
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    if (focus case final focus?) {
      canvas.drawCircle(
        center,
        size.shortestSide / 2 - 1.5,
        Paint()
          ..color = focus
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (progress <= 0) return;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, stroke..color = track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      stroke..color = fill,
    );
  }

  @override
  bool shouldRepaint(ExitRingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.fill != fill ||
      old.focus != focus;
}

/// The exit glyph, from the Espiadinha's vocabulary: the mark's screen
/// (58 × 33, corner at 10/33 of its height) with an arrow leaving it
/// through its side. No lock, shield or door.
class ExitGlyphPainter extends CustomPainter {
  ExitGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 32;
    canvas.scale(u);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const w = 20.0, h = w * 33 / 58;
    const top = 16 - h / 2;
    // The screen, open where the arrow leaves it.
    canvas.save();
    canvas.clipRect(
      const Rect.fromLTRB(21, 16 - 3.5, 23, 16 + 3.5),
      clipOp: ClipOp.difference,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, top, w, h),
        const Radius.circular(h * Radii.screenRatio),
      ),
      line,
    );
    canvas.restore();
    canvas.drawPath(
      Path()
        ..moveTo(13, 16)
        ..lineTo(29, 16)
        ..moveTo(24.5, 11.5)
        ..lineTo(29, 16)
        ..lineTo(24.5, 20.5),
      line,
    );
  }

  @override
  bool shouldRepaint(ExitGlyphPainter old) => old.color != color;
}
