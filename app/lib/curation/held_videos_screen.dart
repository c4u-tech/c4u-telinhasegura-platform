import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../screentime/refetch_on_return.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import 'curation.dart';
import 'role_gate.dart';
import 'words.dart';

/// The held list with nothing in it.
const noHeldVideos = 'Nenhum vídeo retido.';

/// A held video's reports, all reasons together.
int reportCount(HeldVideo h) =>
    h.reports.byReason.values.fold(0, (sum, n) => sum + n);

/// Where the moderation screens' back goes: to
/// "Administração" for an admin, home for a moderator.
String moderationBack(BuildContext context) =>
    AppScope.of(context).familyModel.roles?.contains(PlatformRole.admin) ??
        false
    ? Routes.admin
    : Routes.home;

/// `/moderacao/retidos`: every held video as a door, the title up to two
/// lines, why it is held in words muted, then "2 recusas · 3 denúncias",
/// read through the
/// moderation routes for a moderator or an admin. It reads the list again
/// whenever they come back from a video. [notice] is a calm line brought
/// back from a held video's screen.
class HeldVideosScreen extends StatefulWidget {
  const HeldVideosScreen({super.key, this.notice});

  final String? notice;

  @override
  State<HeldVideosScreen> createState() => _HeldVideosScreenState();
}

class _HeldVideosScreenState extends State<HeldVideosScreen>
    with RefetchOnReturn {
  bool _started = false;

  /// Null while the first read runs.
  List<HeldVideo>? _held;
  bool _failed = false;

  @override
  String get ownPath => Routes.heldVideos;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    watchReturns();
    // Beneath a held video opened directly, it reads once shown.
    if (isHere) scheduleMicrotask(_read);
  }

  @override
  void onReturn() => unawaited(_read());

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final held = await AppScope.of(context).staff.heldVideos();
      if (mounted) setState(() => _held = held);
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => FieldLayout(
    title: 'Vídeos retidos',
    onBack: () => context.go(moderationBack(context)),
    children: [
      if (widget.notice case final notice?) ...[
        Notice(notice),
        const SizedBox(height: Space.xl),
      ],
      ..._list(),
    ],
  );

  List<Widget> _list() {
    final held = _held;
    if (held == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando os vídeos retidos')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    if (held.isEmpty) return [Text(noHeldVideos, style: text.bodyLarge)];
    return [
      Doors(children: [for (final h in held) _HeldRow(h)]),
    ];
  }
}

/// One held video: its title in title-medium up to two lines, why it is
/// held muted, then its counts muted.
class _HeldRow extends StatelessWidget {
  const _HeldRow(this.held);

  final HeldVideo held;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    final v = held.video;
    final reason = held.heldReason.label;
    final counts = CurationWords.heldCounts(
      refusals: held.rejections.length,
      reports: reportCount(held),
    );
    return DoorRow(
      title: v.title,
      titleMaxLines: 2,
      semanticsLabel: [
        v.title,
        reason,
        if (counts.isNotEmpty) counts,
      ].join(', '),
      onTap: () => context.go(Routes.heldVideo(v.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reason, style: muted),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(counts, style: muted),
          ],
        ],
      ),
    );
  }
}
