import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_client.dart';
import '../design/espiadinha.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/wordmark.dart';
import '../family/family_model.dart';
import '../parental/app_mode.dart';
import 'list_detail.dart';
import 'routes.dart';
import 'services.dart';

/// The guardian's four places. Each is a root the navigation opens with
/// `go`; every other screen belongs to the one its path lies under.
enum Destination {
  inicio('Início', Routes.home, Icons.home_rounded),
  familia('Família', Routes.family, Icons.family_restroom_rounded),
  conta('Conta', Routes.account, Icons.person_rounded),
  equipe('Equipe', Routes.staffHome, Icons.groups_rounded);

  const Destination(this.label, this.root, this.icon);

  final String label;
  final String root;
  final IconData icon;

  /// The place [path] belongs to: the kid-mode guide is the family's, a
  /// suggestion the home's, any curation, moderation or admin screen the
  /// staff's.
  static Destination of(String path) {
    if (Routes.isStaffScreen(path)) return equipe;
    if (Routes.isFamilyScreen(path) || Routes.isKidModeScreen(path)) {
      return familia;
    }
    if (Routes.isAccountScreen(path)) return conta;
    return inicio;
  }

  /// Whether [path] is one of the four roots, the only screens a narrow
  /// window shows the bar on.
  static bool isRoot(String path) => values.any((d) => d.root == path);
}

/// Frames the guardian's screens with the navigation, once the family is
/// ready: the ink rail beside every screen on a wide window, the bar under
/// the four roots on a narrow one. Before that (no family yet, the email
/// to confirm, the first read), while suspended, or with the terms
/// pending, the screen stands alone as it always has. On a large window
/// a place of several items ([lists]) shows its list beside the item it
/// opened, the screens of the path standing in the detail.
class GuardianShell extends StatefulWidget {
  const GuardianShell({
    super.key,
    required this.path,
    required this.child,
    this.lists = const {},
  });

  /// The location's path, which decides the selected destination.
  final String path;
  final Widget child;

  /// Each place's root, shown as the list on a large window.
  final Map<Destination, Widget> lists;

  @override
  State<GuardianShell> createState() => _GuardianShellState();
}

class _GuardianShellState extends State<GuardianShell> {
  /// Keeps the framed screens' state as the frame around them changes.
  final _content = GlobalKey();
  final _rises = ValueNotifier(0);
  late final AppServices _services;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _services = AppScope.of(context);
    // The navigation waits on the family; a screen that reads none
    // (a staff screen opened directly) still gets it. The read notifies
    // the router, so it starts after this build.
    if (_services.client.status.value == AuthStatus.signedIn) {
      scheduleMicrotask(_services.familyModel.load);
    }
  }

  @override
  void dispose() {
    _rises.dispose();
    super.dispose();
  }

  /// Whether the place shows its list beside the open item.
  bool _split = false;

  /// Beside the list, an item's first level is the place itself, as the
  /// root is on a phone: system back leaves the app from it rather than
  /// landing on the root, which would show the same item again. A
  /// dialog over the shell, and the second factor's screens, which ask
  /// before letting recovery codes go, keep their own back.
  Future<bool> _leaveFromItem() async {
    final path = widget.path;
    if (!_split ||
        !Panes.leavesOnBack(path) ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    await SystemNavigator.pop();
    return true;
  }

  bool get _active {
    final model = _services.familyModel;
    return _services.appMode.mode is Guardian &&
        model.state is FamilyReady &&
        !model.suspended &&
        model.termsAccepted;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_services.familyModel, _services.appMode]),
    builder: (context, _) {
      final content = KeyedSubtree(key: _content, child: widget.child);
      if (!_active) return content;
      final staff = _services.familyModel.roles?.isNotEmpty ?? false;
      final destinations = [
        Destination.inicio,
        Destination.familia,
        Destination.conta,
        if (staff) Destination.equipe,
      ];
      final current = Destination.of(widget.path);
      void open(Destination d) => context.go(d.root);
      return LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= FieldSizes.wideBreakpoint) {
            final list = widget.lists[current];
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final room =
                box.maxWidth - ShellSizes.railInset - ShellSizes.railWidth;
            // At a text size the window cannot hold beside a list, the
            // place falls back to one column.
            final split =
                list != null &&
                box.maxWidth >= ShellSizes.listDetailBreakpoint &&
                ListDetail.fits(room, scale) &&
                !Panes.isFocus(widget.path);
            _split = split;
            final area = split
                ? ListDetail(
                    listWidth: ListDetail.listWidthAt(scale),
                    list: ShellFrame(
                      rail: true,
                      rises: _rises,
                      pane: Pane.list,
                      chosen: Panes.itemOf(
                        widget.path,
                        _services.familyModel.roles,
                      ),
                      chosenAtFirstLevel: Panes.isPaneRoot(widget.path),
                      child: KeyedSubtree(key: ValueKey(current), child: list),
                    ),
                    detail: ShellFrame(
                      rail: true,
                      rises: _rises,
                      pane: Pane.detail,
                      paneRoot: Panes.isPaneRoot,
                      leavesOnBack: Panes.leavesOnBack,
                      child: content,
                    ),
                  )
                : ShellFrame(rail: true, rises: _rises, child: content);
            return Material(
              color: context.palette.ground,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    right: false,
                    child: InkRail(
                      destinations: destinations,
                      selected: current,
                      onOpen: open,
                      rises: _rises,
                    ),
                  ),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeLeft: true,
                      child: BackButtonListener(
                        onBackButtonPressed: _leaveFromItem,
                        child: area,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final bar = Destination.isRoot(widget.path);
          final framed = ShellFrame(rail: false, rises: _rises, child: content);
          if (!bar) return framed;
          return Material(
            color: context.palette.ground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: framed,
                  ),
                ),
                ShellBar(
                  destinations: destinations,
                  selected: current,
                  onOpen: open,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// The narrow window's navigation, under a destination's root: the
/// destinations side by side on the ground, under a reed hairline.
class ShellBar extends StatelessWidget {
  const ShellBar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onOpen,
  });

  static const surfaceKey = Key('shell-bar');

  final List<Destination> destinations;
  final Destination selected;
  final ValueChanged<Destination> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      key: surfaceKey,
      decoration: BoxDecoration(
        color: p.ground,
        border: Border(top: BorderSide(color: p.outline.withValues(alpha: .5))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          // With the tiles' own inset, every name keeps a clear gap from
          // its neighbour and from the screen edge, even at 200 % text.
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xs,
          ),
          child: Row(
            children: [
              for (final d in destinations)
                Expanded(
                  child: DestinationTile(
                    destination: d,
                    selected: d == selected,
                    onTap: () => onOpen(d),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wide window's navigation and its one ink field: the Espiadinha
/// peeking over the rail's top edge, the wordmark inside it, then the
/// destinations.
class InkRail extends StatelessWidget {
  const InkRail({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onOpen,
    required this.rises,
  });

  static const fieldKey = Key('ink-rail');

  final List<Destination> destinations;
  final Destination selected;
  final ValueChanged<Destination> onOpen;

  /// The confirmations the framed screens asked for: the head rises.
  final ValueNotifier<int> rises;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: ShellSizes.railInset,
        top: ShellSizes.railInset,
        bottom: ShellSizes.railInset,
      ),
      child: SizedBox(
        width: ShellSizes.railWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Center(
                child: SizedBox(
                  height: EspiadinhaPainter.height * ShellSizes.railUnit,
                  child: ValueListenableBuilder(
                    valueListenable: rises,
                    builder: (context, n, _) =>
                        PeekingHead(unit: ShellSizes.railUnit, rise: n > 0),
                  ),
                ),
              ),
            ),
            Expanded(
              child: DecoratedBox(
                key: fieldKey,
                decoration: BoxDecoration(
                  color: p.field,
                  borderRadius: BorderRadius.circular(10 * ShellSizes.railUnit),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.xl,
                    Space.md,
                    Space.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The name plate, on the head's axis above the
                      // start-aligned destinations.
                      const Center(child: Wordmark(height: WordmarkSizes.rail)),
                      const SizedBox(height: Space.xxl),
                      for (final d in destinations) ...[
                        if (d != destinations.first)
                          const SizedBox(height: Space.xs),
                        DestinationTile(
                          destination: d,
                          selected: d == selected,
                          onTap: () => onOpen(d),
                          rail: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One destination: its glyph inside the mark's screen, filled when it is
/// the place shown and empty otherwise, with its name beside it (the
/// rail) or under it (the bar). Read as a button by its name, with its
/// selected state; the whole tile is the target.
class DestinationTile extends StatefulWidget {
  const DestinationTile({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
    this.rail = false,
  });

  static const indicatorKey = Key('destination-indicator');

  final Destination destination;
  final bool selected;
  final VoidCallback onTap;

  /// On the ink rail: cream on ink, the name beside the glyph.
  final bool rail;

  @override
  State<DestinationTile> createState() => _DestinationTileState();
}

class _DestinationTileState extends State<DestinationTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final selected = widget.selected;
    final rail = widget.rail;
    // On the ground the screen fills with the action colour; on the ink
    // rail with cream, the field's own figure.
    final fill = rail ? p.onField : p.action;
    final glyph = selected
        ? (rail ? p.field : p.onAction)
        : (rail ? p.onField : p.muted);
    final words = rail
        ? (selected ? p.onField : p.onFieldMuted)
        : (selected ? p.text : p.muted);
    final indicator = Container(
      key: DestinationTile.indicatorKey,
      width: ShellSizes.indicatorWidth,
      height: ShellSizes.indicator,
      decoration: BoxDecoration(
        color: selected ? fill : null,
        borderRadius: BorderRadius.circular(
          ShellSizes.indicator * Radii.screenRatio,
        ),
      ),
      child: Icon(widget.destination.icon, size: 22, color: glyph),
    );
    final label = Text(
      widget.destination.label,
      maxLines: 1,
      softWrap: false,
      style: (rail ? text.labelLarge : text.labelMedium)?.copyWith(
        color: words,
      ),
    );
    final body = rail
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ShellSizes.railItem),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(
                children: [
                  indicator,
                  const SizedBox(width: Space.md),
                  Expanded(child: label),
                ],
              ),
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: Space.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  indicator,
                  const SizedBox(height: Space.xs),
                  // A long name at a large text size scales down to fit
                  // its share of the bar rather than overflow it.
                  FittedBox(fit: BoxFit.scaleDown, child: label),
                ],
              ),
            ),
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.small),
    );
    final ring = _focused
        ? (rail
              ? BorderSide(
                  color: p.onField,
                  width: 3,
                  strokeAlign: BorderSide.strokeAlignOutside,
                )
              : focusRing(p).resolve({WidgetState.focused}))
        : null;
    final wash = rail ? p.onField : p.outline;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: widget.destination.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape.copyWith(side: ring ?? BorderSide.none),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (focused) => setState(() => _focused = focused),
          customBorder: shape,
          focusColor: Colors.transparent,
          hoverColor: wash.withValues(alpha: .08),
          highlightColor: wash.withValues(alpha: .12),
          splashColor: wash.withValues(alpha: .12),
          child: body,
        ),
      ),
    );
  }
}
