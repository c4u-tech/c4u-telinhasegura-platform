import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../curation/adult_window.dart';
import '../curation/family_catalog.dart';
import '../curation/video_heading.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'catalog_children_screen.dart' show leaveForGoneChild;
import 'words.dart';

/// In the window's place when the player could not play the video:
/// hide and report stay.
const familyPlayerFailed =
    'Esse vídeo não abriu aqui. Você ainda pode escondê‑lo ou '
    'denunciá‑lo.';

/// The family catalogue's way to one video: [video] as its row read it;
/// opened by its address, the child's catalogue is read page by page to
/// find it, since there is no read of one video.
Future<FamilyVideo?> findFamilyVideo(
  BuildContext context,
  String minorId,
  String videoId,
) async {
  final api = AppScope.of(context).familyCatalog;
  var offset = 0;
  while (true) {
    final page = await api.minorCatalog(minorId, offset: offset);
    if (page.videos.where((v) => v.id == videoId).firstOrNull case final v?) {
      return v;
    }
    if (!page.hasMore || page.videos.isEmpty) return null;
    offset += page.videos.length;
  }
}

/// `/familia/videos/:crianca/:video`: the Video Heading, who approved it
/// by role and when, the Guardian Window (YouTube's own controls, cued,
/// links in the browser), then "Esconder para Lia" or "Mostrar para Lia
/// de novo" as the primary, done in place, and "Denunciar
/// este vídeo" quiet in clay at the foot.
class FamilyVideoScreen extends StatefulWidget {
  const FamilyVideoScreen({
    super.key,
    required this.minorId,
    required this.videoId,
    this.video,
  });

  final String minorId;
  final String videoId;
  final FamilyVideo? video;

  @override
  State<FamilyVideoScreen> createState() => _FamilyVideoScreenState();
}

class _FamilyVideoScreenState extends State<FamilyVideoScreen>
    with AdultWindow {
  final _write = Submission();
  late final FamilyModel _model;
  bool _started = false;
  bool _failed = false;
  FamilyVideo? _video;

  /// Hidden for the child, as the last write left it.
  bool _hidden = false;

  /// The notice of the last write done in place.
  String? _done;

  /// Set once the screen hands back.
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    scheduleMicrotask(_model.load);
    if (widget.video case final v?) {
      _show(v);
    } else {
      scheduleMicrotask(_read);
    }
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  void _show(FamilyVideo v) {
    _video = v;
    _hidden = v.hidden;
    openPlayer(v.youtubeId);
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final v = await findFamilyVideo(context, widget.minorId, widget.videoId);
      if (!mounted) return;
      if (v == null) return _toCatalogue();
      setState(() => _show(v));
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'not_found') return _toChildren();
      setState(() => _failed = true);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toCatalogue() {
    _leaving = true;
    context.go(Routes.childVideos(widget.minorId), extra: videoGone);
  }

  /// The catalogue read answered `not_found`: the child is gone.
  void _toChildren() {
    if (_leaving) return;
    _leaving = true;
    unawaited(leaveForGoneChild(context, _model));
  }

  /// A write answered `not_found`: the video left the catalogue.
  bool _gone(ApiError e) {
    if (e.code != 'not_found') return false;
    if (!_leaving) _toCatalogue();
    return true;
  }

  Future<void> _toggle(String nickname) async {
    final api = AppScope.of(context).familyCatalog;
    final hide = !_hidden;
    setState(() => _done = null);
    final ok = await _write.run(
      () => hide
          ? api.hide(widget.minorId, widget.videoId)
          : api.unhide(widget.minorId, widget.videoId),
      handle: _gone,
    );
    if (!ok || !mounted) return;
    setState(() {
      _hidden = hide;
      _done = hide
          ? CatalogWords.hidden(nickname)
          : CatalogWords.shown(nickname);
    });
  }

  void _report(FamilyVideo v) {
    // The video waits, paused, beneath the report.
    unawaited(playback?.pause());
    context.go(Routes.reportVideo(widget.minorId, widget.videoId), extra: v);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.minorId).firstOrNull;
        if (minor == null) scheduleMicrotask(_toChildren);
      }
      return FieldLayout(
        title: 'Vídeo',
        onBack: () => context.go(Routes.childVideos(widget.minorId)),
        children: minor == null ? familyPending(_model) : _body(minor),
      );
    },
  );

  List<Widget> _body(Minor minor) {
    final v = _video;
    if (v == null) {
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
    final idle = !_write.blocked;
    final nickname = minor.nickname;
    return [
      VideoHeading.parts(
        title: v.title,
        channelTitle: v.channelTitle,
        duration: v.duration,
      ),
      if (v.provenance case final p?) ...[
        const SizedBox(height: Space.lg),
        Text(CatalogWords.provenance(p, clock.now()), style: text.bodyLarge),
      ],
      const SizedBox(height: Space.xl),
      playerWindow(failed: familyPlayerFailed),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_done case final done?) ...[
        Notice(done),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: _hidden
            ? CatalogWords.show(nickname)
            : CatalogWords.hide(nickname),
        busy: _write.busy,
        onPressed: idle ? () => _toggle(nickname) : null,
      ),
      const SizedBox(height: Space.xxl),
      QuietAction(
        label: 'Denunciar este vídeo',
        destructive: true,
        onPressed: idle ? () => _report(v) : null,
      ),
    ];
  }
}
