import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'empty_shelf.dart';

/// The child side's error note: the picture
/// first, the Espiadinha peeking into its hollow screen, as on the empty
/// shelf, then one calm line in ember on dark for the adult nearby. No
/// alarm icon: a pre-reader reads the picture, and the picture is calm.
class KidErrorNote extends StatelessWidget {
  const KidErrorNote(this.message, {super.key, this.picture = 96});

  final String message;

  /// The picture's height.
  final double picture;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const corner = Radius.circular(48 * Radii.screenRatio);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: CustomPaint(
              size: EmptyShelf.size * (picture / EmptyShelf.size.height),
              painter: const EmptyShelfPainter(),
            ),
          ),
          const SizedBox(height: Space.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.errorGround,
              borderRadius: const BorderRadius.all(corner),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: p.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
