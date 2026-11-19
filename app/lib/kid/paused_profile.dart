import 'package:flutter/material.dart';

import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'empty_shelf.dart';

/// The child home of a profile waiting for a guardian to authorize it
/// again: in the pictures' place, the mascot asleep on its wire, as on a
/// day without time, since nothing is for the child to do, and one calm
/// line for the adult nearby. No way out but the exit behind the parents'
/// PIN.
class PausedProfile extends StatelessWidget {
  const PausedProfile({super.key, this.scale = 1, this.pictureKey});

  /// Grows the drawing with the child home's avatar on wide screens.
  final double scale;

  /// The picture's key: the home that shows one resting screen after
  /// another keeps the one mascot, so it falls asleep only once.
  final Key? pictureKey;

  static const line =
      'Este perfil está pausado. Peça a um adulto para abrir o app e '
      'autorizar de novo.';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Grown, the line takes the empty shelf's two type steps up.
    final step = scale > 1 ? text.titleLarge : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShelfPicture(
          key: pictureKey,
          look: TeviLook.asleep,
          perch: Perch.wire,
          scale: scale,
          fallsAsleep: true,
        ),
        const SizedBox(height: Space.lg),
        Semantics(
          liveRegion: true,
          child: Text(
            line,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(
              color: context.palette.muted,
              fontSize: step?.fontSize,
              height: step?.height,
            ),
          ),
        ),
      ],
    );
  }
}
