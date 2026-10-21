import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'adult_window.dart';
import 'curation.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'video_heading.dart';
import 'words.dart';

/// A round nobody has reviewed yet.
const noReviews = 'Ninguém revisou nesta rodada ainda.';

/// In the window's place when the player could not play the video:
/// the doors stay, since a video that no longer plays may still
/// be refused.
const playerFailed =
    'Esse vídeo não abriu aqui. Se ele não passa mais, você pode recusá\u2011lo.';

/// `/curadoria/:id`: "O que já disseram, depois o vídeo".
/// The video's title, "Canal · 4 min · Rodada 2" and,
/// on a revisit, since when it is in the catalogue; this round's reviews
/// by displayed role, never by person; then the player, whole in a
/// square-edged 16:9 window at the column's width, loaded without
/// playing, with YouTube's own controls and nothing of ours over it;
/// then the doors "Aprovar" and "Recusar". The player pauses beneath a
/// decision and goes when the curator leaves.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.id});

  final String id;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> with AdultWindow {
  bool _started = false;
  VideoDetail? _detail;
  bool _failed = false;
  GoRouter? _router;
  bool _away = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    _router = GoRouter.of(context)..routerDelegate.addListener(_where);
    scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_where);
    super.dispose();
  }

  /// A decision opened above: the video waits, paused, beneath it.
  void _where() {
    final here =
        _router?.routerDelegate.currentConfiguration.uri.path ==
        Routes.review(widget.id);
    if (!here && !_away) unawaited(playback?.pause());
    _away = !here;
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final detail = await AppScope.of(context).curation.video(widget.id);
      if (!mounted) return;
      setState(() => _detail = detail);
      openPlayer(detail.video.youtubeId);
    } on Object catch (e) {
      if (!mounted || leaveForQueue(context, e)) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => FieldLayout(
    title: 'Revisar',
    onBack: () => context.go(Routes.curation),
    children: _body(),
  );

  List<Widget> _body() {
    final detail = _detail;
    if (detail == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o vídeo')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final v = detail.video;
    return [
      VideoHeading(v, more: ['Rodada ${v.round}']),
      if (_revisit(v) case final revisit?) ...[
        const SizedBox(height: Space.xs),
        Text(revisit, style: muted),
      ],
      const SizedBox(height: Space.xl),
      if (detail.reviews.isEmpty)
        Text(noReviews, style: text.bodyLarge)
      else
        Doors(children: [for (final r in detail.reviews) _ReviewLine(r)]),
      const SizedBox(height: Space.xl),
      playerWindow(failed: playerFailed),
      const SizedBox(height: Space.xl),
      Doors(
        children: [
          DoorRow(
            title: 'Aprovar',
            semanticsLabel: 'Aprovar, Responder às perguntas',
            onTap: () => context.go(Routes.approve(widget.id), extra: v),
            child: Text('Responder às perguntas', style: muted),
          ),
          DoorRow(
            title: 'Recusar',
            semanticsLabel: 'Recusar, Marcar o que aparece',
            onTap: () => context.go(Routes.refuse(widget.id), extra: v),
            child: Text('Marcar o que aparece', style: muted),
          ),
        ],
      ),
    ];
  }

  /// A published video back for its revisit: since when it is in the
  /// catalogue, by its latest publication.
  static String? _revisit(Video v) {
    if (v.state != VideoState.approved) return null;
    final since = v.lastReviewedAt;
    if (since == null) return 'Revisita';
    return 'Revisita: no catálogo desde ${CurationWords.date(since, clock.now())}';
  }
}

/// One review of the round, read and never a target: "Pedagogo(a)
/// aprovou · Bichos · 5 a 8 anos", the reason of a refusal or of a
/// doubt on its own line.
class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.review);

  final Review review;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final line = CurationWords.review(review);
    final reason =
        review.decision == ReviewDecision.reject ||
            review.decision == ReviewDecision.doubt
        ? review.reason?.trim()
        : null;
    final hasReason = reason != null && reason.isNotEmpty;
    return Semantics(
      container: true,
      label: hasReason ? '$line, $reason' : line,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line, style: text.bodyLarge),
                if (hasReason) ...[
                  const SizedBox(height: Space.xs),
                  Text(reason, style: text.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
