import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Something under way: the platform's spinning ring, or, where the
/// platform asks for reduced motion, a still partial ring. Assistive
/// technology reads it the same either way, as a spinner with no value.
class BusyRing extends StatelessWidget {
  const BusyRing({super.key, this.strokeWidth, this.color});

  /// How much of the still ring is drawn: enough to read as a ring under
  /// way rather than an empty one or a full one.
  static const stillPart = .25;

  final double? strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return CircularProgressIndicator(strokeWidth: strokeWidth, color: color);
    }
    // A ring with a value would be read as a progress bar at 25 %, which
    // is not what it says: it keeps the spinner's reading.
    return Semantics(
      role: SemanticsRole.loadingSpinner,
      child: ExcludeSemantics(
        child: CircularProgressIndicator(
          value: stillPart,
          strokeWidth: strokeWidth,
          color: color,
        ),
      ),
    );
  }
}
