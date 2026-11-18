import 'package:flutter/material.dart';

import '../access/widgets.dart' show StateModule;
import '../curation/kid_catalog.dart';
import '../design/tokens.dart';
import '../family/avatars.dart' show AvatarColors;
import 'shelves.dart';

/// A pacotinho: its cover in a rounded frame, with a play disc in its
/// corner, and beneath it one hollow module per video, the same modules
/// its player fills. One button, read by its title and its count;
/// nothing written on it.
class PackTile extends StatelessWidget {
  const PackTile({
    super.key,
    required this.pack,
    required this.size,
    required this.thumbnail,
    required this.onTap,
    this.radius,
    this.playDiscScale = 1,
  });

  final KidPack pack;

  /// The cover's size; the modules stand below it.
  final Size size;
  final ThumbnailLoader thumbnail;
  final VoidCallback? onTap;

  /// The cover's corner, as a [VideoTile]'s.
  final double? radius;
  final double playDiscScale;

  /// The modules' height on a tile, and their gap to the cover.
  static const module = 10.0;
  static const below = Space.sm + module;

  static String label(KidPack pack) =>
      VideoTile.label(_named(pack), resting: !pack.fits);

  static String _named(KidPack pack) =>
      '${pack.title}, pacotinho de ${pack.videos.length} vídeos';

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: true,
    label: label(pack),
    onTap: onTap,
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VideoTile(
            // The cover is one of its videos; the tile reads the pack.
            video: KidVideo(
              id: pack.coverVideoId,
              title: _named(pack),
              duration: Duration.zero,
            ),
            size: size,
            thumbnail: thumbnail,
            onTap: onTap,
            radius: radius,
            resting: !pack.fits,
            playDisc: true,
            playDiscScale: playDiscScale,
          ),
          const SizedBox(height: Space.sm),
          PackModules(count: pack.videos.length, filled: 0, height: module),
        ],
      ),
    ),
  );
}

/// A pacotinho's videos counted in state modules: one per video, the
/// first [filled] taken, 4 px apart.
class PackModules extends StatelessWidget {
  const PackModules({
    super.key,
    required this.count,
    required this.filled,
    this.height = 10,
  });

  final int count;
  final int filled;
  final double height;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: Space.xs),
        StateModule(filled: i < filled, height: height),
      ],
    ],
  );
}

/// The pacotinhos' sign: a bundle of three screens, offset like a
/// small stack of telinhas, the front one cream. Drawn on the
/// theme glyphs' 64-unit grid in the avatars' colours, never sun; read
/// "Pacotinhos", never a target.
class PackGlyph extends StatelessWidget {
  const PackGlyph({super.key, this.size = KidSizes.target});

  final double size;

  static const label = 'Pacotinhos';

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: label,
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: PackGlyphPainter()),
    ),
  );
}

class PackGlyphPainter extends CustomPainter {
  const PackGlyphPainter();

  static const grid = 64.0;

  static RRect _screen(Rect r) => RRect.fromRectAndRadius(
    r,
    Radius.circular(r.shortestSide * Radii.screenRatio),
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / grid);
    final ground = Paint()..color = AvatarColors.ground;
    final mist = Paint()..color = AvatarColors.mist;
    final figure = Paint()..color = AvatarColors.figure;
    // Back to front, each screen 40 × 23 (close to 16:9), cut from the one
    // behind by a wide sliver of the ground, so three screens read at 64 dp:
    // two in the mid tone, the front one cream.
    const back = Rect.fromLTWH(18, 6, 40, 23);
    const middle = Rect.fromLTWH(12, 19, 40, 23);
    const front = Rect.fromLTWH(6, 32, 40, 23);
    canvas.drawRRect(_screen(back), mist);
    canvas.drawRRect(_screen(middle.inflate(3.5)), ground);
    canvas.drawRRect(_screen(middle), mist);
    canvas.drawRRect(_screen(front.inflate(3.5)), ground);
    canvas.drawRRect(_screen(front), figure);
  }

  @override
  bool shouldRepaint(PackGlyphPainter old) => false;
}
