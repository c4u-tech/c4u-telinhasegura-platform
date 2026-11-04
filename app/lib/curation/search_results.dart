import 'package:flutter/material.dart';

import '../catalog/video_row.dart' show VideoThumb;
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../kid/shelves.dart' show ThumbnailLoader;
import '../kid_mode/kid_mode_door.dart' show StateLine;
import 'curation.dart';
import 'search_result.dart';
import 'words.dart';

/// Over the results: they are YouTube's, said in words rather than a logo.
const resultsLabel = 'Resultados do YouTube';

/// A search that found nothing.
const noResults =
    'Não achamos vídeos com essas palavras. Tente outras ou cole o link.';

/// A hit already in the catalogue, which can still be suggested.
const inCatalog = 'Já está no catálogo';

/// A hit the curators already have, pending or held.
const inReview = 'Em revisão';

/// What assistive technology hears when [n] results arrive.
String foundWords(int n) =>
    n == 1 ? '1 vídeo encontrado' : '$n vídeos encontrados';

/// A hit's length, as every video length is worded.
String resultLength(SearchResult r) =>
    CurationWords.duration(Duration(seconds: r.durationSeconds));

/// Where a hit stands, in words: why it cannot be suggested, or that the
/// catalogue already has it; null for a video nobody suggested yet.
String? resultState(SearchResult r) {
  if (!r.suggestible) return RefusalReason.parse(r.refusal).message;
  return switch (VideoState.parse(r.state)) {
    VideoState.approved => inCatalog,
    VideoState.pending || VideoState.held => inReview,
    _ => null,
  };
}

/// The results of one title search, in the order YouTube gave them, under
/// their attribution: door rows a guardian taps to confirm a video. A hit
/// that cannot be suggested stays in its place with its reason, and is no
/// target.
class SearchResults extends StatelessWidget {
  const SearchResults({
    super.key,
    required this.results,
    required this.thumbnail,
    required this.onPick,
  });

  final List<SearchResult> results;
  final ThumbnailLoader thumbnail;
  final ValueChanged<SearchResult> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(resultsLabel, style: text.titleMedium),
        ),
        const SizedBox(height: Space.md),
        if (results.isEmpty)
          Text(noResults, style: text.bodyLarge)
        else
          Doors(
            children: [
              for (final r in results)
                SearchResultRow(
                  key: ValueKey(r.youtubeId),
                  result: r,
                  thumbnail: thumbnail,
                  onTap: r.suggestible ? () => onPick(r) : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// One hit: the thumbnail as a cue, the title in at most two lines,
/// "Canal · 3 min" muted, then where it stands on its own line. Read as
/// one label, "título, canal, duração, estado".
class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    super.key,
    required this.result,
    required this.thumbnail,
    required this.onTap,
  });

  final SearchResult result;
  final ThumbnailLoader thumbnail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    final state = resultState(r);
    return DoorRow(
      title: r.title,
      titleMaxLines: 2,
      semanticsLabel: [
        r.title,
        r.channelTitle,
        resultLength(r),
        ?state,
      ].join(', '),
      leading: VideoThumb(videoId: r.youtubeId, thumbnail: thumbnail),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CurationWords.joined([r.channelTitle, resultLength(r)]),
            style: muted,
          ),
          if (state != null) ...[
            const SizedBox(height: Space.xs),
            // A refusal is a sentence, read whole; a stored video's state
            // keeps the catalogue's module beside its words.
            if (r.suggestible)
              StateLine(filled: state == inCatalog, words: state)
            else
              Text(state, style: muted),
          ],
        ],
      ),
    );
  }
}
