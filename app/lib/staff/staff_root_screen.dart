import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_error.dart';
import '../auth/auth_api.dart' show PlatformRole;
import '../curation/curation.dart' show QueuePage;
import '../curation/pack.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';

/// The muted line of a row with nothing waiting in it.
const nothingWaiting = 'nada esperando';

/// The line under the home's door to Equipe.
const _equipeLine = 'O que espera revisão e as ferramentas';

/// Where a staff member without a family reaches their work from the
/// home: one door to Equipe for any platform role in [roles], none
/// without one.
List<DoorRow> staffDoors(BuildContext context, Set<PlatformRole> roles) => [
  if (roles.isNotEmpty)
    DoorRow(
      title: 'Equipe',
      semanticsLabel: 'Equipe, $_equipeLine',
      onTap: () => context.go(Routes.staffHome),
      child: Text(
        _equipeLine,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.muted),
      ),
    ),
];

/// How many items wait in one of Equipe's rows, as far as the read that
/// counted them can tell: [count] exactly, or, when [more] may follow
/// past the page read, at least [count].
class Waiting {
  const Waiting(this.count, {this.more = false});

  final int count;
  final bool more;

  /// The figure at the row's end: "12", "50+"; null when nothing waits.
  String? get figure => count == 0 && !more
      ? null
      : more
      ? '$count+'
      : '$count';

  /// What assistive technology hears after the row's title.
  String get spoken => count == 0 && !more
      ? nothingWaiting
      : more
      ? '$count ou mais'
      : '$count';

  /// The queue's first page: every video in it waits for this curator,
  /// and another page means more do.
  static Waiting ofQueue(QueuePage page) =>
      Waiting(page.videos.length, more: page.nextOffset != null);

  /// The pacotinhos' first page, those awaiting review first: the ones
  /// this curator may review. While the page's last pacotinho is still
  /// awaiting review, another page may hold more, so the count is a
  /// floor; with none on the page then, there is no honest number (null).
  static Waiting? ofPacks(PackPage page) {
    final n = page.packs.where((p) => p.reviewable).length;
    final last = page.packs.lastOrNull;
    final open =
        page.hasMore &&
        last != null &&
        (last.reviewable || last.state == PackState.pending);
    if (open && n == 0) return null;
    return Waiting(n, more: open);
  }
}

/// `/equipe`, the Equipe destination's root: the work first. "Para
/// revisar" holds, per role, "Revisar vídeos" and "Pacotinhos para
/// revisar" (curators) and "Vídeos retidos" (moderators and admins), each
/// ending on how many wait, read with the same calls their screens make;
/// "Ferramentas" follows with the admin's and the moderator's tools. A
/// count not read (loading, failed, refused) shows no number, and a
/// section with no row for the roles is not shown. The router lets only
/// a role holder in; staff need no family, so without one it stands
/// outside the navigation, with a back control to the home.
class StaffRootScreen extends StatefulWidget {
  const StaffRootScreen({super.key});

  @override
  State<StaffRootScreen> createState() => _StaffRootScreenState();
}

class _StaffRootScreenState extends State<StaffRootScreen> {
  late final FamilyModel _model;
  bool _started = false;
  bool _asked = false;

  Waiting? _queue;
  Waiting? _packs;
  Waiting? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel..addListener(_rolesRead);
    // The roles come with the account's read; it notifies the router, so
    // after this build.
    scheduleMicrotask(_model.load);
    scheduleMicrotask(_rolesRead);
  }

  @override
  void dispose() {
    _model.removeListener(_rolesRead);
    super.dispose();
  }

  /// Once the roles are known, counts what each opens, once.
  void _rolesRead() {
    final roles = _model.roles;
    if (_asked || roles == null || !mounted) return;
    _asked = true;
    final services = AppScope.of(context);
    if (roles.contains(PlatformRole.curator)) {
      final curation = services.curation;
      unawaited(
        _count(() async => Waiting.ofQueue(await curation.queue()), (w) {
          _queue = w;
        }),
      );
      unawaited(
        _count(() async => Waiting.ofPacks(await curation.packs()), (w) {
          _packs = w;
        }),
      );
    }
    if (_holds(roles)) {
      final staff = services.staff;
      unawaited(
        _count(() async => Waiting((await staff.heldVideos()).length), (w) {
          _held = w;
        }),
      );
    }
  }

  static bool _holds(Set<PlatformRole> roles) =>
      roles.contains(PlatformRole.moderator) ||
      roles.contains(PlatformRole.admin);

  /// Reads one count. Equipe never leaves on a count's refusal: one that
  /// asks for the curator terms or the second factor leaves its row
  /// without a number, and the screen it opens asks; a role the server
  /// no longer grants goes from the session, taking its rows with it.
  Future<void> _count(
    Future<Waiting?> Function() read,
    void Function(Waiting?) set,
  ) async {
    try {
      final waiting = await read();
      if (mounted) setState(() => set(waiting));
    } on Object catch (e) {
      if (e is ApiError) unawaited(_model.roleLost(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => FieldLayout(
      title: 'Equipe',
      onBack: ShellFrame.maybeOf(context) == null
          ? () => context.go(Routes.home)
          : null,
      children: switch (_model.roles) {
        final roles? => _sections(roles),
        null => const [FamilyPlaceholder(label: 'Carregando a equipe')],
      },
    ),
  );

  List<Widget> _sections(Set<PlatformRole> roles) {
    final curator = roles.contains(PlatformRole.curator);
    final admin = roles.contains(PlatformRole.admin);
    final review = [
      if (curator) ...[
        _counted('Revisar vídeos', Routes.curation, _queue),
        _counted('Pacotinhos para revisar', Routes.packs, _packs),
      ],
      if (_holds(roles)) _counted('Vídeos retidos', Routes.heldVideos, _held),
    ];
    final tools = [
      if (admin) ...[
        _tool('Buscar uma conta', Routes.accounts),
        _tool('Pessoas da equipe', Routes.team),
        _tool('Registro da equipe', Routes.audit),
      ],
      if (_holds(roles)) _tool('Amostra de aprovações', Routes.auditSample),
      // A curator reaches the pacotinhos from "Para revisar"; an admin
      // who is not one, here, to remove one.
      if (admin && !curator) _tool('Pacotinhos', Routes.packs),
      if (admin) _tool('Números da plataforma', Routes.numbers),
    ];
    return [
      if (review.isNotEmpty) _section('Para revisar', review),
      if (review.isNotEmpty && tools.isNotEmpty)
        const SizedBox(height: Space.xxl),
      if (tools.isNotEmpty) _section('Ferramentas', tools),
    ];
  }

  Widget _section(String title, List<DoorRow> rows) => Column(
    key: ValueKey(title),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: Space.md),
      Doors(children: rows),
    ],
  );

  /// A row to review: its count at the end once read, "nada esperando"
  /// muted under the title when nothing waits, no number otherwise.
  DoorRow _counted(String title, String path, Waiting? waiting) {
    final text = Theme.of(context).textTheme;
    final figure = waiting?.figure;
    return DoorRow(
      title: title,
      semanticsLabel: [title, ?waiting?.spoken].join(', '),
      onTap: () => context.go(path),
      trailing: figure == null
          ? null
          : Text(
              figure,
              key: const ValueKey('figure'),
              style: text.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
      child: waiting != null && figure == null
          ? Text(
              nothingWaiting,
              style: text.bodyMedium?.copyWith(color: context.palette.muted),
            )
          : null,
    );
  }

  DoorRow _tool(String title, String path) =>
      DoorRow(title: title, onTap: () => context.go(path));
}
