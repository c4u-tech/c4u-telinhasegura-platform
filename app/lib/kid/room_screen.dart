import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../curation/curation.dart' show VideoTheme;
import '../curation/kid_catalog.dart';
import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'hold_to_exit.dart';
import 'kid_day.dart';
import 'kid_error_note.dart';
import 'kid_layout.dart';
import 'player_keys.dart';
import 'player_screen.dart';
import 'shelves.dart';
import 'tap_guard.dart';
import 'theme_glyph.dart';

/// What the home hands the page it opens: the day it read, and where the
/// door that opened it stood. A page reached any other way (a reload, a
/// typed address) has neither, and goes back to the home.
class RoomDoor {
  const RoomDoor({required this.day, this.from});

  final KidDay day;
  final Rect? from;
}

/// `/crianca/tema/:tema`: one theme's small room. The theme's world fills
/// the screen; a large back key at the top start with the theme's glyph
/// beside it, the exit at the end; the theme's first video large with
/// the play disc, the rest in two columns (from 840 px, a grid beside and
/// beneath it), every one a tap from playing. The videos are the ones the
/// home read: the page asks for nothing when it opens. A video longer
/// than the time left rests in its place, as on the home. The page goes
/// back to the home when its theme is gone from the catalogue, when the
/// day ends, or when it was opened without the home's day.
class RoomScreen extends StatefulWidget {
  const RoomScreen.theme({super.key, required VideoTheme this.theme, this.day});

  /// The theme shown.
  final VideoTheme? theme;

  /// The home's day; null when the page was reached without it.
  final KidDay? day;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  bool _started = false;
  bool _leaving = false;

  /// What the page lists, as last read: it stays while the catalogue is
  /// read again after a refusal.
  List<KidVideo> _videos = const [];

  ColourWorld get _world => worldOf(widget.theme ?? VideoTheme.unknown);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final day = widget.day;
    if (day == null) return _leave();
    day.addListener(_onDay);
    _onDay();
  }

  @override
  void dispose() {
    widget.day?.removeListener(_onDay);
    super.dispose();
  }

  List<KidVideo> _of(KidCatalog catalog) => [
    for (final shelf in catalog.shelves)
      if (shelf.theme == widget.theme) ...shelf.videos,
  ];

  void _onDay() {
    final day = widget.day!;
    if (day.waiting || day.failed) return _leave();
    if (day.catalog case final catalog?) {
      final videos = _of(catalog);
      if (videos.isEmpty) return _leave();
      _videos = videos;
    }
    if (mounted) setState(() {});
  }

  /// Back to the home, once, after the frame that found the reason.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(Routes.kidHome);
    });
  }

  /// The player stands over the page, so its end comes back here.
  void _open(String location, Object extra) =>
      unawaited(GoRouter.of(context).push<void>(location, extra: extra));

  void _play(KidVideo video) => unawaited(widget.day!.play(video, open: _open));

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final world = _world;
    final exit = HoldToExit(
      color: world.figure,
      onExit: () {
        AppScope.of(context).moreTimeErrand = false;
        context.go(Routes.kidExit);
      },
    );
    final lead = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoomBack(world: world, onPressed: () => context.go(Routes.kidHome)),
        const SizedBox(width: Space.md),
        ThemeGlyph(
          widget.theme ?? VideoTheme.unknown,
          size: RoomBack.glyph,
          color: world.figure,
          ground: world.ground,
        ),
      ],
    );
    final ready = day != null && _videos.isNotEmpty;
    final onPlay = !ready || day.pending || day.catalog == null ? null : _play;
    return TapGuard(
      child: LayoutBuilder(
        builder: (context, box) {
          final g = _RoomGeometry.of(
            box,
            wide: MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint,
            tevi: _standsOn(world),
          );
          return KidLayout(
            ground: world.ground,
            exit: exit,
            lead: lead,
            leadInset: KidLayout.exitInset,
            fullWidth: true,
            scrolls: false,
            rise: g.rise,
            child: !ready
                ? const SizedBox.shrink()
                : _RoomArrangement(
                    geometry: g,
                    world: world,
                    note: switch (day.notice) {
                      final notice? => RoomNote(notice, world: world),
                      null => null,
                    },
                    lead: _video(_videos.first, g.lead, g, onPlay, lead: true),
                    rest: [
                      for (final v in _videos.skip(1))
                        _video(v, g.tile, g, onPlay),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _video(
    KidVideo video,
    Size size,
    _RoomGeometry g,
    ValueChanged<KidVideo>? onPlay, {
    bool lead = false,
  }) => VideoTile(
    video: video,
    size: size,
    thumbnail: widget.day!.thumbnail,
    radius: lead ? FieldSizes.heroCorner : Radii.card,
    resting: !video.fits,
    playDisc: lead,
    playDiscScale: RoomBack.disc / PlayDisc.size,
    world: _world,
    onTap: onPlay == null ? null : () => onPlay(video),
  );
}

/// The mascot is drawn only on the home's ink and on the night's dark.
bool _standsOn(ColourWorld world) =>
    world.ground == BrandColors.ink || world.ground == BrandColors.dark;

/// A page's measures for the room it has.
class _RoomGeometry {
  const _RoomGeometry({
    required this.wide,
    required this.inset,
    required this.lead,
    required this.tile,
    required this.gap,
    required this.tevi,
  });

  factory _RoomGeometry.of(
    BoxConstraints box, {
    required bool wide,
    required bool tevi,
  }) {
    final inset = wide ? _insetWide : _inset;
    final room = box.maxWidth - 2 * inset;
    final gap = wide ? Space.lg : Space.md;
    // A phone's column stays a phone's: two columns under the first
    // video. Wide, four columns, the first video taking two of them.
    final column = math.min(room, _maxColumn);
    final tw = wide ? (room - 3 * gap) / 4 : (column - gap) / 2;
    final lw = wide ? 2 * tw + gap : column;
    return _RoomGeometry(
      wide: wide,
      inset: inset,
      lead: Size(lw, lw * 9 / 16),
      tile: Size(tw, tw * 9 / 16),
      gap: gap,
      tevi: tevi ? (wide ? _teviWide : _tevi) : null,
    );
  }

  static const _inset = 20.0;
  static const _insetWide = 48.0;
  static const _maxColumn = 600.0;
  static const _tevi = 80.0;
  static const _teviWide = 104.0;

  /// Between the strip and the first video.
  static const top = Space.sm;
  static const bottom = Space.lg;

  final bool wide;
  final double inset;
  final Size lead;
  final Size tile;
  final double gap;

  /// The mascot's size on the first video, where it stands.
  final double? tevi;

  /// The room the mascot standing on the first video takes above it.
  double get stand => switch (tevi) {
    final size? =>
      size * (TeviPainter.perchY - TeviPainter.top) - TeviPainter.perchOverlap,
    null => 0,
  };

  /// How far the page reaches up into the strip: the mascot's head, while
  /// the first video keeps its place below the strip.
  double get rise => math.max(0, stand - top);
}

/// Lays the page's videos out for its [geometry], in one scrolling screen.
class _RoomArrangement extends StatelessWidget {
  const _RoomArrangement({
    required this.geometry,
    required this.world,
    required this.lead,
    required this.rest,
    this.note,
  });

  final _RoomGeometry geometry;
  final ColourWorld world;
  final Widget? note;
  final Widget lead;
  final List<Widget> rest;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    Widget row(Iterable<Widget> tiles) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, t) in tiles.indexed) ...[
          if (i > 0) SizedBox(width: g.gap),
          t,
        ],
      ],
    );
    Widget rows(List<Widget> tiles, int across) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tiles.length; i += across) ...[
          if (i > 0) SizedBox(height: g.gap),
          row(tiles.sublist(i, math.min(i + across, tiles.length))),
        ],
      ],
    );
    final first = _Standing(
      geometry: g,
      night: world.ground == BrandColors.dark,
      child: lead,
    );
    final Widget body;
    if (g.wide) {
      // Beside the first video, two rows of two; then rows of four.
      final beside = rest.take(4).toList();
      final beneath = rest.skip(4).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              first,
              if (beside.isNotEmpty) ...[
                SizedBox(width: g.gap),
                Padding(
                  padding: EdgeInsets.only(top: g.stand),
                  child: rows(beside, 2),
                ),
              ],
            ],
          ),
          if (beneath.isNotEmpty) ...[
            SizedBox(height: g.gap),
            rows(beneath, 4),
          ],
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          first,
          if (rest.isNotEmpty) ...[SizedBox(height: g.gap), rows(rest, 2)],
        ],
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: g.tevi == null ? _RoomGeometry.top : 0,
        bottom: _RoomGeometry.bottom,
      ),
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Below the strip, clear of the back key and the exit.
            if (note case final note?)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  g.inset,
                  g.rise,
                  g.inset,
                  Space.xl,
                ),
                child: note,
              ),
            Center(child: body),
          ],
        ),
      ),
    );
  }
}

/// The first video, with the mascot standing on its top edge toward the
/// end, between the glyph and the exit, where the ground lets it stand.
class _Standing extends StatelessWidget {
  const _Standing({
    required this.geometry,
    required this.night,
    required this.child,
  });

  final _RoomGeometry geometry;
  final bool night;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = geometry.tevi;
    if (size == null) return child;
    final stand = geometry.stand;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(top: stand),
          child: child,
        ),
        PositionedDirectional(
          top: stand + TeviPainter.perchOverlap - size * TeviPainter.perchY,
          start:
              geometry.lead.width * 2 / 3 - size * TeviPainter.body.center.dx,
          width: size,
          height: size,
          child: IgnorePointer(
            child: Transform.flip(
              flipX: Directionality.of(context) == TextDirection.rtl,
              child: Tevi(size: size, night: night),
            ),
          ),
        ),
      ],
    );
  }
}

/// A page's way back to the home: a large round key in the world's
/// figure with the player's back arrow cut in its ground, at the top
/// start, never near the bottom edge. Read "Voltar".
class RoomBack extends StatefulWidget {
  const RoomBack({super.key, required this.world, required this.onPressed});

  final ColourWorld world;
  final VoidCallback onPressed;

  /// The glyph beside the key.
  static const glyph = 48.0;

  /// The play disc on the first video.
  static const disc = 64.0;

  @override
  State<RoomBack> createState() => _RoomBackState();
}

class _RoomBackState extends State<RoomBack> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.world;
    final ring = _focused
        ? BorderSide(
            color: w.figure,
            width: 3,
            strokeAlign: BorderSide.strokeAlignOutside,
          )
        : BorderSide.none;
    return Semantics(
      container: true,
      button: true,
      label: PlayerScreen.back,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: KidSizes.target,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(shape: CircleBorder(side: ring)),
            child: Material(
              color: w.figure,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onPressed,
                onFocusChange: (f) => setState(() => _focused = f),
                focusColor: Colors.transparent,
                hoverColor: w.ground.withValues(alpha: .08),
                highlightColor: w.ground.withValues(alpha: .16),
                splashColor: w.ground.withValues(alpha: .16),
                child: CustomPaint(
                  painter: PlayerGlyphPainter(PlayerGlyph.back, w.ground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The kid error note on a theme's world: on the night's dark, where its
/// cream line and the mascot read on any ground.
class RoomNote extends StatelessWidget {
  const RoomNote(this.message, {super.key, required this.world});

  final String message;
  final ColourWorld world;

  @override
  Widget build(BuildContext context) {
    final note = KidErrorNote(message, asleep: restsNote(message));
    if (world.ground == context.palette.ground) return note;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.dark,
        borderRadius: BorderRadius.all(Radius.circular(Radii.card)),
      ),
      child: Padding(padding: const EdgeInsets.all(Space.lg), child: note),
    );
  }
}
