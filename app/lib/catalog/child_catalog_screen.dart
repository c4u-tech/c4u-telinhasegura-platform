import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../curation/curation.dart';
import '../curation/family_catalog.dart';
import '../curation/words.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../screentime/refetch_on_return.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'catalog_children_screen.dart' show leaveForGoneChild;
import 'pack_rows.dart';
import 'video_row.dart';
import 'words.dart';

/// `/familia/videos/:crianca`: everything one child can watch, titled by
/// the nickname, each theme under its heading in the app's order and each
/// video a row led by its thumbnail,
/// under today's pacotinhos when there are any.
/// Pages of 50 append under "Ver mais"; coming back from a video reads
/// from the start again. [notice] is a calm line brought back from a
/// video that left the catalogue.
class ChildCatalogScreen extends StatefulWidget {
  const ChildCatalogScreen({super.key, required this.id, this.notice});

  final String id;
  final String? notice;

  @override
  State<ChildCatalogScreen> createState() => _ChildCatalogScreenState();
}

class _ChildCatalogScreenState extends State<ChildCatalogScreen>
    with RefetchOnReturn {
  final _reading = Submission();
  late final FamilyModel _model;
  bool _started = false;
  List<FamilyVideo>? _videos;
  bool _hasMore = false;

  /// Today's pacotinhos: only the first page carries them.
  List<FamilyPack> _packs = const [];

  /// The read running is "Ver mais", whose action shows the progress.
  bool _more = false;

  /// The first read failed: "Tentar de novo" stays.
  bool _failed = false;

  /// Set once the screen hands back to the list.
  bool _leaving = false;

  /// Shown until the guardian leaves for a video.
  String? _notice;

  @override
  String get ownPath => Routes.childVideos(widget.id);

  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
  }

  @override
  void didUpdateWidget(ChildCatalogScreen old) {
    super.didUpdateWidget(old);
    if (widget.notice != old.notice) _notice = widget.notice;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    watchReturns();
    scheduleMicrotask(_model.load);
    // Beneath a video opened directly, it reads once shown.
    if (isHere) scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  @override
  void onReturn() => unawaited(_read());

  Future<void> _read() async {
    final api = AppScope.of(context).familyCatalog;
    _more = false;
    final ok = await _reading.run(() async {
      final page = await api.minorCatalog(widget.id);
      if (!mounted) return;
      setState(() {
        _videos = page.videos;
        _hasMore = page.hasMore;
        _packs = page.packs;
      });
    }, handle: _gone);
    if (mounted) setState(() => _failed = !ok && !_leaving);
  }

  Future<void> _readMore() async {
    final api = AppScope.of(context).familyCatalog;
    final offset = _videos?.length ?? 0;
    setState(() => _more = true);
    await _reading.run(() async {
      final page = await api.minorCatalog(widget.id, offset: offset);
      if (!mounted) return;
      setState(() {
        _videos = [...?_videos, ...page.videos];
        _hasMore = page.hasMore;
      });
    }, handle: _gone);
    if (mounted) setState(() => _more = false);
  }

  Future<void> _toList() {
    _leaving = true;
    return leaveForGoneChild(context, _model);
  }

  bool _gone(ApiError e) {
    if (e.code != 'not_found') return false;
    if (!_leaving) unawaited(_toList());
    return true;
  }

  void _open(FamilyVideo v) {
    setState(() => _notice = null);
    context.go(Routes.familyVideo(widget.id, v.id), extra: v);
  }

  void _openPack(FamilyPack p) {
    setState(() => _notice = null);
    context.go(Routes.familyPack(widget.id, p.id), extra: p);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _reading]),
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.id).firstOrNull;
        if (minor == null && !_leaving) {
          // Opened for a child the family does not hold.
          _leaving = true;
          scheduleMicrotask(_toList);
        }
      }
      return FieldLayout(
        title: minor?.nickname ?? 'Vídeos',
        onBack: () => context.go(Routes.familyVideos),
        children: minor == null ? familyPending(_model) : _body(minor),
      );
    },
  );

  List<Widget> _body(Minor minor) {
    final text = Theme.of(context).textTheme;
    final videos = _videos;
    final note = [
      if (_reading.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
    ];
    if (videos == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando os vídeos')];
      }
      return [
        ...note,
        PrimaryButton(
          label: 'Tentar de novo',
          busy: _reading.busy,
          onPressed: _reading.blocked ? null : _read,
        ),
      ];
    }
    final themes = [
      for (final t in VideoTheme.values)
        if (t != VideoTheme.unknown)
          (
            t,
            [
              for (final v in videos)
                if (v.theme == t) v,
            ],
          ),
    ].where((s) => s.$2.isNotEmpty);
    final thumbnail = AppScope.of(context).familyCatalog.thumbnail;
    return [
      if (_notice case final notice?) ...[
        Notice(notice),
        const SizedBox(height: Space.lg),
      ],
      // A failed read stands by "Ver mais" when there is more to read.
      if (!_hasMore) ...note,
      Text(CatalogWords.lead(minor.nickname), style: text.bodyLarge),
      if (_packs.isNotEmpty) ...[
        const SizedBox(height: Space.xxl),
        Semantics(
          header: true,
          child: Text(packsHeading, style: text.titleMedium),
        ),
        const SizedBox(height: Space.md),
        Doors(
          children: [
            for (final p in _packs)
              PackRow(
                key: ValueKey(p.id),
                pack: p,
                nickname: minor.nickname,
                thumbnail: thumbnail,
                onTap: () => _openPack(p),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        Text(
          packsDaily,
          style: text.bodyMedium?.copyWith(color: context.palette.muted),
        ),
      ],
      if (themes.isEmpty) ...[
        const SizedBox(height: Space.xl),
        Text(CatalogWords.empty(minor.ageBand), style: text.bodyLarge),
      ],
      for (final (theme, rows) in themes) ...[
        const SizedBox(height: Space.xxl),
        Semantics(
          header: true,
          child: Text(theme.label, style: text.titleMedium),
        ),
        const SizedBox(height: Space.md),
        Doors(
          children: [
            for (final v in rows)
              VideoRow(
                key: ValueKey(v.id),
                video: v,
                nickname: minor.nickname,
                thumbnail: thumbnail,
                onTap: () => _open(v),
              ),
          ],
        ),
      ],
      if (_hasMore) ...[
        const SizedBox(height: Space.xl),
        ...note,
        QuietAction(
          label: 'Ver mais',
          busy: _reading.busy && _more,
          onPressed: _reading.blocked ? null : _readMore,
        ),
      ],
    ];
  }
}
