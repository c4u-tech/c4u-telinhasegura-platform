import 'package:flutter/material.dart';

import '../curation/family_catalog.dart';
import '../curation/words.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../kid/shelves.dart' show ThumbnailLoader;
import '../kid_mode/kid_mode_door.dart' show StateLine;
import 'video_row.dart' show VideoThumb;
import 'words.dart';

/// One of today's pacotinhos on a child's catalogue:
/// a door row led by its cover, its title,
/// and the count and length of what plays for [nickname]. The whole row
/// is one target, read as a pacotinho.
class PackRow extends StatelessWidget {
  const PackRow({
    super.key,
    required this.pack,
    required this.nickname,
    required this.thumbnail,
    required this.onTap,
  });

  final FamilyPack pack;
  final String nickname;
  final ThumbnailLoader thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = CatalogWords.packCount(pack, nickname);
    return DoorRow(
      title: pack.title,
      titleMaxLines: 2,
      semanticsLabel: '${pack.title}, pacotinho, $count',
      leading: VideoThumb(videoId: pack.coverVideoId, thumbnail: thumbnail),
      onTap: onTap,
      child: Text(
        count,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.muted),
      ),
    );
  }
}

/// One video of a pacotinho in its order, read and never a target:
/// its thumbnail, "2. Título" and its length, with a hollow state
/// module and "Fica de fora para Lia" under them when it is skipped for
/// [nickname]. The row nobody acts on: no chevron.
class PackVideoRow extends StatelessWidget {
  const PackVideoRow({
    super.key,
    required this.position,
    required this.video,
    required this.nickname,
    required this.thumbnail,
  });

  /// From 1.
  final int position;
  final FamilyPackVideo video;
  final String nickname;
  final ThumbnailLoader thumbnail;

  @override
  Widget build(BuildContext context) {
    final title = '$position. ${video.title}';
    final length = CurationWords.duration(video.duration);
    final skipped = CatalogWords.packSkipped(nickname);
    return DoorRow(
      title: title,
      titleMaxLines: 2,
      semanticsLabel: [
        title,
        length,
        if (video.hidden) 'fica de fora para $nickname',
      ].join(', '),
      leading: VideoThumb(videoId: video.id, thumbnail: thumbnail),
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            length,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
          // Skipped is a state: a hollow module and its words on their own
          // line, never a faded row.
          if (video.hidden) ...[
            const SizedBox(height: Space.xs),
            StateLine(filled: false, words: skipped),
          ],
        ],
      ),
    );
  }
}
