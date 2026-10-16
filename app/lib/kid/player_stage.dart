import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The player's composition: a 16:9 window under the child frame's strip, its keys
/// outside it, in a strip beneath it (portrait) or a rail beside it
/// (landscape). A pacotinho's [progress] sits between the window and the
/// strip, or at the top of the rail. The window is whatever [window]
/// builds at the size given: the embed, whole, or what stands in its
/// place.
class PlayerStage extends StatelessWidget {
  const PlayerStage({
    super.key,
    required this.window,
    required this.back,
    this.toggle,
    this.progress,
    this.bare = false,
  });

  final Widget Function(Size size) window;
  final Widget back;

  /// The one filled key; null leaves its place empty.
  final Widget? toggle;

  final Widget? progress;

  /// Fullscreen: the window alone, centred, as large as the space allows
  /// at 16:9; no keys, no progress (fullscreen design).
  final bool bare;

  /// The widest the player grows.
  static const maxWidth = 960.0;

  /// A pacotinho's modules in the player, and the room they take.
  static const module = 16.0;
  static const _progressRoom = module + Space.lg;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (bare) {
        final width = math.min(box.maxWidth, box.maxHeight * 16 / 9);
        return Center(child: this.window(Size(width, width * 9 / 16)));
      }
      // Landscape puts the keys in a rail beside the player.
      final rail = box.maxWidth > box.maxHeight;
      const keys = KidSizes.target + 2 * Space.lg;
      final below = keys + (progress == null ? 0 : _progressRoom);
      final width = [
        maxWidth,
        rail ? box.maxWidth - keys - Space.xl : box.maxWidth,
        (rail ? box.maxHeight - 2 * Space.lg : box.maxHeight - below) * 16 / 9,
      ].reduce(math.min);
      final size = Size(width, width * 9 / 16);
      final window = this.window(size);
      if (rail) {
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              window,
              const SizedBox(width: Space.lg),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (progress case final progress?) ...[
                    progress,
                    const SizedBox(height: Space.lg),
                  ],
                  back,
                  const SizedBox(height: Space.lg),
                  // Every slot keeps its room when empty, so nothing moves
                  // under the child's hand between states.
                  toggle ?? const SizedBox.square(dimension: KidSizes.target),
                ],
              ),
            ],
          ),
        );
      }
      // Portrait: the window right under the top strip, the strip under
      // it: back at the start, play/pause on the window's centre line, the
      // end empty (no YouTube logo, fullscreen design).
      return Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            window,
            const SizedBox(height: Space.lg),
            if (progress case final progress?) ...[
              progress,
              const SizedBox(height: Space.lg),
            ],
            SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: back,
                      ),
                    ),
                    toggle ?? const SizedBox.square(dimension: KidSizes.target),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
