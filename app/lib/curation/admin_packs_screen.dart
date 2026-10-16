import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../screentime/refetch_on_return.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import 'pack.dart';
import 'packs_screen.dart' show PackRow, emptyPacks;
import 'role_gate.dart';

/// `/admin/pacotinhos`: every pacotinho not removed, for an admin who
/// need not be a curator, as doors read like the curators' list but
/// never "para você revisar"; "Ver mais" appends the next page.
/// It reads again whenever the admin
/// comes back; [notice] is the line a removal brings back.
class AdminPacksScreen extends StatefulWidget {
  const AdminPacksScreen({super.key, this.notice});

  final String? notice;

  @override
  State<AdminPacksScreen> createState() => _AdminPacksScreenState();
}

class _AdminPacksScreenState extends State<AdminPacksScreen>
    with RefetchOnReturn {
  final _more = Submission();
  bool _started = false;
  List<Pack>? _packs;
  bool _hasMore = false;
  bool _failed = false;

  @override
  String get ownPath => Routes.adminPacks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    watchReturns();
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
      final page = await AppScope.of(context).curation.adminPacks();
      if (!mounted) return;
      setState(() {
        _packs = page.packs;
        _hasMore = page.hasMore;
      });
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  Future<void> _readMore() async {
    final api = AppScope.of(context).curation;
    final offset = _packs?.length ?? 0;
    late PackPage page;
    final ok = await _more.run(
      () async => page = await api.adminPacks(offset: offset),
      handle: (e) =>
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _readMore),
    );
    if (!ok || !mounted) return;
    setState(() {
      _packs = [...?_packs, ...page.packs];
      _hasMore = page.hasMore;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _more,
    builder: (context, _) => FieldLayout(
      title: 'Pacotinhos',
      onBack: () => context.go(Routes.admin),
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
    final packs = _packs;
    if (packs == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando os pacotinhos')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    if (packs.isEmpty) {
      return [Text(emptyPacks, style: Theme.of(context).textTheme.bodyLarge)];
    }
    return [
      Doors(
        children: [
          for (final p in packs)
            PackRow(p, onTap: () => context.go(Routes.adminPack(p.id))),
        ],
      ),
      if (_hasMore) ...[
        const SizedBox(height: Space.xxl),
        if (_more.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.sm),
        ],
        QuietAction(
          label: 'Ver mais',
          busy: _more.busy,
          onPressed: _more.blocked ? null : _readMore,
        ),
      ],
    ];
  }
}
