import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// The line under the window: whether the video has played to its end.
const notPlayedToEnd = 'Ainda não tocou até o fim';
const playedToEnd = 'Tocou até o fim';

/// Under the window: "Ainda não tocou até o fim", muted, or the check and
/// "Tocou até o fim" in the text colour, so the state is in words and
/// glyph, never in colour alone. Read as one label, announced when it
/// changes.
class EndLine extends StatelessWidget {
  const EndLine({super.key, required this.ended});

  final bool ended;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final words = ended ? playedToEnd : notPlayedToEnd;
    return Semantics(
      container: true,
      liveRegion: true,
      label: words,
      excludeSemantics: true,
      child: Row(
        children: [
          if (ended) ...[
            Icon(Icons.check_rounded, size: 20, color: p.text),
            const SizedBox(width: Space.xs),
          ],
          Flexible(
            child: Text(
              words,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: ended ? p.text : p.muted),
            ),
          ),
        ],
      ),
    );
  }
}
