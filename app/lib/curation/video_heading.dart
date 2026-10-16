import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'curation.dart';
import 'words.dart';

/// The video a curation screen is about, under its display title: the
/// title in title-medium, whole, then "Canal · 4 min" muted, with
/// [more] after the length ("Rodada 2" on the review). The review, the
/// approval, the refusal and the held video name it the same way, so a
/// curator sees what they decide on the screen that commits it.
class VideoHeading extends StatelessWidget {
  VideoHeading(Video video, {super.key, this.more = const []})
    : title = video.title,
      channelTitle = video.channelTitle,
      duration = video.duration;

  /// A video known by its parts: the family catalogue's.
  const VideoHeading.parts({
    super.key,
    required this.title,
    required this.channelTitle,
    required this.duration,
    this.more = const [],
  });

  final String title;
  final String channelTitle;
  final Duration duration;
  final List<String> more;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.titleMedium),
        const SizedBox(height: Space.xs),
        Text(
          CurationWords.joined([
            channelTitle,
            CurationWords.duration(duration),
            ...more,
          ]),
          style: text.bodyMedium?.copyWith(color: context.palette.muted),
        ),
      ],
    );
  }
}
