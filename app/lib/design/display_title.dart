import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A display title that breaks only between words. At large text sizes it
/// keeps the reader's scale whenever its longest word fits the column, and
/// shrinks only as far as that word needs otherwise: never clipped, never
/// cut short, never split inside a word ("Aparelho / s"). An address set
/// with `addressBreaks` may break at its marks, so each piece between
/// them counts as a word, never the whole address.
class DisplayTitle extends StatelessWidget {
  const DisplayTitle(this.text, {super.key, this.style, this.semanticsLabel});

  final String text;

  /// What assistive technology reads instead of [text], when the shown
  /// text carries break marks (an address set with `addressBreaks`).
  final String? semanticsLabel;

  /// The display face by default.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? Theme.of(context).textTheme.displaySmall;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, box) => Text(
        text,
        style: style,
        semanticsLabel: semanticsLabel,
        textScaler: fitWords(text, style, scaler, box.maxWidth, direction),
      ),
    );
  }
}

/// The scale at which every word of [text] fits [width], a word ending at
/// a space or at a zero-width break (U+200B): [scaler] itself
/// when its longest word already fits, else the largest linear scale
/// below it that fits.
TextScaler fitWords(
  String text,
  TextStyle? style,
  TextScaler scaler,
  double width,
  TextDirection direction,
) {
  if (!width.isFinite) return scaler;
  final size = style?.fontSize ?? 14;
  double widest(TextScaler at) {
    var widest = 0.0;
    for (final word in text.split(RegExp('[ \u200B]'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: direction,
        textScaler: at,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  final measured = widest(scaler);
  if (measured <= width) return scaler;
  // Width grows with the scale almost linearly; the loop takes up what
  // rounding and tracking leave over.
  var factor = scaler.scale(size) / size * width / measured;
  while (factor > 0.01 && widest(TextScaler.linear(factor)) > width) {
    factor *= 0.98;
  }
  return TextScaler.linear(factor);
}
