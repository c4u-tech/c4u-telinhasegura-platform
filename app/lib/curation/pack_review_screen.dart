import 'dart:async';

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
import 'pack.dart';
import 'pack_parts.dart';
import 'packs_screen.dart' show leaveForPacks;
import 'role_gate.dart';
import 'video_heading.dart';
import 'words.dart';

/// A round nobody has reviewed yet.
const noPackReviews = 'Ninguém revisou nesta rodada ainda.';

/// A published pacotinho whose new version awaits review.
const publishedKeeps = 'As crianças seguem vendo a versão publicada.';

/// A round the caller cannot review: they composed it or reviewed it
/// already, and the contract does not say which.
const othersReview = 'Esta versão espera a revisão de outros curadores.';

/// A refused version: only a new one brings the pacotinho back.
const heldVersion =
    'Esta versão foi recusada. Para voltar, o pacotinho precisa de uma '
    'nova versão.';

/// In the window's place when the player could not play the video.
const packVideoFailed = 'Esse vídeo não abriu aqui.';

/// `/pacotinhos/:id`: "O que já disseram, depois o pacotinho".
/// The title, "Montado por
/// Pedagogo(a) · Rodada 2", this round's reviews by displayed role; then
/// the videos in order, each a door to watch it, and the total; then,
/// for a round the curator may review, the doors "Aprovar" and
/// "Recusar", and for any pacotinho the quiet "Mudar o pacotinho".
class PackReviewScreen extends StatefulWidget {
  const PackReviewScreen({super.key, required this.id});

  final String id;

  @override
  State<PackReviewScreen> createState() => _PackReviewScreenState();
}

class _PackReviewScreenState extends State<PackReviewScreen> {
  bool _started = false;
  Pack? _pack;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    scheduleMicrotask(_read);
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final pack = await AppScope.of(context).curation.pack(widget.id);
      if (mounted) setState(() => _pack = pack);
    } on Object catch (e) {
      if (!mounted || leaveForPacks(context, e)) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => FieldLayout(
    title: 'Revisar pacotinho',
    onBack: () => context.go(Routes.packs),
    children: _body(),
  );

  List<Widget> _body() {
    final p = _pack;
    if (p == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o pacotinho')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final standing = switch (p) {
      Pack(reviewable: true, state: PackState.approved) => publishedKeeps,
      Pack(reviewable: true) => null,
      Pack(state: PackState.pending) => othersReview,
      Pack(state: PackState.held) => heldVersion,
      _ => null,
    };
    return [
      Text(p.title, style: text.titleMedium),
      const SizedBox(height: Space.xs),
      Text(
        CurationWords.joined([
          'Montado por ${p.composerRole.label}',
          'Rodada ${p.round}',
        ]),
        style: muted,
      ),
      const SizedBox(height: Space.xl),
      if (p.reviews.isEmpty)
        Text(noPackReviews, style: text.bodyLarge)
      else
        Doors(children: [for (final r in p.reviews) PackReviewLine(r)]),
      if (standing != null) ...[
        const SizedBox(height: Space.lg),
        Text(standing, style: text.bodyLarge),
      ],
      const SizedBox(height: Space.xl),
      Semantics(
        header: true,
        child: Text('Vídeos, nesta ordem', style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      Doors(
        children: [
          for (final (i, v) in p.videos.indexed)
            PackVideoLine(
              position: i + 1,
              video: v,
              onTap: () => context.go(Routes.packVideo(p.id, v.id)),
            ),
        ],
      ),
      const SizedBox(height: Space.sm),
      Text(packTotal(p), style: muted),
      if (p.reviewable) ...[
        const SizedBox(height: Space.xl),
        Doors(
          children: [
            DoorRow(
              title: 'Aprovar',
              semanticsLabel: 'Aprovar, Confirmar a sequência',
              onTap: () => context.go(Routes.approvePack(p.id), extra: p),
              child: Text('Confirmar a sequência', style: muted),
            ),
            DoorRow(
              title: 'Recusar',
              semanticsLabel: 'Recusar, Dizer o motivo',
              onTap: () => context.go(Routes.refusePack(p.id), extra: p),
              child: Text('Dizer o motivo', style: muted),
            ),
          ],
        ),
      ],
      if (p.state != PackState.removed) ...[
        const SizedBox(height: Space.xxl),
        QuietAction(
          label: 'Mudar o pacotinho',
          onPressed: () => context.go(Routes.recompose(p.id)),
        ),
      ],
    ];
  }
}

/// `/pacotinhos/:id/videos/:videoId`: one video of a pacotinho, its
/// title and the adult player as on the video review, nothing else; a
/// video that fails to load shows the error note in the window's place.
class PackVideoScreen extends StatefulWidget {
  const PackVideoScreen({
    super.key,
    required this.packId,
    required this.videoId,
  });

  final String packId;
  final String videoId;

  @override
  State<PackVideoScreen> createState() => _PackVideoScreenState();
}

class _PackVideoScreenState extends State<PackVideoScreen> with AdultWindow {
  bool _started = false;
  Video? _video;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    scheduleMicrotask(_read);
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final d = await AppScope.of(context).curation.video(widget.videoId);
      if (!mounted) return;
      setState(() => _video = d.video);
      openPlayer(d.video.youtubeId);
    } on Object catch (e) {
      if (!mounted || takeLostRole(context, e)) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => FieldLayout(
    title: 'Assistir',
    onBack: () => context.go(Routes.packReview(widget.packId)),
    children: switch (_video) {
      final v? => [
        VideoHeading(v),
        const SizedBox(height: Space.xl),
        playerWindow(failed: packVideoFailed),
      ],
      null when _failed => [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ],
      null => const [FamilyPlaceholder(label: 'Carregando o vídeo')],
    },
  );
}
