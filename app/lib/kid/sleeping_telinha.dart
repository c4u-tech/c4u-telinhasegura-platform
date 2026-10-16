import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../screentime/kid_time.dart';
import 'empty_shelf.dart';

/// The child home's day without time: in the empty shelf's place, the Espiadinha peeking into its
/// hollow screen with its eyes closed, and one muted line. No minutes, no
/// counter: the picture says the day is done, and the line is all
/// assistive technology reads.
class SleepingTelinha extends StatelessWidget {
  const SleepingTelinha({super.key, required this.state, this.scale = 1});

  /// [KidTimeState.timeUp] or [KidTimeState.outsideWindow].
  final KidTimeState state;

  /// Grows the drawing with the child home's avatar on wide screens.
  final double scale;

  static const timeUp = 'Acabou por hoje';

  /// Before the window or after it: the app cannot tell them apart.
  static const outsideWindow = 'Agora não é hora';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Grown, the line takes the empty shelf's two type steps up.
    final step = scale > 1 ? text.titleLarge : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: CustomPaint(
            size: EmptyShelf.size * scale,
            painter: const EmptyShelfPainter(asleep: true),
          ),
        ),
        const SizedBox(height: Space.lg),
        Text(
          state == KidTimeState.outsideWindow ? outsideWindow : timeUp,
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(
            color: context.palette.muted,
            fontSize: step?.fontSize,
            height: step?.height,
          ),
        ),
      ],
    );
  }
}
