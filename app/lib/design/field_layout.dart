import 'dart:async';

import 'package:flutter/material.dart';

import 'display_title.dart';
import 'pinned_header.dart';
import 'tevi.dart';
import 'theme.dart';
import 'tokens.dart';
import 'wordmark.dart';

/// How much of the screen the ink field takes on a narrow screen.
enum FieldSize {
  /// The entry screen: wordmark and the promise line.
  hero,

  /// Every task screen: a band with the wordmark and, when given, a back
  /// control.
  band,
}

/// The field's one promise, on every screen: who curates is parents,
/// caregivers and professionals, and publishing takes approvals from any
/// of them, so it never says "only other parents" (2026-10-06).
const promiseLine =
    'Cada vídeo daqui passa pelo olhar de pais, cuidadores e profissionais '
    'antes de chegar a uma criança.';

/// Where a framed screen stands beside the rail.
enum Pane {
  /// Alone in the space beside the rail, its column centred there.
  single,

  /// The list of a place's items, at the start of a large window.
  list,

  /// The item the list opened, beside the list.
  detail,
}

/// Marks the screens the guardian's navigation frames. With [rail], the
/// ink rail stands beside them and is their ink field, so a screen draws
/// no field of its own. A destination's root reads it to know that the
/// navigation, not a back control, is the way elsewhere.
class ShellFrame extends InheritedWidget {
  const ShellFrame({
    super.key,
    required this.rail,
    required this.winks,
    this.pane = Pane.single,
    this.chosen,
    this.chosenAtFirstLevel = false,
    this.paneRoot,
    this.leavesOnBack,
    required super.child,
  });

  final bool rail;

  /// Counts the confirmations a framed screen asked to play: the mascot
  /// on the rail winks for them, since the rail is the screen's field.
  final ValueNotifier<int> winks;

  /// Where the screens stand beside the rail.
  final Pane pane;

  /// In the list pane, the path of the item the detail shows.
  final String? chosen;

  /// In the list pane, whether the detail shows the chosen item at its
  /// first level, so opening it again would change nothing.
  final bool chosenAtFirstLevel;

  /// In the detail pane, whether a page (named by its route's path
  /// pattern) is an item's first level: the list beside it is the way
  /// elsewhere, so it shows no back control.
  final bool Function(String pattern)? paneRoot;

  /// In the detail pane, whether back from a page (named by its route's
  /// path pattern) leaves the place rather than popping to its root, so
  /// the page takes no back swipe.
  final bool Function(String pattern)? leavesOnBack;

  static ShellFrame? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellFrame>();

  /// Whether the list pane's row opening [item] is the one shown beside it.
  static bool isChosen(BuildContext context, String item) {
    final frame = maybeOf(context);
    return frame != null && frame.pane == Pane.list && frame.chosen == item;
  }

  @override
  bool updateShouldNotify(ShellFrame old) =>
      old.rail != rail ||
      old.winks != winks ||
      old.pane != pane ||
      old.chosen != chosen ||
      old.chosenAtFirstLevel != chosenAtFirstLevel ||
      old.paneRoot != paneRoot ||
      old.leavesOnBack != leavesOnBack;
}

/// The access surface's frame. The flat ink field carries the name plate,
/// with the mascot standing on its top edge; the task sits on the ground
/// beside it (wide) or below it (narrow). No cards: the field's edge does
/// the dividing.
///
/// A screen that is watched while it is worked on gives a [watch] (a
/// player and its state): it stays in view above the task, pinned under
/// the band or the back control while the task scrolls beneath it, or in
/// a pane of its own beside the task on a large window.
class FieldLayout extends StatelessWidget {
  const FieldLayout({
    super.key,
    required this.title,
    required this.children,
    this.watch,
    this.titleSemanticsLabel,
    this.titleLeading,
    this.titleLine,
    this.size = FieldSize.band,
    this.onBack,
    this.wink = false,
    this.promise = promiseLine,
    this.columnWidth = FieldSizes.columnMaxWidth,
  });

  /// The wide window's ink panel, absent when the rail stands for it.
  static const panelKey = Key('field-panel');

  /// The ink field itself, narrow or in the wide panel.
  static const fieldKey = Key('ink-field');

  /// The display title over the task; null for none.
  final String? title;

  /// What stays in view while the task is worked on; see the class.
  final Widget? watch;

  /// The column's cap: the task's 400 px, wider only for a screen that
  /// is not one task (the home's two columns of children beside the rail).
  final double columnWidth;

  /// The promise line the field carries (wide, and under the title at large
  /// text). A surface whose reader is not a guardian says its own.
  final String promise;

  /// What assistive technology reads instead of [title], when the shown
  /// title carries an address's break marks.
  final String? titleSemanticsLabel;

  /// A mark beside the title (a child's avatar), top-aligned with it.
  final Widget? titleLeading;

  /// A muted line under the title, beside [titleLeading] when there is one
  /// (a child's age band).
  final String? titleLine;
  final List<Widget> children;
  final FieldSize size;
  final VoidCallback? onBack;

  /// The mascot winks once: the confirmations.
  final bool wink;

  /// The width a column can take in a screen [width] wide: the screen
  /// less the side padding its place gives the column.
  static double roomIn(BuildContext context, double width) {
    final frame = ShellFrame.maybeOf(context);
    final sides = frame == null || !frame.rail
        ? 2 * Space.xl
        : _RailFramed.padding(frame.pane).horizontal;
    return width - sides;
  }

  /// Whether this screen is the first level of the detail pane's item,
  /// read from its page's path pattern (never from the router's state,
  /// which a page being redirected away cannot resolve).
  static bool _atPaneRoot(BuildContext context, ShellFrame frame) =>
      _pageIs(context, frame, frame.paneRoot);

  /// Whether [test] holds for this page's path pattern in the detail pane.
  static bool _pageIs(
    BuildContext context,
    ShellFrame frame,
    bool Function(String pattern)? test,
  ) {
    if (frame.pane != Pane.detail || test == null) return false;
    final key = ModalRoute.of(context)?.settings;
    return switch (key) {
      Page(key: ValueKey<String>(:final value)) => test(value),
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    // At large text sizes the hero would push the task below the fold:
    // the field shrinks to a band and the promise moves under the title.
    final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    final compact = size == FieldSize.hero && largeText;
    // The compact hero's promise reads under the title, wide or narrow.
    final task = _TaskColumn(
      title: title,
      titleSemanticsLabel: titleSemanticsLabel,
      leading: titleLeading,
      line: titleLine,
      lead: compact ? promise : null,
      width: columnWidth,
      children: children,
    );
    final frame = ShellFrame.maybeOf(context);
    if (frame != null && frame.rail) {
      final framed = _RailFramed(
        task: task,
        watch: watch,
        width: columnWidth,
        onBack: _atPaneRoot(context, frame) ? null : onBack,
        wink: wink,
        winks: frame.winks,
        pane: frame.pane,
      );
      // Back from here leaves the place (the shell sees to it), so no
      // swipe pops to the root beneath, which shows this same page.
      return _pageIs(context, frame, frame.leavesOnBack)
          ? PopScope(canPop: false, child: framed)
          : framed;
    }
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= FieldSizes.wideBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    key: panelKey,
                    width: box.maxWidth * 0.46,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: _Field(
                        corner: FieldSizes.heroCorner,
                        tevi: FieldSizes.heroTevi,
                        wink: wink,
                        expand: true,
                        // At large text the panel behaves as the narrow
                        // field: no promise for a band screen (the band
                        // carries none), the hero's under its title; a
                        // display-large promise would be clipped at the
                        // panel's foot.
                        child: _FieldContent(
                          size: FieldSize.hero,
                          onBack: onBack,
                          large: true,
                          promise: largeText ? null : promise,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.xl,
                          vertical: Space.xxxl,
                        ),
                        // Without a pane of its own here, what is watched
                        // heads the task.
                        child: switch (watch) {
                          final watch? => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: columnWidth,
                                ),
                                child: watch,
                              ),
                              const SizedBox(height: Space.xl),
                              task,
                            ],
                          ),
                          null => task,
                        },
                      ),
                    ),
                  ),
                ],
              );
            }
            final hero = size == FieldSize.hero && !compact;
            if (watch case final watch?) {
              return _pinnedUnderBand(
                context,
                watch: watch,
                task: task,
                onBack: onBack,
                wink: wink,
                width: columnWidth,
              );
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.md,
                      Space.sm,
                      Space.md,
                      0,
                    ),
                    child: _Field(
                      corner: hero
                          ? FieldSizes.heroCorner
                          : FieldSizes.bandCorner,
                      tevi: hero ? FieldSizes.heroTevi : FieldSizes.bandTevi,
                      wink: wink,
                      child: _FieldContent(
                        size: hero ? FieldSize.hero : FieldSize.band,
                        onBack: onBack,
                        promise: promise,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xl,
                      Space.xxl,
                      Space.xl,
                      Space.xxxl,
                    ),
                    child: Center(child: task),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The narrow band and [watch] under it stay at the top while [task]
/// scrolls beneath them, as long as the task keeps at least half the
/// height: else the band scrolls away and [watch] alone stays, when that
/// leaves the task half; else both scroll with it.
Widget _pinnedUnderBand(
  BuildContext context, {
  required Widget watch,
  required Widget task,
  required VoidCallback? onBack,
  required bool wink,
  required double width,
}) {
  final p = context.palette;
  return CustomScrollView(
    slivers: [
      PinnedHeader(
        edge: p.outline.withValues(alpha: .5),
        lead: ColoredBox(
          color: p.ground,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
            child: _Field(
              corner: FieldSizes.bandCorner,
              tevi: FieldSizes.bandTevi,
              wink: wink,
              child: _FieldContent(size: FieldSize.band, onBack: onBack),
            ),
          ),
        ),
        child: ColoredBox(
          color: p.ground,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.lg,
              Space.xl,
              Space.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: watch,
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.xl,
          Space.xl,
          Space.xxxl,
        ),
        sliver: SliverToBoxAdapter(child: Center(child: task)),
      ),
    ],
  );
}

/// A screen beside the ink rail: the rail is its field. Every column
/// stands at one place, at the top of the content area and centred in it
/// (or at the start of its pane, beside a list), so the title stays put
/// as the destinations change; a task's back control stands at the
/// column's start right above it, in a slot a root keeps empty.
class _RailFramed extends StatefulWidget {
  const _RailFramed({
    required this.task,
    required this.watch,
    required this.width,
    required this.onBack,
    required this.wink,
    required this.winks,
    required this.pane,
  });

  final Widget task;
  final Widget? watch;

  /// The task column's cap.
  final double width;
  final VoidCallback? onBack;
  final bool wink;
  final ValueNotifier<int> winks;
  final Pane pane;

  /// From this width of the content area what is watched takes a pane of
  /// its own: the room a large window leaves beside the rail, the same
  /// at which a place shows its list beside its item.
  static const watchPaneFrom =
      ShellSizes.listDetailBreakpoint -
      ShellSizes.railInset -
      ShellSizes.railWidth;

  /// The space around the column in each place beside the rail.
  static EdgeInsetsDirectional padding(Pane pane) => switch (pane) {
    Pane.single => const EdgeInsetsDirectional.fromSTEB(
      Space.xxxl,
      Space.xxl,
      Space.xxxl,
      Space.xxxl,
    ),
    // The list's pane is narrow: its doors take most of it.
    Pane.list => const EdgeInsetsDirectional.fromSTEB(
      Space.xl,
      Space.xxl,
      Space.xl,
      Space.xxxl,
    ),
    Pane.detail => const EdgeInsetsDirectional.fromSTEB(
      Space.xxxl,
      Space.xxl,
      Space.xl,
      Space.xxxl,
    ),
  };

  @override
  State<_RailFramed> createState() => _RailFramedState();
}

class _RailFramedState extends State<_RailFramed> {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _askWink();
  }

  @override
  void didUpdateWidget(_RailFramed old) {
    super.didUpdateWidget(old);
    _askWink();
  }

  /// A confirmation plays once, on the rail's mascot.
  void _askWink() {
    if (!widget.wink || _asked) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.winks.value++);
  }

  /// The back control's slot over the column, kept empty at a root.
  Widget _backSlot(BuildContext context) => SizedBox(
    height: 48,
    child: switch (widget.onBack) {
      // The arrow's edge on the column's edge; the button's own inset
      // stands outside it.
      final onBack? => Transform.translate(
        offset: const Offset(-Space.md, 0),
        child: IconButton(
          onPressed: onBack,
          tooltip: 'Voltar',
          color: context.palette.text,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      null => null,
    },
  );

  AlignmentGeometry get _align => widget.pane == Pane.single
      ? Alignment.topCenter
      : AlignmentDirectional.topStart;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: switch (widget.watch) {
        final watch? => LayoutBuilder(
          builder: (context, box) => box.maxWidth >= _RailFramed.watchPaneFrom
              ? _beside(context, watch)
              : _pinned(context, watch),
        ),
        null => SingleChildScrollView(
          padding: _RailFramed.padding(widget.pane),
          child: Align(
            alignment: _align,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _backSlot(context),
                const SizedBox(height: Space.sm),
                widget.task,
              ],
            ),
          ),
        ),
      },
    ),
  );

  /// What is watched in its own pane, under the back control; a hairline;
  /// then the task in its column, which scrolls on its own, its top level
  /// with the watched pane's.
  Widget _beside(BuildContext context, Widget watch) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        // Read first: what is watched, then the task.
        child: FocusTraversalGroup(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.xxxl,
              Space.xxl,
              Space.xl,
              Space.xxxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _backSlot(context),
                const SizedBox(height: Space.sm),
                watch,
              ],
            ),
          ),
        ),
      ),
      VerticalDivider(
        width: 1,
        thickness: 1,
        color: context.palette.outline.withValues(alpha: .5),
      ),
      SizedBox(
        width: widget.width + Space.xxxl + Space.xl,
        child: FocusTraversalGroup(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.xxxl,
              Space.xxl + 48 + Space.sm,
              Space.xl,
              Space.xxxl,
            ),
            child: widget.task,
          ),
        ),
      ),
    ],
  );

  /// The back control and what is watched stay at the top while the task
  /// scrolls beneath them, as long as the task keeps at least half the
  /// height: else the back control scrolls away and what is watched alone
  /// stays, when that leaves the task half; else both scroll with it.
  Widget _pinned(BuildContext context, Widget watch) {
    final p = context.palette;
    final sides = _RailFramed.padding(widget.pane);
    Widget column(Widget child) => Align(
      alignment: _align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.width),
        child: child,
      ),
    );
    return CustomScrollView(
      slivers: [
        PinnedHeader(
          edge: p.outline.withValues(alpha: .5),
          lead: ColoredBox(
            color: p.ground,
            child: Padding(
              padding: sides.copyWith(bottom: Space.sm),
              child: column(_backSlot(context)),
            ),
          ),
          child: ColoredBox(
            color: p.ground,
            child: Padding(
              padding: sides.copyWith(top: 0, bottom: Space.lg),
              child: column(watch),
            ),
          ),
        ),
        SliverPadding(
          padding: sides.copyWith(top: Space.xl),
          sliver: SliverToBoxAdapter(child: column(widget.task)),
        ),
      ],
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.title,
    required this.children,
    required this.width,
    this.titleSemanticsLabel,
    this.leading,
    this.line,
    this.lead,
  });

  final double width;
  final String? title;
  final String? titleSemanticsLabel;
  final Widget? leading;
  final String? line;
  final List<Widget> children;

  /// Body text under the title: the promise, when the field is a band.
  final String? lead;

  /// The title, with its muted line under it and its mark beside both.
  Widget _heading(BuildContext context, String title) {
    final heading = Semantics(
      header: true,
      child: DisplayTitle(title, semanticsLabel: titleSemanticsLabel),
    );
    final line = this.line;
    final leading = this.leading;
    if (line == null && leading == null) return heading;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        if (line != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            line,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: context.palette.muted),
          ),
        ],
      ],
    );
    if (leading == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading,
        const SizedBox(width: Space.lg),
        Expanded(child: text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final title?) ...[
          _heading(context, title),
          if (lead case final lead?) ...[
            const SizedBox(height: Space.md),
            Text(lead, style: Theme.of(context).textTheme.bodyLarge),
          ],
          const SizedBox(height: Space.xl),
        ],
        ...children,
      ],
    ),
  );
}

/// A rounded ink field with [corner], the mascot at [tevi] standing on
/// its top edge.
class _Field extends StatelessWidget {
  const _Field({
    required this.corner,
    required this.tevi,
    required this.child,
    this.wink = false,
    this.expand = false,
  });

  final double corner;
  final double tevi;
  final Widget child;
  final bool wink;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final decoration = BoxDecoration(
      color: p.field,
      borderRadius: BorderRadius.circular(corner),
    );
    return PerchedTevi(
      size: tevi,
      wink: wink,
      corner: corner,
      child: expand
          // The field fills the panel; at large text sizes its content
          // scrolls inside it rather than overflowing.
          ? LayoutBuilder(
              builder: (context, box) => DecoratedBox(
                key: FieldLayout.fieldKey,
                decoration: decoration,
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(child: child),
                  ),
                ),
              ),
            )
          : DecoratedBox(
              key: FieldLayout.fieldKey,
              decoration: decoration,
              child: child,
            ),
    );
  }
}

/// The mascot standing on the top edge of [child], an ink field: whole,
/// at the field's start, facing its content, its legs landing a little
/// into the field. It takes [standOf] its [size] above the field and
/// draws over the field's edge. With [wink], it winks once to confirm.
class PerchedTevi extends StatefulWidget {
  const PerchedTevi({
    super.key,
    required this.size,
    required this.child,
    this.wink = false,
    this.corner = 0,
  });

  /// How long the wink takes: the eye closes, holds and opens again.
  static const winkDuration = Duration(milliseconds: 1400);

  /// The room a mascot [size] wide takes above the field: from the top
  /// of its body down to the edge. The air the figure's box keeps above
  /// the body is left to overhang, since nothing is drawn there.
  static double standOf(double size) =>
      size * (TeviPainter.perchY - TeviPainter.body.top) -
      TeviPainter.perchOverlap;

  final double size;
  final bool wink;
  final Widget child;

  /// The field's corner radius: the app's opening, landing its mascot on
  /// this one, closes its ground onto the field's shape.
  final double corner;

  @override
  State<PerchedTevi> createState() => _PerchedTeviState();
}

class _PerchedTeviState extends State<PerchedTevi>
    with SingleTickerProviderStateMixin {
  late final _wink = AnimationController(
    vsync: this,
    duration: PerchedTevi.winkDuration,
  );

  /// The eyelid over the wink: it shuts quickly, stays shut long enough
  /// to be read, then opens more gently.
  late final _lid = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Motion.shut)),
      weight: 20,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Motion.sway)),
      weight: 40,
    ),
  ]).animate(_wink);

  bool _played = false;

  /// The field it stands on, for the app's opening to close onto.
  final _field = GlobalKey();

  /// Under reduced motion the wink is shown, not played: the eye stays
  /// shut until this ends.
  Timer? _shut;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _play();
  }

  /// A confirmation on a screen already shown (the family just created)
  /// turns the wink on in place.
  @override
  void didUpdateWidget(PerchedTevi old) {
    super.didUpdateWidget(old);
    if (!old.wink) _play();
  }

  void _play() {
    if (!widget.wink || _played) return;
    _played = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _shut = Timer(PerchedTevi.winkDuration, () {
        if (mounted) setState(() => _shut = null);
      });
    } else {
      _wink.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shut?.cancel();
    _wink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // On the dark theme's ground the figure's dark parts would vanish, so
    // they take the night colours there, unless the screen says which
    // ground it stands on.
    final night =
        TeviGround.maybeNightAt(context) ??
        context.palette.brightness == Brightness.dark;
    final figure = AnimatedBuilder(
      animation: _lid,
      // The wink moves the look itself, frame by frame.
      builder: (context, _) => Tevi(
        size: size,
        night: night,
        eases: false,
        look: _shut != null
            ? TeviLook.winking
            : TeviLook.lerp(TeviLook.watching, TeviLook.winking, _lid.value),
      ),
    );
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(top: PerchedTevi.standOf(size)),
          child: KeyedSubtree(key: _field, child: widget.child),
        ),
        // The figure's box is square and drawn facing the end side; its
        // legs end at [TeviPainter.perchY] of its height.
        PositionedDirectional(
          top: -size * TeviPainter.body.top,
          start: TeviPainter.perchInset - size * TeviPainter.body.left,
          width: size,
          height: size,
          child: TeviLanding(
            look: TeviLook.watching,
            night: night,
            flipped: Directionality.of(context) == TextDirection.rtl,
            field: _field,
            fieldCorner: widget.corner,
            child: IgnorePointer(
              child: Transform.flip(
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: figure,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldContent extends StatelessWidget {
  const _FieldContent({
    required this.size,
    this.onBack,
    this.large = false,
    this.promise = promiseLine,
  });

  final FieldSize size;

  /// The promise at the field's foot; null leaves the field to the wordmark.
  final String? promise;
  final VoidCallback? onBack;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // The name plate starts under the mascot's body, on the edge the text
    // below it keeps, so figure, name and text read down one line.
    final wordmark = Wordmark(
      height: size == FieldSize.hero ? WordmarkSizes.hero : WordmarkSizes.band,
    );
    final back = onBack == null
        ? null
        : IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            color: p.onField,
            icon: const Icon(Icons.arrow_back_rounded),
          );
    if (size == FieldSize.band) {
      // A back control keeps the band's start; the name plate follows it
      // at the band's own spacing.
      return Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          back == null ? TeviPainter.perchInset : Space.sm,
          Space.sm,
          Space.sm,
          Space.sm,
        ),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              if (back != null) ...[back, const SizedBox(width: Space.sm)],
              wordmark,
            ],
          ),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        TeviPainter.perchInset,
        back == null ? Space.xl : Space.sm,
        TeviPainter.perchInset,
        large ? Space.xxxl : Space.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: large
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: [
          // Back and wordmark stay one top group; only the promise goes to
          // the foot of the wide field.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (back != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Transform.translate(
                    offset: const Offset(-Space.md, 0),
                    child: back,
                  ),
                ),
              wordmark,
            ],
          ),
          if (promise case final promise?) ...[
            // Further from the name plate than the plate is from the edge.
            SizedBox(height: large ? Space.xxxl : Space.xxl),
            Text(
              promise,
              style: (large ? text.displayLarge : text.headlineSmall)?.copyWith(
                color: p.onField,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
