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
