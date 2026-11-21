import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// The line under the window: whether the video has played to its end.
const notPlayedToEnd = 'Ainda não tocou até o fim';
const playedToEnd = 'Tocou até o fim';

/// Under the window: "Ainda não tocou até o fim", muted, or the check and
/// "Tocou até o fim" in the text colour, so the state is in words and
/// glyph, never in colour alone; the check grows with the words. It keeps
/// the height of the taller of its two sentences at the width it has, so
/// what stands under it never moves as the state changes. Read as one
/// label, announced when it changes.
class EndLine extends StatelessWidget {
  const EndLine({super.key, required this.ended});

  final bool ended;

  /// The check's size at a text scale of 1.
  static const _check = 20.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final words = ended ? playedToEnd : notPlayedToEnd;
    final scaler = MediaQuery.textScalerOf(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    final check = scaler.scale(_check);
    return Semantics(
      container: true,
      liveRegion: true,
      label: words,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          double height(String words, double room) {
            final line = TextPainter(
              text: TextSpan(text: words, style: style),
              textScaler: scaler,
              textDirection: Directionality.of(context),
            )..layout(maxWidth: room);
            final h = line.height;
            line.dispose();
            return h;
          }

          final tallest = [
            height(notPlayedToEnd, box.maxWidth),
            check,
            height(playedToEnd, box.maxWidth - check - Space.xs),
          ].reduce((a, b) => a > b ? a : b);
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: tallest),
            child: Row(
              children: [
                if (ended) ...[
                  Icon(Icons.check_rounded, size: check, color: p.text),
                  const SizedBox(width: Space.xs),
                ],
                Flexible(
                  child: Text(
                    words,
                    style: style?.copyWith(color: ended ? p.text : p.muted),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
