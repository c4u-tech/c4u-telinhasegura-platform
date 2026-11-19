import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../curation/curation.dart' show VideoTheme;
import '../curation/kid_catalog.dart';
import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart' show AgeBand;
import 'kid_error_note.dart';
import 'kid_layout.dart';
import 'pack_row.dart';
import 'room_transition.dart';
import 'shelves.dart';
import 'theme_glyph.dart';

/// What the child home shows of a catalogue, chosen on the device from the
/// catalogue as delivered: the day's highlight (the first pacotinho, else
/// the first video of the first theme), up to two pictures that play at
/// one tap (the first videos of the themes that follow, never the
/// highlight's picture again), and one block per theme that has videos,
/// in the catalogue's order. A day with more pacotinhos than the one it
/// leads with gives the pictures' place to a door to all of them. A child
/// up to 4 gets no small pictures: one large picture and the blocks are
/// enough to choose from, with the pacotinhos' door between them on such
/// a day.
class MosaicPlan {
  const MosaicPlan._({
    required this.pack,
    required this.video,
    required this.pictures,
    required this.blocks,
    required this.packs,
    required this.packsDoor,
  });

  factory MosaicPlan.of(KidCatalog catalog, {required AgeBand band}) {
    final blocks = [
      for (final shelf in catalog.shelves)
        if (shelf.videos.isNotEmpty) shelf,
    ];
    final pack = catalog.packs.firstOrNull;
    final video = pack == null ? blocks.firstOrNull?.videos.first : null;
    // A pacotinho stands for every theme, so the pictures start from the
    // first; a video stands for its own, so they start after it.
    final from = pack != null ? blocks : blocks.skip(1);
    final shown = pack?.coverVideoId ?? video?.id;
    final packsDoor = catalog.packs.length > 1;
    return MosaicPlan._(
      pack: pack,
      video: video,
      pictures: band == AgeBand.upTo4 || packsDoor
          ? const []
          : [
              for (final shelf in from)
                if (shelf.videos.first.id != shown) shelf.videos.first,
            ].take(maxPictures).toList(),
      blocks: blocks,
      packs: catalog.packs,
      packsDoor: packsDoor,
    );
  }

  static const maxPictures = 2;

  /// The highlight when the day has a pacotinho; [video] otherwise.
  final KidPack? pack;
  final KidVideo? video;
  final List<KidVideo> pictures;
  final List<KidShelf> blocks;

  /// Every pacotinho of the day, the first leading.
  final List<KidPack> packs;

  /// The pacotinhos after the first have a door of their own, in the
  /// pictures' place.
  final bool packsDoor;

  /// Nothing to watch today: no pacotinho and no video in any theme.
  bool get isEmpty => pack == null && video == null;
}

/// The child home's one screen: the highlight with the mascot standing on
/// it, the one-tap pictures, and the theme blocks in two columns. On a
/// phone they stand one under the other; from 840 px the highlight and
/// the pictures take the start and the blocks the end, both columns
/// ending on one line. On a phone the blocks grow to fill the screen's
/// height, up to a size that still reads as a block, so today's
/// catalogue needs no scrolling; with more than fits, or larger text,
/// the screen scrolls.
class KidMosaic extends StatelessWidget {
  const KidMosaic({
    super.key,
    required this.catalog,
    required this.band,
    required this.thumbnail,
    required this.onPlay,
    required this.onOpenPack,
    required this.onOpenTheme,
    this.onOpenPacks,
    this.note,
    this.plan,
  });

  final KidCatalog catalog;

  /// What to show of [catalog], when the screen around it already chose;
  /// otherwise chosen here.
  final MosaicPlan? plan;

  /// The child's age band, which tunes how many pictures and how large
  /// the blocks are.
  final AgeBand band;
  final ThumbnailLoader thumbnail;

  /// Null while a play is pending, so further taps do nothing.
  final ValueChanged<KidVideo>? onPlay;
  final ValueChanged<KidPack>? onOpenPack;

  /// A theme's block was tapped, standing [from] on the screen.
  final void Function(VideoTheme theme, DoorPlace from)? onOpenTheme;

  /// The door to every pacotinho was tapped, standing at the given place.
  final ValueChanged<DoorPlace>? onOpenPacks;

  /// Floating over the home's foot (a refusal's note).
  final Widget? note;

  /// The child's avatar at the strip's start: a small "this is you".
  static const avatar = 48.0;

  /// How far the home reaches up into the strip: the mascot's head stands
  /// there, between the avatar and the exit.
  static const rise = 64.0;

  @override
  Widget build(BuildContext context) {
    final plan = this.plan ?? MosaicPlan.of(catalog, band: band);
    return LayoutBuilder(
      builder: (context, box) {
        final g = _Geometry.of(
          box,
          wide: MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint,
          pack: plan.pack != null,
          pictures: plan.pictures.isNotEmpty,
          door: plan.packsDoor,
          blocks: plan.blocks.length,
          grow: band == AgeBand.upTo4,
        );
        final lead = _Highlight(
          geometry: g,
          child: HighlightPicture(
            pack: plan.pack,
            video: plan.video,
            size: g.highlight,
            thumbnail: thumbnail,
            onPlay: onPlay,
            onOpenPack: onOpenPack,
          ),
        );
        final pictures = [
          for (final v in plan.pictures)
            OneTapPicture(
              video: v,
              size: g.picture,
              thumbnail: thumbnail,
              onTap: onPlay == null ? null : () => onPlay!(v),
            ),
        ];
        final packs = plan.packs;
        final door = !plan.packsDoor
            ? null
            : Builder(
                key: _packsKey,
                builder: (context) => PacksDoor(
                  size: Size(g.start, g.door),
                  // The next pacotinho in front, another peeking behind.
                  covers: [
                    packs[1].coverVideoId,
                    packs[packs.length > 2 ? 2 : 0].coverVideoId,
                  ],
                  thumbnail: thumbnail,
                  wide: g.wide,
                  onTap: onOpenPacks == null
                      ? null
                      : () => onOpenPacks!(_placeOf(context, _packsKey)),
                ),
              );
        final blocks = [
          for (final shelf in plan.blocks)
            Builder(
              key: _keyOf(shelf.theme),
              builder: (context) => ThemeBlock(
                shelf: shelf,
                world: worldOf(shelf.theme),
                size: g.block,
                wide: g.wide,
                thumbnail: thumbnail,
                onTap: onOpenTheme == null
                    ? null
                    : () => onOpenTheme!(
                        shelf.theme,
                        _placeOf(context, _keyOf(shelf.theme)),
                      ),
              ),
            ),
        ];
        return _Arrangement(
          geometry: g,
          note: note,
          lead: lead,
          pictures: pictures,
          door: door,
          blocks: blocks,
        );
      },
    );
  }
}

/// Each door keeps its key from build to build, so a page opened from it
/// finds it again when it goes back, wherever it stands then.
GlobalKey _keyOf(VideoTheme theme) => _doorKeys[theme]!;
final _doorKeys = {
  for (final theme in VideoTheme.values)
    theme: GlobalKey(debugLabel: 'door ${theme.name}'),
};
final _packsKey = GlobalKey(debugLabel: 'door pacotinhos');

/// Where the door at [context] stands on the screen, how to find it
/// again through [key], and a picture of what it shows.
DoorPlace _placeOf(BuildContext context, GlobalKey key) => DoorPlace(
  _rectOf(context)!,
  measure: () => switch (key.currentContext) {
    final context? => _rectOf(context),
    null => null,
  },
  face: faceOf(context),
);

/// Where the widget at [context] stands on the screen, if it is laid out.
Rect? _rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The home's measures for the room it has.
class _Geometry {
  const _Geometry({
    required this.wide,
    required this.inset,
    required this.start,
    required this.end,
    required this.tevi,
    required this.highlight,
    required this.picture,
    required this.door,
    required this.block,
    required this.gap,
    required this.blockGap,
    required this.lift,
  });

  factory _Geometry.of(
    BoxConstraints box, {
    required bool wide,
    required bool pack,
    required bool pictures,
    required int blocks,
    required bool grow,
    bool door = false,
  }) {
    final inset = wide ? KidLayout.insetWide : KidLayout.inset;
    final room = box.maxWidth - 2 * inset;
    // A phone's column stays a phone's: on a wider narrow window it is
    // centred rather than stretched.
    final column = math.min(room, KidLayout.column);
    final start = wide ? (room - _between) * 11 / 21 : column;
    final end = wide ? room - _between - start : column;
    final gap = Space.md;
    final blockGap = wide ? Space.lg : Space.md;
    final tevi = wide ? _teviWide : _tevi;
    final highlight = Size(start, start * 9 / 16);
    final pw = (start - gap) / 2;
    final picture = Size(pw, pw * 9 / 16);
    // The pacotinhos' door: a band as tall as a picture's row, never
    // under a child's target nor taller than a phone's row.
    final band = picture.height.clamp(KidSizes.target, _doorMax);
    final bw = (end - blockGap) / 2;
    final rows = (blocks / 2).ceil();
    // What stands above and below the blocks, in their column.
    final above =
        _standOf(tevi) +
        (wide
            ? 0
            : highlight.height +
                  (pack ? PackTile.below : 0) +
                  (door
                      ? gap + band
                      : pictures
                      ? gap + picture.height
                      : 0) +
                  gap);
    final fill = rows == 0
        ? 0.0
        : (box.maxHeight - above - _bottom - (rows - 1) * blockGap) / rows;
    // On a phone, up to a size that still reads as a block.
    final ratio = grow ? .90 : .70;
    final low = math.max(KidSizes.target, bw * .50);
    final high = math.max(low, bw * ratio);
    // From 840 px the blocks' column ends where the start column does,
    // so the home reads as one block of two columns. For the youngest,
    // who have no pictures beside the highlight, the blocks grow into
    // the height instead, and the start column stands centred against
    // them.
    final startHeight =
        highlight.height +
        (pack ? PackTile.below : 0) +
        (door
            ? gap + band
            : pictures
            ? gap + picture.height
            : 0);
    final even = rows == 0 ? 0.0 : (startHeight - (rows - 1) * blockGap) / rows;
    final height = wide
        ? (grow ? fill.clamp(low, high) : math.max(low, even))
        : fill.clamp(low, high);
    final grid = rows == 0 ? 0.0 : rows * height + (rows - 1) * blockGap;
    return _Geometry(
      wide: wide,
      inset: inset,
      start: start,
      end: end,
      tevi: tevi,
      highlight: highlight,
      picture: picture,
      door: band,
      block: Size(bw, height),
      lift: wide ? math.max(0.0, (grid - startHeight) / 2) : 0,
      gap: gap,
      blockGap: blockGap,
    );
  }

  /// Between the start column and the blocks, from 840 px.
  static const _between = 40.0;
  static const _tevi = 104.0;
  static const _teviWide = 128.0;

  /// The pacotinhos' door's tallest.
  static const _doorMax = 112.0;

  /// The air above the mascot's raised crest.
  static const _air = Space.sm;
  static const _bottom = Space.lg;

  /// The room the mascot standing on the highlight takes above it, crest
  /// raised, with its air.
  static double _standOf(double size) =>
      size * (TeviPainter.perchY - TeviPainter.top) -
      TeviPainter.perchOverlap +
      _air;

  final bool wide;
  final double inset;
  final double start;
  final double end;
  final double tevi;
  final Size highlight;
  final Size picture;

  /// The pacotinhos' door's height.
  final double door;
  final Size block;
  final double gap;
  final double blockGap;

  /// How far the start column stands below the blocks' top, from 840 px,
  /// to sit centred against a taller column of blocks.
  final double lift;

  double get stand => _standOf(tevi);
  double get bottom => _bottom;
}

/// The highlight with the mascot standing on its top edge, crest raised,
/// its body over the picture's middle, in the colours of the ground
/// behind it.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.geometry, required this.child, this.look});

  final _Geometry geometry;
  final Widget child;
  final TeviLook? look;

  @override
  Widget build(BuildContext context) {
    final size = geometry.tevi;
    final stand = geometry.stand;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(top: stand),
          child: child,
        ),
        Positioned(
          top: stand + TeviPainter.perchOverlap - size * TeviPainter.perchY,
          left:
              geometry.highlight.width / 2 - size * TeviPainter.body.center.dx,
          width: size,
          height: size,
          child: IgnorePointer(
            child: MascotUnderNote(
              child: FacingTevi(size: size, look: look ?? TeviLook.crestUp),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lays the home's parts out for its [geometry], in one scrolling screen.
class _Arrangement extends StatelessWidget {
  const _Arrangement({
    required this.geometry,
    required this.lead,
    required this.pictures,
    required this.blocks,
    this.door,
    this.note,
  });

  final _Geometry geometry;
  final Widget? note;
  final Widget lead;
  final List<Widget> pictures;

  /// The pacotinhos' door, in the pictures' place.
  final Widget? door;
  final List<Widget> blocks;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    Widget pair(List<Widget> two, double gap) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        two[0],
        if (two.length > 1) ...[SizedBox(width: gap), two[1]],
      ],
    );
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i += 2) ...[
          if (i > 0) SizedBox(height: g.blockGap),
          pair(blocks.sublist(i, math.min(i + 2, blocks.length)), g.blockGap),
        ],
      ],
    );
    final start = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        lead,
        if (door case final door?) ...[
          SizedBox(height: g.gap),
          door,
        ] else if (pictures.isNotEmpty) ...[
          SizedBox(height: g.gap),
          pair(pictures, g.gap),
        ],
      ],
    );
    final body = g.wide
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: g.lift),
                child: SizedBox(width: g.start, child: start),
              ),
              const SizedBox(width: _Geometry._between),
              Padding(
                padding: EdgeInsets.only(top: g.stand),
                child: SizedBox(width: g.end, child: grid),
              ),
            ],
          )
        : SizedBox(
            width: g.start,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                start,
                if (blocks.isNotEmpty) ...[SizedBox(height: g.gap), grid],
              ],
            ),
          );
    // A note floats over the home's foot, below the strip, and never
    // moves the pictures under the child's hand.
    return NoteOver(
      note: note,
      top: KidMosaic.rise,
      content: (room) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: g.bottom + room),
        child: Center(child: body),
      ),
    );
  }
}

/// The day's highlight: the pacotinho's cover with its modules beneath,
/// or the video's picture, large, with the play disc in its corner. It
/// plays at a tap as any picture does.
class HighlightPicture extends StatelessWidget {
  const HighlightPicture({
    super.key,
    required this.pack,
    required this.video,
    required this.size,
    required this.thumbnail,
    required this.onPlay,
    required this.onOpenPack,
  });

  final KidPack? pack;
  final KidVideo? video;
  final Size size;
  final ThumbnailLoader thumbnail;
  final ValueChanged<KidVideo>? onPlay;
  final ValueChanged<KidPack>? onOpenPack;

  /// The play disc's diameter on the highlight.
  static const disc = 64.0;

  @override
  Widget build(BuildContext context) {
    const scale = disc / PlayDisc.size;
    if (pack case final pack?) {
      return PackTile(
        pack: pack,
        size: size,
        thumbnail: thumbnail,
        radius: FieldSizes.heroCorner,
        playDiscScale: scale,
        onTap: onOpenPack == null ? null : () => onOpenPack!(pack),
      );
    }
    final video = this.video;
    if (video == null) return SizedBox.fromSize(size: size);
    return VideoTile(
      video: video,
      size: size,
      thumbnail: thumbnail,
      radius: FieldSizes.heroCorner,
      resting: !video.fits,
      playDisc: true,
      playDiscScale: scale,
      onTap: onPlay == null ? null : () => onPlay!(video),
    );
  }
}

/// A picture that plays at one tap, with a small play disc: the first
/// video of a theme.
class OneTapPicture extends StatelessWidget {
  const OneTapPicture({
    super.key,
    required this.video,
    required this.size,
    required this.thumbnail,
    required this.onTap,
  });

  final KidVideo video;
  final Size size;
  final ThumbnailLoader thumbnail;
  final VoidCallback? onTap;

  /// The play disc's diameter on a picture.
  static const disc = 32.0;

  @override
  Widget build(BuildContext context) => VideoTile(
    video: video,
    size: size,
    thumbnail: thumbnail,
    radius: Radii.card,
    resting: !video.fits,
    playDisc: true,
    playDiscScale: disc / PlayDisc.size,
    onTap: onTap,
  );
}

/// A theme's door: its colour world's ground, its glyph small at the top
/// start, the cover of its first video large at the bottom end and, when
/// it has a second, that one's cover peeking out behind. One button, read
/// by the theme's name; nothing written on it.
class ThemeBlock extends StatefulWidget {
  const ThemeBlock({
    super.key,
    required this.shelf,
    required this.world,
    required this.size,
    required this.thumbnail,
    required this.onTap,
    this.wide = false,
  });

  final KidShelf shelf;
  final ColourWorld world;
  final Size size;
  final ThumbnailLoader thumbnail;
  final VoidCallback? onTap;

  /// From 840 px: a larger glyph and padding.
  final bool wide;

  /// How far the cover behind shows above the front one, and how much
  /// narrower it is on each side.
  static const peek = 10.0;

  @override
  State<ThemeBlock> createState() => _ThemeBlockState();
}

class _ThemeBlockState extends State<ThemeBlock> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = widget.world;
    final size = widget.size;
    final pad = widget.wide ? Space.lg : Space.md;
    final glyph = widget.wide ? 36.0 : 28.0;
    // The cover takes most of the width, and no more of the height than
    // leaves room for the one peeking behind it.
    final coverW = math.min(
      size.width * .68,
      (size.height - pad - ThemeBlock.peek - Space.xs) * 16 / 9,
    );
    final cover = Size(coverW, coverW * 9 / 16);
    final front = Rect.fromLTWH(
      size.width - Space.md - cover.width,
      size.height - Space.md - cover.height,
      cover.width,
      cover.height,
    );
    final videos = widget.shelf.videos;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.card),
    );
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    return Semantics(
      container: true,
      button: true,
      enabled: widget.onTap != null,
      label: themeName(widget.shelf.theme),
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: size,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: shape.copyWith(side: ring ?? BorderSide.none),
            ),
            child: Material(
              color: w.ground,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // What the door shows above its ground, pictured
                  // as the page grows out of it.
                  Positioned.fill(
                    child: DoorFace(
                      child: Stack(
                        children: [
                          PositionedDirectional(
                            start: pad,
                            top: pad,
                            child: ThemeGlyph(
                              widget.shelf.theme,
                              size: glyph,
                              color: w.figure,
                              ground: w.ground,
                            ),
                          ),
                          if (videos.length > 1)
                            PositionedDirectional(
                              end: Space.md + ThemeBlock.peek,
                              top: front.top - ThemeBlock.peek,
                              width: cover.width - 2 * ThemeBlock.peek,
                              height: cover.height,
                              child: BlockCover(
                                videoId: videos[1].id,
                                thumbnail: widget.thumbnail,
                                color: w.figure,
                              ),
                            ),
                          PositionedDirectional(
                            end: Space.md,
                            top: front.top,
                            width: cover.width,
                            height: cover.height,
                            child: BlockCover(
                              videoId: videos.first.id,
                              thumbnail: widget.thumbnail,
                              color: w.figure,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: InkWell(
                      onTap: widget.onTap,
                      canRequestFocus: true,
                      onFocusChange: (f) => setState(() => _focused = f),
                      focusColor: Colors.transparent,
                      hoverColor: w.figure.withValues(alpha: .08),
                      highlightColor: w.figure.withValues(alpha: .12),
                      splashColor: w.figure.withValues(alpha: .12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The door to every pacotinho of the day, in the one-tap pictures' place:
/// a band the content's width, filled with the input tone (apart from the
/// home's ground and from every theme's world), the pacotinhos' sign at
/// its start and, at its end, the next pacotinho's cover with another
/// peeking behind it. One button, read "Pacotinhos".
class PacksDoor extends StatefulWidget {
  const PacksDoor({
    super.key,
    required this.size,
    required this.onTap,
    this.covers = const [],
    this.thumbnail,
    this.wide = false,
  });

  final Size size;
  final VoidCallback? onTap;

  /// The videos whose pictures stand as covers: the front one first.
  final List<String> covers;
  final ThumbnailLoader? thumbnail;
  final bool wide;

  @override
  State<PacksDoor> createState() => _PacksDoorState();
}

class _PacksDoorState extends State<PacksDoor> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final figure = ColourWorlds.home.figure;
    final size = widget.size;
    final pad = widget.wide ? Space.lg : Space.md;
    final glyph = widget.wide ? 56.0 : 48.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.card),
    );
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    // The front cover fills the band's height below the peek, and keeps
    // clear of the sign.
    final coverH = math.max(
      0.0,
      size.height - Space.md - ThemeBlock.peek - Space.sm,
    );
    final coverW = math.min(
      coverH * 16 / 9,
      size.width - 2 * pad - glyph - Space.md,
    );
    final cover = Size(coverW, coverW * 9 / 16);
    final thumbnail = widget.thumbnail;
    final covers = thumbnail == null ? const <String>[] : widget.covers;
    return Semantics(
      container: true,
      button: true,
      enabled: widget.onTap != null,
      label: PackGlyph.label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: size,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: shape.copyWith(side: ring ?? BorderSide.none),
            ),
            child: Material(
              color: p.input,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // What the door shows above its ground, pictured
                  // as the page grows out of it.
                  Positioned.fill(
                    child: DoorFace(
                      child: Stack(
                        children: [
                          PositionedDirectional(
                            start: pad,
                            top: (size.height - glyph) / 2,
                            child: PackGlyph(size: glyph, color: figure),
                          ),
                          if (covers.length > 1)
                            PositionedDirectional(
                              end: Space.md + ThemeBlock.peek,
                              bottom: Space.md + ThemeBlock.peek,
                              width: cover.width - 2 * ThemeBlock.peek,
                              height: cover.height,
                              child: BlockCover(
                                videoId: covers[1],
                                thumbnail: thumbnail!,
                                color: figure,
                              ),
                            ),
                          if (covers.isNotEmpty)
                            PositionedDirectional(
                              end: Space.md,
                              bottom: Space.md,
                              width: cover.width,
                              height: cover.height,
                              child: BlockCover(
                                videoId: covers.first,
                                thumbnail: thumbnail!,
                                color: figure,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: InkWell(
                      onTap: widget.onTap,
                      onFocusChange: (f) => setState(() => _focused = f),
                      focusColor: Colors.transparent,
                      hoverColor: figure.withValues(alpha: .08),
                      highlightColor: figure.withValues(alpha: .12),
                      splashColor: figure.withValues(alpha: .12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A cover inside a theme's block: a picture, not a target of its own.
class BlockCover extends StatelessWidget {
  const BlockCover({
    super.key,
    required this.videoId,
    required this.thumbnail,
    required this.color,
  });

  final String videoId;
  final ThumbnailLoader thumbnail;

  /// The world's figure, for a cover that did not come.
  final Color color;

  /// The corner, against the cover's height: as the highlight's is
  /// against its own.
  static const ratio = FieldSizes.heroCorner / 197;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final radius = box.maxHeight * ratio;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ThumbnailPicture(
          videoId: videoId,
          thumbnail: thumbnail,
          radius: radius,
          color: color,
        ),
      );
    },
  );
}

/// The home while the catalogue loads: its shapes as quiet fills, the
/// mascot watching from the highlight's place, read as what is loading.
/// When the child's [band] is known, the fills take that band's layout
/// (the pictures for a child of 5 to 8), so nothing jumps as the
/// catalogue arrives.
class MosaicLoading extends StatelessWidget {
  const MosaicLoading({super.key, this.note, this.band});

  final AgeBand? band;

  static const label = 'Carregando vídeos';

  /// The blocks a day usually brings.
  static const _blocks = 6;

  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final fill = context.palette.outline.withValues(alpha: .24);
    Widget quiet(Size size, double radius) => Container(
      width: size.width,
      height: size.height,
      decoration: ShapeDecoration(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final band = this.band;
            final pictures = band != null && band != AgeBand.upTo4;
            final g = _Geometry.of(
              box,
              wide:
                  MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint,
              pack: false,
              pictures: pictures,
              blocks: _blocks,
              grow: !pictures,
            );
            return _Arrangement(
              geometry: g,
              note: note,
              lead: _Highlight(
                geometry: g,
                look: TeviLook.watching,
                child: quiet(g.highlight, FieldSizes.heroCorner),
              ),
              pictures: [
                if (pictures)
                  for (var i = 0; i < MosaicPlan.maxPictures; i++)
                    quiet(g.picture, Radii.card),
              ],
              blocks: [
                for (var i = 0; i < _blocks; i++) quiet(g.block, Radii.card),
              ],
            );
          },
        ),
      ),
    );
  }
}
