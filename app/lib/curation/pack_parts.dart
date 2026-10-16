import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import 'curation.dart';
import 'pack.dart';
import 'pack_words.dart';
import 'words.dart';

/// A pacotinho's video no longer in the catalogue: every child skips it.
const outOfCatalogue = 'Fora do catálogo agora';

/// What a pacotinho's numbered video line shows under its title:
/// "Canal · 4 min", and "Fora do catálogo agora" when it is not approved.
String packVideoMeta(PackVideo v) => CurationWords.joined([
  if (v.channelTitle.isNotEmpty) v.channelTitle,
  CurationWords.duration(v.duration),
  if (v.state != VideoState.approved) outOfCatalogue,
]);

/// The total under a pacotinho's videos: "Total: 12 min".
String packTotal(Pack p) => 'Total: ${CurationWords.duration(p.total)}';

/// One video of a pacotinho, numbered in its order: "2. Sapo Cururu",
/// then "Canal · 4 min" muted. A door to watch it when [onTap] is given
/// (the review), a read line otherwise (the admin).
class PackVideoLine extends StatelessWidget {
  const PackVideoLine({
    super.key,
    required this.position,
    required this.video,
    this.onTap,
  });

  /// From 1.
  final int position;
  final PackVideo video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = '$position. ${video.title}';
    final meta = packVideoMeta(video);
    final muted = Text(
      meta,
      style: text.bodyMedium?.copyWith(color: context.palette.muted),
    );
    if (onTap case final tap?) {
      return DoorRow(
        title: title,
        titleMaxLines: 2,
        semanticsLabel: '$title, $meta',
        onTap: tap,
        child: muted,
      );
    }
    return ReadLine(
      label: '$title, $meta',
      children: [
        Text(title, style: text.bodyLarge),
        const SizedBox(height: Space.xs),
        muted,
      ],
    );
  }
}

/// One review of a pacotinho's round, read and never a target:
/// "Pedagogo(a) aprovou", a refusal's reason on its own line.
class PackReviewLine extends StatelessWidget {
  const PackReviewLine(this.review, {super.key});

  final PackReview review;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final line = PackWords.review(review);
    final reason = review.decision == ReviewDecision.reject
        ? review.reason?.trim()
        : null;
    final hasReason = reason != null && reason.isNotEmpty;
    return ReadLine(
      label: hasReason ? '$line, $reason' : line,
      children: [
        Text(line, style: text.bodyLarge),
        if (hasReason) ...[
          const SizedBox(height: Space.xs),
          Text(reason, style: text.bodyMedium),
        ],
      ],
    );
  }
}

/// A read line between hairlines: one semantics node of [label], at
/// least 48 dp tall.
class ReadLine extends StatelessWidget {
  const ReadLine({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );
}
