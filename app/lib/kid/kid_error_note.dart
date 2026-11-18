import 'package:flutter/material.dart';

import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'empty_shelf.dart';

/// The child side's error note: the picture
/// first, the mascot on its hollow screen with its crest raised, as on the
/// empty shelf but surprised, then one calm line in ember on dark for the
/// adult nearby. No alarm icon: a pre-reader reads the picture, and the
/// picture is calm.
///
/// Asleep, nothing went wrong: the video is only longer than the time left.
/// The mascot sleeps on its wire, as on the day without time, and the
/// line is the sleeping telinha's muted one, with no error ground, so a
/// child who cannot read yet sees "not now", not "broken".
class KidErrorNote extends StatelessWidget {
  const KidErrorNote(
    this.message, {
    super.key,
    this.picture = 96,
    this.asleep = false,
  });

  final String message;

  /// The mascot asleep and the line calm: "not now".
  final bool asleep;

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
          ShelfPicture(
            look: asleep ? TeviLook.asleep : TeviLook.crestUp,
            perch: asleep ? Perch.wire : Perch.screen,
            scale: picture / ShelfPicture.size.height,
          ),
          const SizedBox(height: Space.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: asleep ? null : p.errorGround,
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
                    ?.copyWith(color: asleep ? p.muted : p.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
