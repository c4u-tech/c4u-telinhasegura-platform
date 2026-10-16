import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../curation/family_catalog.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'catalog_children_screen.dart' show leaveForGoneChild;
import 'pack_rows.dart';
import 'words.dart';

/// `/familia/videos/:crianca/pacotinho/:pacotinho`: one of the child's
/// pacotinhos today, read and never acted on:
/// its title and count, who built and reviewed it by
/// role, its videos in order with the skipped ones marked, and where
/// hiding a video is done. [pack] is the row's; opened by its address,
/// the catalogue's first page is read to find it, since the pacotinhos
/// ride only that page.
class PackScreen extends StatefulWidget {
  const PackScreen({
    super.key,
    required this.minorId,
    required this.packId,
    this.pack,
  });

  final String minorId;
  final String packId;
  final FamilyPack? pack;

  @override
  State<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends State<PackScreen> {
  late final FamilyModel _model;
  bool _started = false;
  bool _failed = false;
  bool _reading = false;
  FamilyPack? _pack;

  /// Set once the screen hands back.
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    scheduleMicrotask(_model.load);
    _pack = widget.pack;
    if (_pack == null) scheduleMicrotask(_read);
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() {
      _failed = false;
      _reading = true;
    });
    final api = AppScope.of(context).familyCatalog;
    try {
      final page = await api.minorCatalog(widget.minorId);
      if (!mounted) return;
      final pack = page.packs.where((p) => p.id == widget.packId).firstOrNull;
      if (pack == null) return _toCatalogue();
      setState(() => _pack = pack);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'not_found') return _toChildren();
      setState(() => _failed = true);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// Not among today's pacotinhos: the day turned, or it was taken down.
  void _toCatalogue() {
    _leaving = true;
    context.go(Routes.childVideos(widget.minorId), extra: packGone);
  }

  /// The child is gone from the family.
  void _toChildren() {
    if (_leaving) return;
    _leaving = true;
    unawaited(leaveForGoneChild(context, _model));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.minorId).firstOrNull;
        if (minor == null) scheduleMicrotask(_toChildren);
      }
      return FieldLayout(
        title: 'Pacotinho',
        onBack: () => context.go(Routes.childVideos(widget.minorId)),
        children: minor == null ? familyPending(_model) : _body(minor),
      );
    },
  );

  List<Widget> _body(Minor minor) {
    final p = _pack;
    if (p == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o pacotinho')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(
          label: 'Tentar de novo',
          busy: _reading,
          onPressed: _reading ? null : _read,
        ),
      ];
    }
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final nickname = minor.nickname;
    final thumbnail = AppScope.of(context).familyCatalog.thumbnail;
    return [
      Text(p.title, style: text.titleMedium),
      const SizedBox(height: Space.xs),
      Text(CatalogWords.packCount(p, nickname), style: muted),
      const SizedBox(height: Space.lg),
      Text(CatalogWords.packProvenance(p, clock.now()), style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      Semantics(
        header: true,
        child: Text('Vídeos, nesta ordem', style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      Doors(
        children: [
          for (final (i, v) in p.videos.indexed)
            PackVideoRow(
              key: ValueKey(v.id),
              position: i + 1,
              video: v,
              nickname: nickname,
              thumbnail: thumbnail,
            ),
        ],
      ),
      const SizedBox(height: Space.md),
      Text(CatalogWords.packHint(nickname), style: muted),
    ];
  }
}
