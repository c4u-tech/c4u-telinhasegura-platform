import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../curation/family_catalog.dart';
import '../curation/words.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../kid/shelves.dart' show HollowThumbnail, ThumbnailLoader;
import '../kid_mode/kid_mode_door.dart' show StateLine;

/// One video of a child's catalogue as a guardian reads it:
/// a door row led by the picture the child taps,
/// then its title in at most two lines and "Canal · 6 min", with a
/// hollow state module and "Escondido para Lia" under it when
/// hidden for [nickname]. The whole row is one target,
/// read by its words; the thumbnail is not read on its own.
class VideoRow extends StatelessWidget {
  const VideoRow({
    super.key,
    required this.video,
    required this.nickname,
    required this.thumbnail,
    required this.onTap,
  });

  final FamilyVideo video;
  final String nickname;
  final ThumbnailLoader thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = [video.channelTitle, CurationWords.duration(video.duration)];
    final large = rowTextIsLarge(context);
    return DoorRow(
      title: video.title,
      titleMaxLines: large ? 4 : 2,
      semanticsLabel: [
        video.title,
        CurationWords.tight(parts),
        if (video.hidden) 'escondido para $nickname',
      ].join(', '),
      leading: large
          ? null
          : VideoThumb(videoId: video.id, thumbnail: thumbnail),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RowMeta(lead: video.channelTitle, length: parts.last),
          // Hidden is a state: a hollow module and its words, on their own
          // line, never a faded row (2026-10-06).
          if (video.hidden) ...[
            const SizedBox(height: Space.xs),
            StateLine(filled: false, words: 'Escondido para $nickname'),
          ],
        ],
      ),
    );
  }
}

/// A row's muted line, "Canal · 6 min", its dot glued to both neighbours
/// so no line ends or opens on it. When the length and the word before it
/// cannot share one line (large text in a narrow column), the length takes
/// a line of its own, whole and without the dot, instead of breaking
/// inside a word.
class RowMeta extends StatelessWidget {
  const RowMeta({super.key, required this.lead, required this.length});

  final String lead;
  final String length;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    return LayoutBuilder(
      builder: (context, box) {
        final last = lead.split(' ').last;
        final chunk = TextPainter(
          text: TextSpan(
            text: '$last${CurationWords.tightDot}$length',
            style: style,
          ),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final fits = chunk.width <= box.maxWidth;
        chunk.dispose();
        return Text(
          fits ? CurationWords.tight([lead, length]) : '$lead\n$length',
          style: style,
        );
      },
    );
  }
}

/// Whether the text is set at 1.5 times or more: a row led by a picture
/// then drops it and lets its title take up to four lines, since the
/// picture would leave the title a word per line, and the row is read by
/// its words.
bool rowTextIsLarge(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;

/// The thumbnail at 96 × 54, the screen at 16:9 cornered at 10/33 of its
/// height; while it loads, or if it never comes, the same screen hollow.
class VideoThumb extends StatefulWidget {
  const VideoThumb({super.key, required this.videoId, required this.thumbnail});

  final String videoId;
  final ThumbnailLoader thumbnail;

  static const size = Size(96, 54);

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  late final Future<Uint8List> _bytes = widget.thumbnail(widget.videoId);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: VideoThumb.size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(
        VideoThumb.size.height * Radii.screenRatio,
      ),
      child: FutureBuilder(
        future: _bytes,
        builder: (context, snap) => switch (snap) {
          AsyncSnapshot(hasData: true, :final data!) => Image.memory(
            data,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const HollowThumbnail(),
          ),
          _ => const HollowThumbnail(),
        },
      ),
    ),
  );
}
