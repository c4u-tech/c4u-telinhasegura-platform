import 'package:flutter/material.dart';

import '../access/widgets.dart' show StateModule;
import '../curation/kid_catalog.dart';
import '../design/tokens.dart';
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
    this.color,
  });

  final int count;
  final int filled;
  final double height;

  /// The modules' one colour, off the kid ground.
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: Space.xs),
        StateModule(filled: i < filled, height: height, color: color),
      ],
    ],
  );
}

/// The pacotinhos' sign: a bundle of three screens, offset like a
/// small stack of telinhas. Drawn on the theme glyphs' 64-unit grid in
/// one [color], as they are (the home's cream by default), never sun;
/// read "Pacotinhos", never a target.
class PackGlyph extends StatelessWidget {
  const PackGlyph({super.key, this.size = KidSizes.target, this.color});

  final double size;
  final Color? color;

  static const label = 'Pacotinhos';

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: label,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: PackGlyphPainter(color: color)),
    ),
  );
}

class PackGlyphPainter extends CustomPainter {
  const PackGlyphPainter({this.color});

  final Color? color;

  static const grid = 64.0;

  static RRect _screen(Rect r) => RRect.fromRectAndRadius(
    r,
    Radius.circular(r.shortestSide * Radii.screenRatio),
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(size.shortestSide / grid);
    final figure = Paint()..color = color ?? ColourWorlds.home.figure;
    // Cuts through to whatever lies beneath.
    final cut = Paint()..blendMode = BlendMode.clear;
    // Back to front, each screen 36 × 20 (16:9), parted from the
    // one behind by a wide cut, so three screens read even at 24 dp.
    const back = Rect.fromLTWH(20, 8, 36, 20);
    const middle = Rect.fromLTWH(14, 20, 36, 20);
    const front = Rect.fromLTWH(8, 32, 36, 20);
    canvas.drawRRect(_screen(back), figure);
    canvas.drawRRect(_screen(middle.inflate(4)), cut);
    canvas.drawRRect(_screen(middle), figure);
    canvas.drawRRect(_screen(front.inflate(4)), cut);
    canvas.drawRRect(_screen(front), figure);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PackGlyphPainter old) => old.color != color;
}
