import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tevi.dart';
import '../design/tokens.dart';

/// The player's composition: a 16:9 window under the child frame's strip, its keys
/// outside it, in a strip beneath it (portrait) or a rail beside it
/// (landscape). A pacotinho's [progress] sits between the window and the
/// strip, or at the top of the rail. The mascot keeps the child company
/// from a thin wire at the keys' foot, beside them and never near the
/// window. The window is whatever [window] builds at the size given: the
/// embed, whole, or what stands in its place.
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

  /// The one filled key, [PlayerStage.toggleSize] across; null leaves its
  /// place empty.
  final Widget? toggle;

  final Widget? progress;

  /// Fullscreen: the window alone, centred, as large as the space allows
  /// at 16:9; no keys, no progress (fullscreen design).
  final bool bare;

  /// The widest the player grows.
  static const maxWidth = 960.0;

  /// The play/pause key: the largest target on the screen, the one the
  /// child reaches for most.
  static const toggleSize = 88.0;

  /// A pacotinho's modules in the player, and the room they take.
  static const module = 16.0;
  static const _progressRoom = module + Space.lg;

  /// The keys' row, upright, down to the wire beneath it.
  static const _keys = toggleSize + PlayerPerch.drop + PlayerPerch.stroke;

  /// The rail: the play/pause key and its air on both sides, or the
  /// modules of a pacotinho of five, the most one holds, if wider.
  static final _rail = math.max(
    toggleSize + 2 * Space.lg,
    5 * module * Proportions.screen + 4 * Space.xs,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (bare) {
        final width = math.min(box.maxWidth, box.maxHeight * 16 / 9);
        return Center(child: this.window(Size(width, width * 9 / 16)));
      }
      // Landscape puts the keys in a rail beside the player.
      final rail = box.maxWidth > box.maxHeight;
      final below =
          Space.lg + _keys + Space.lg + (progress == null ? 0 : _progressRoom);
      final width = [
        maxWidth,
        rail ? box.maxWidth - _rail - Space.xl : box.maxWidth,
        (rail ? box.maxHeight - 2 * Space.lg : box.maxHeight - below) * 16 / 9,
      ].reduce(math.min);
      final size = Size(width, width * 9 / 16);
      final window = this.window(size);
      // Every slot keeps its room when empty, so nothing moves under the
      // child's hand between states.
      final toggle =
          this.toggle ??
          const SizedBox.square(dimension: PlayerStage.toggleSize);
      if (rail) {
        final keys =
            (progress == null ? 0 : _progressRoom) +
            KidSizes.target +
            Space.lg +
            PlayerStage.toggleSize;
        // The mascot joins the rail where the screen has the height.
        final perched = box.maxHeight >= keys + Space.lg + PlayerPerch.height;
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              window,
              const SizedBox(width: Space.lg),
              SizedBox(
                width: _rail,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (progress case final progress?) ...[
                      FittedBox(fit: BoxFit.scaleDown, child: progress),
                      const SizedBox(height: Space.lg),
                    ],
                    back,
                    const SizedBox(height: Space.lg),
                    toggle,
                    if (perched) ...[
                      const SizedBox(height: Space.lg),
                      SizedBox(
                        height: PlayerPerch.height,
                        child: const PlayerPerch(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }
      // Portrait: the window right under the top strip, the strip under
      // it: back at the start, play/pause on the window's centre line, the
      // mascot at the end on the wire beneath them (no YouTube logo,
      // fullscreen design).
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              window,
              const SizedBox(height: Space.lg),
              if (progress case final progress?) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Space.xl),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: progress,
                  ),
                ),
                const SizedBox(height: Space.lg),
              ],
              SizedBox(
                height: _keys,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(child: PlayerPerch(end: Space.xl)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      child: SizedBox(
                        height: PlayerStage.toggleSize,
                        child: Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: back,
                              ),
                            ),
                            toggle,
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A thin wire along this box's foot and the mascot standing on it in
/// the colours of the ground below, watching: at [end] from the end side,
/// or in the middle when [end] is null. Where the box is too narrow to
/// hold the figure clear of what stands beside it, only the wire shows.
class PlayerPerch extends StatelessWidget {
  const PlayerPerch({super.key, this.end});

  final double? end;

  /// The mascot's box.
  static const size = 72.0;

  /// The wire's width, and how far below the keys it runs.
  static const stroke = 2.0;
  static const drop = Space.md;

  /// The room the figure takes from the top of its body down to the
  /// wire, the wire included.
  static double get height =>
      size * (TeviPainter.perchY - TeviPainter.body.top) -
      TeviPainter.perchOverlap +
      stroke;

  /// From the tail's tip to the beak's, as fractions of the figure's box.
  static const _tail = (3.70 + 6) / 132;
  static const _beak = (115.03 + 6) / 132;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wire = box.maxHeight - stroke;
      final reach = size * (_beak - _tail);
      final inset = end;
      // Upright, the figure stays clear of the middle, where play/pause
      // stands.
      final room = inset == null
          ? box.maxWidth >= reach
          : box.maxWidth / 2 - PlayerStage.toggleSize / 2 - Space.md >=
                inset + reach;
      // The beak ends [end] from the box's end; centred, the figure's
      // reach is.
      final start = inset == null
          ? (box.maxWidth - reach) / 2 - size * _tail
          : box.maxWidth - inset - size * _beak;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: wire,
            height: stroke,
            child: const ColoredBox(color: BrandColors.ink),
          ),
          if (room)
            PositionedDirectional(
              start: start,
              top: wire + TeviPainter.perchOverlap - size * TeviPainter.perchY,
              width: size,
              height: size,
              child: Transform.flip(
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: Tevi(size: size, night: TeviGround.nightAt(context)),
              ),
            ),
        ],
      );
    },
  );
}
