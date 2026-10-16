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
import 'pack.dart';
import 'pack_words.dart';
import 'role_gate.dart';

/// No pacotinho yet.
const emptyPacks = 'Nenhum pacotinho ainda.';

/// A pacotinho the server no longer takes a decision or a composition
/// on, worded per case; null for any other answer, which the
/// screen words itself.
String? packGoneNotice(Object error) => switch (error) {
  ApiError(code: 'own_composition') =>
    'Você montou essa versão, então a revisão dela fica com outros '
        'curadores.',
  ApiError(code: 'already_reviewed') => 'Você já revisou essa versão.',
  ApiError(code: 'not_reviewable') =>
    'Essa versão não está mais esperando revisão.',
  ApiError(code: 'not_found' || 'state_conflict') =>
    'Esse pacotinho foi removido.',
  _ => null,
};

/// Takes a pacotinho call's [error]: a lost role goes
/// home; a pacotinho the curator can no longer act on goes back to the
/// list, which reads itself again, with the notice. Returns whether it
/// took [error].
bool leaveForPacks(BuildContext context, Object error) {
  if (takeLostRole(context, error)) return true;
  final notice = packGoneNotice(error);
  if (notice == null) return false;
  context.go(Routes.packs, extra: notice);
  return true;
}

/// `/pacotinhos`: "Montar um pacotinho", then every pacotinho not
/// removed, in the server's order (those awaiting review first), as
/// doors: the title, "3 vídeos · 12 min · Música" muted, and where it
/// stands for this curator in words; "Ver mais" appends the next page.
/// It reads the list again from
/// the start whenever the curator comes back. [notice] is a calm line
/// brought back from a pacotinho the server no longer took.
class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key, this.notice});

  final String? notice;

  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> with RefetchOnReturn {
  final _more = Submission();
  bool _started = false;

  /// Null while the first read runs.
  List<Pack>? _packs;
  bool _hasMore = false;
  bool _failed = false;

  @override
  String get ownPath => Routes.packs;

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
      final page = await AppScope.of(context).curation.packs();
      if (!mounted) return;
      setState(() {
        _packs = page.packs;
        _hasMore = page.hasMore;
      });
    } on Object catch (e) {
      if (!mounted || takeLostRole(context, e)) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _readMore() async {
    final api = AppScope.of(context).curation;
    final offset = _packs?.length ?? 0;
    late PackPage page;
    final ok = await _more.run(
      () async => page = await api.packs(offset: offset),
      handle: (e) => takeLostRole(context, e),
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
      onBack: () => context.go(Routes.home),
      children: [
        if (widget.notice case final notice?) ...[
          Notice(notice),
          const SizedBox(height: Space.xl),
        ],
        PrimaryButton(
          label: 'Montar um pacotinho',
          onPressed: () => context.go(Routes.newPack),
        ),
        const SizedBox(height: Space.xxl),
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
    final text = Theme.of(context).textTheme;
    if (packs.isEmpty) return [Text(emptyPacks, style: text.bodyLarge)];
    return [
      Doors(
        children: [
          for (final p in packs)
            PackRow(p, onTap: () => context.go(Routes.packReview(p.id))),
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

/// One pacotinho as a door: its title in title-medium up to two lines,
/// "3 vídeos · 12 min · Música" muted, then where it stands in label
/// type. The admin's list uses it too.
class PackRow extends StatelessWidget {
  const PackRow(this.pack, {super.key, required this.onTap});

  final Pack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meta = PackWords.meta(pack);
    final state = PackWords.state(pack);
    return DoorRow(
      title: pack.title,
      titleMaxLines: 2,
      semanticsLabel: [pack.title, meta, state].join(', '),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meta,
            style: text.bodyMedium?.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: Space.xs),
          Text(state, style: text.labelLarge),
        ],
      ),
    );
  }
}
