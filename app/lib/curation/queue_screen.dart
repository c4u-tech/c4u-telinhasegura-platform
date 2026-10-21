import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../screentime/refetch_on_return.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'role_gate.dart';
import 'words.dart';

/// The curator's empty queue.
const emptyQueue = 'Nada na fila agora.';

/// A review the server no longer takes, worded per case; null
/// for any other answer, which the screen words itself.
String? reviewGoneNotice(Object error) => switch (error) {
  ApiError(code: 'already_reviewed' || 'not_reviewable') =>
    'Esse vídeo já saiu da fila.',
  ApiError(code: 'own_suggestion') =>
    'Você sugeriu esse vídeo, então a revisão dele fica com outros '
        'curadores.',
  ApiError(code: 'conflict_of_interest') =>
    'Você tem vínculo com este canal, então a revisão dele fica com outros '
        'curadores.',
  ApiError(code: 'not_found') => 'Esse vídeo não está mais na curadoria.',
  _ => null,
};

/// Takes a review call's [error]: a lost role goes home; a
/// video the curator can no longer review goes back to the queue, which
/// reads itself again, with the notice. Returns whether it took [error].
bool leaveForQueue(BuildContext context, Object error) {
  if (takeLostRole(context, error)) return true;
  final notice = reviewGoneNotice(error);
  if (notice == null) return false;
  context.go(Routes.curation, extra: notice);
  return true;
}

/// `/curadoria`: the calling curator's queue, oldest first, as doors:
/// the title up to two lines, "Canal · 4 min" muted, and "Revisita" on a
/// published video whose revisit fell due; "Ver mais" appends the next
/// page. It reads the queue again from
/// the start whenever the curator comes back from a review, since
/// reviewed videos leave it and shift the offsets. [notice] is a calm
/// line brought back from a review the server no longer took.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, this.notice});

  final String? notice;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> with RefetchOnReturn {
  final _more = Submission();
  bool _started = false;

  /// Null while the first read runs.
  List<Video>? _videos;
  int? _next;
  bool _failed = false;

  @override
  String get ownPath => Routes.curation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    watchReturns();
    // Beneath a review opened directly, it reads once shown.
    if (isHere) scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _more.dispose();
    super.dispose();
  }

  @override
  void onReturn() => unawaited(_read());

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final page = await AppScope.of(context).curation.queue();
      if (!mounted) return;
      setState(() {
        _videos = page.videos;
        _next = page.nextOffset;
      });
    } on Object catch (e) {
      if (!mounted || takeLostRole(context, e)) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _readMore(int offset) async {
    final api = AppScope.of(context).curation;
    late QueuePage page;
    final ok = await _more.run(
      () async => page = await api.queue(offset: offset),
      handle: (e) => takeLostRole(context, e),
    );
    if (!ok || !mounted) return;
    setState(() {
      _videos = [...?_videos, ...page.videos];
      _next = page.nextOffset;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _more,
    builder: (context, _) => FieldLayout(
      title: 'Curadoria',
      onBack: () => context.go(Routes.home),
      children: [
        if (widget.notice case final notice?) ...[
          Notice(notice),
          const SizedBox(height: Space.xl),
        ],
        ..._list(),
      ],
    ),
  );

  List<Widget> _list() {
    final videos = _videos;
    if (videos == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando a fila')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    if (videos.isEmpty) return [Text(emptyQueue, style: text.bodyLarge)];
    final next = _next;
    return [
      Doors(children: [for (final v in videos) _QueueRow(v)]),
      if (next != null) ...[
        const SizedBox(height: Space.xxl),
        if (_more.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.sm),
        ],
        QuietAction(
          label: 'Ver mais',
          busy: _more.busy,
          onPressed: _more.blocked ? null : () => _readMore(next),
        ),
      ],
    ];
  }
}

/// One queued video: its title in title-medium up to two lines, "Canal ·
/// 4 min" muted, then "Revisita" in label type on a revisit.
class _QueueRow extends StatelessWidget {
  const _QueueRow(this.video);

  final Video video;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = video;
    final meta = CurationWords.joined([
      v.channelTitle,
      CurationWords.duration(v.duration),
    ]);
    return DoorRow(
      title: v.title,
      titleMaxLines: 2,
      semanticsLabel: [v.title, meta, if (v.revisit) 'Revisita'].join(', '),
      onTap: () => context.go(Routes.review(v.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meta,
            style: text.bodyMedium?.copyWith(color: context.palette.muted),
          ),
          if (v.revisit) ...[
            const SizedBox(height: Space.xs),
            Text('Revisita', style: text.labelLarge),
          ],
        ],
      ),
    );
  }
}
