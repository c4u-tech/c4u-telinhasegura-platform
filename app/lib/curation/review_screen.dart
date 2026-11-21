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
import 'approval_draft.dart';
import 'curation.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'unheard_ends.dart';
import 'video_heading.dart';
import 'words.dart';

/// A round nobody has reviewed yet.
const noReviews = 'Ninguém revisou nesta rodada ainda.';

/// In the window's place when the player could not play the video:
/// the doors stay, since a video that no longer plays may still
/// be refused.
const playerFailed =
    'Esse vídeo não abriu aqui. Se ele não passa mais, você pode recusá\u2011lo.';

/// The first door, on a review in progress: where it stopped, or, with
/// every question answered, what is left.
const continueReview = 'Continuar revisão';
String stoppedIn(String group) => 'Parou em $group';
const ageLeft = 'Falta confirmar a idade';
const sendLeft = 'Falta conferir e enviar';

/// `/curadoria/:id`: "O que já disseram, depois o vídeo".
/// The video's title, "Canal · 4 min · Rodada 2" and,
/// on a revisit, since when it is in the catalogue; this round's reviews
/// by displayed role, never by person; then the player, whole in a
/// square-edged 16:9 window at the column's width, loaded without
/// playing, with YouTube's own controls and nothing of ours over it;
/// then the doors "Revisar vídeo" and "Recusar". The player pauses
/// beneath a decision and goes when the curator leaves. Entering begins
/// the curator's draft of the review, unless one is already kept, and
/// the video's end is told to it, since an approval needs the video
/// watched to its end; the screen works the same without a draft. A draft
/// with answers turns the first door into "Continuar revisão", with the
/// group where the answers stopped.
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
  late final UnheardEnds _ends;
  bool _away = false;

  /// The draft read on entry, while it holds an answer, and where it
  /// stopped, once the list is read; null for none.
  ReviewDraft? _kept;
  ApprovalDraft? _progress;
  Checklist? _list;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _ends = AppScope.of(context).unheardEnds;
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

  /// A decision opened above: the video waits, paused, beneath it. Back
  /// from it, the draft is read again, since the answers may have moved.
  void _where() {
    final here =
        _router?.routerDelegate.currentConfiguration.uri.path ==
        Routes.review(widget.id);
    if (!here && !_away) unawaited(playback?.pause());
    if (here && _away) {
      if (_detail case final detail?) unawaited(_reread(detail.video));
    }
    _away = !here;
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final detail = await AppScope.of(context).curation.video(widget.id);
      if (!mounted) return;
      setState(() => _detail = detail);
      openPlayer(detail.video.youtubeId, onEnded: _ended);
      unawaited(_begin(detail.video));
    } on Object catch (e) {
      if (!mounted || leaveForQueue(context, e)) return;
      setState(() => _failed = true);
    }
  }

  /// Begins the draft when none is kept. A draft that cannot be read or
  /// begun changes nothing here: the review goes on without it. A kept
  /// draft with answers is read against the list, for where it stopped.
  Future<void> _begin(Video v) async {
    final api = AppScope.of(context).curation;
    final ReviewDraft? kept;
    try {
      kept = await api.draft(widget.id);
      if (kept == null) await api.saveDraft(widget.id);
    } on Object {
      // Without a draft, the review is the one it always was.
      return;
    }
    await _show(kept, v);
  }

  /// Reads the draft again for the door; a read that fails leaves it.
  Future<void> _reread(Video v) async {
    try {
      final kept = await AppScope.of(context).curation.draft(widget.id);
      await _show(kept, v);
    } on Object {
      // The door keeps what it said.
    }
  }

  /// Where [kept] stopped, on the door: read against the list, read once.
  Future<void> _show(ReviewDraft? kept, Video v) async {
    if (!mounted) return;
    final answered = kept != null && kept.answers.isNotEmpty;
    setState(() {
      _kept = answered ? kept : null;
      _progress = null;
    });
    if (!answered) return;
    try {
      final list = _list ??= await AppScope.of(context).curation.checklist();
      if (!mounted || _kept != kept) return;
      setState(
        () =>
            _progress = ApprovalDraft(list, length: v.duration)..restore(kept),
      );
    } on Object {
      // The door still says the review is in progress, without where.
    }
  }

  /// Tells the draft the video played to its end. A failure says nothing
  /// here: it is kept, and the approval sends it again.
  void _ended() => unawaited(_ends.report(widget.id));

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
          // The questions may end in an approval, a refusal or the team's
          // decision: the door names the review, not one outcome.
          if (_firstDoor() case (final title, final line))
            DoorRow(
              title: title,
              semanticsLabel: '$title, $line',
              onTap: () => context.go(Routes.approve(widget.id), extra: v),
              child: Text(line, style: muted),
            ),
          DoorRow(
            title: 'Recusar',
            semanticsLabel: 'Recusar, Marcar o que acontece',
            onTap: () => context.go(Routes.refuse(widget.id), extra: v),
            child: Text('Marcar o que acontece', style: muted),
          ),
        ],
      ),
    ];
  }

  /// The first door's title and line: a review not begun, or one in
  /// progress with where it stopped, the page the flow opens on. A draft
  /// whose answers are all to questions the list no longer asks is one not
  /// begun.
  (String, String) _firstDoor() {
    const fresh = ('Revisar vídeo', 'Responder às perguntas');
    if (_kept == null) return fresh;
    final d = _progress;
    if (d == null) return (continueReview, 'Responder às perguntas');
    if (d.answers.isEmpty) return fresh;
    final page = d.resumePage;
    return (
      continueReview,
      page <= d.stepCount
          ? stoppedIn(d.checklist.groups[page].title)
          : page == d.topicPage
          ? ageLeft
          : sendLeft,
    );
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
