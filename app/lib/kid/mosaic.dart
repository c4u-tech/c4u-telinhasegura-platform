import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../curation/curation.dart' show VideoTheme;
import '../curation/kid_catalog.dart';
import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart' show AgeBand;
import 'kid_error_note.dart';
import 'pack_row.dart';
import 'shelves.dart';
import 'theme_glyph.dart';

/// What the child home shows of a catalogue, chosen on the device from the
/// catalogue as delivered: the day's highlight (the first pacotinho, else
/// the first video of the first theme), up to two pictures that play at
/// one tap (the first videos of the themes that follow, never the
/// highlight's picture again), and one block per theme that has videos,
/// in the catalogue's order, led by a door to every pacotinho when the
/// day has more than the one it leads with. A child up to 4 gets no
/// small pictures: one large picture and the blocks are enough to choose
/// from.
class MosaicPlan {
  const MosaicPlan._({
    required this.pack,
    required this.video,
    required this.pictures,
    required this.blocks,
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
    return MosaicPlan._(
      pack: pack,
      video: video,
      pictures: band == AgeBand.upTo4
          ? const []
          : [
              for (final shelf in from)
                if (shelf.videos.first.id != shown) shelf.videos.first,
            ].take(maxPictures).toList(),
      blocks: blocks,
      packsDoor: catalog.packs.length > 1,
    );
  }

  static const maxPictures = 2;

  /// The highlight when the day has a pacotinho; [video] otherwise.
  final KidPack? pack;
  final KidVideo? video;
  final List<KidVideo> pictures;
  final List<KidShelf> blocks;

  /// The pacotinhos after the first have a door of their own.
  final bool packsDoor;

  /// Nothing to watch today: no pacotinho and no video in any theme.
  bool get isEmpty => pack == null && video == null;
}

/// The child home's one screen: the highlight with the mascot standing on
/// it, the one-tap pictures, and the theme blocks in two columns. On a
/// phone they stand one under the other; from 840 px the highlight and
/// the pictures take the start and the blocks the end. The blocks grow to
/// fill the screen's height, up to a size that still reads as a block,
/// so a phone with today's catalogue needs no scrolling; with more than
/// fits, or larger text, the screen scrolls.
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
  });

  final KidCatalog catalog;

  /// The child's age band, which tunes how many pictures and how large
  /// the blocks are.
  final AgeBand band;
  final ThumbnailLoader thumbnail;

  /// Null while a play is pending, so further taps do nothing.
  final ValueChanged<KidVideo>? onPlay;
  final ValueChanged<KidPack>? onOpenPack;

  /// A theme's block was tapped, standing [from] on the screen.
  final void Function(VideoTheme theme, Rect from)? onOpenTheme;

  /// The door to every pacotinho was tapped, standing at the given place.
  final ValueChanged<Rect>? onOpenPacks;

  /// Floating over the home's foot (a refusal's note).
  final Widget? note;

  /// The child's avatar at the strip's start: a small "this is you".
  static const avatar = 48.0;

  /// How far the home reaches up into the strip: the mascot's head stands
  /// there, between the avatar and the exit.
  static const rise = 64.0;

  @override
  Widget build(BuildContext context) {
    final plan = MosaicPlan.of(catalog, band: band);
    return LayoutBuilder(
      builder: (context, box) {
        final g = _Geometry.of(
          box,
          wide: MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint,
          pack: plan.pack != null,
          pictures: plan.pictures.isNotEmpty,
          blocks: plan.blocks.length + (plan.packsDoor ? 1 : 0),
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
        final blocks = [
          if (plan.packsDoor)
            Builder(
              builder: (context) => PacksDoor(
                size: g.block,
                wide: g.wide,
                onTap: onOpenPacks == null
                    ? null
                    : () => onOpenPacks!(_placeOf(context)),
              ),
            ),
          for (final shelf in plan.blocks)
            Builder(
              builder: (context) => ThemeBlock(
                shelf: shelf,
                world: worldOf(shelf.theme),
                size: g.block,
                wide: g.wide,
                thumbnail: thumbnail,
                onTap: onOpenTheme == null
                    ? null
                    : () => onOpenTheme!(shelf.theme, _placeOf(context)),
              ),
            ),
        ];
        return _Arrangement(
          geometry: g,
          note: note,
          lead: lead,
          pictures: pictures,
          blocks: blocks,
        );
      },
    );
  }
}

/// Where the widget at [context] stands on the screen.
Rect _placeOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
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
    required this.block,
    required this.gap,
    required this.blockGap,
  });

  factory _Geometry.of(
    BoxConstraints box, {
    required bool wide,
    required bool pack,
    required bool pictures,
    required int blocks,
    required bool grow,
  }) {
    final inset = wide ? _insetWide : _inset;
    final room = box.maxWidth - 2 * inset;
    // A phone's column stays a phone's: on a wider narrow window it is
    // centred rather than stretched.
    final column = math.min(room, _maxColumn);
    final start = wide ? (room - _between) * 11 / 21 : column;
    final end = wide ? room - _between - start : column;
    final gap = Space.md;
    final blockGap = wide ? Space.lg : Space.md;
    final tevi = wide ? _teviWide : _tevi;
    final highlight = Size(start, start * 9 / 16);
    final pw = (start - gap) / 2;
    final picture = Size(pw, pw * 9 / 16);
    final bw = (end - blockGap) / 2;
    final rows = (blocks / 2).ceil();
    // What stands above and below the blocks, in their column.
    final above =
        _standOf(tevi) +
        (wide
            ? 0
            : highlight.height +
                  (pack ? PackTile.below : 0) +
                  (pictures ? gap + picture.height : 0) +
                  gap);
    final fill = rows == 0
        ? 0.0
        : (box.maxHeight - above - _bottom - (rows - 1) * blockGap) / rows;
    final ratio = switch ((wide, grow)) {
      (false, false) => .70,
      (false, true) => .90,
      (true, false) => .62,
      (true, true) => .80,
    };
    final low = math.max(KidSizes.target, bw * .50);
    final high = math.max(low, bw * ratio);
    return _Geometry(
      wide: wide,
      inset: inset,
      start: start,
      end: end,
      tevi: tevi,
      highlight: highlight,
      picture: picture,
      block: Size(bw, fill.clamp(low, high)),
      gap: gap,
      blockGap: blockGap,
    );
  }

  static const _inset = 20.0;
  static const _insetWide = 48.0;
  static const _maxColumn = 600.0;

  /// Between the start column and the blocks, from 840 px.
  static const _between = 40.0;
  static const _tevi = 104.0;
  static const _teviWide = 128.0;

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
  final Size block;
  final double gap;
  final double blockGap;

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
            child: Transform.flip(
              flipX: Directionality.of(context) == TextDirection.rtl,
              child: Tevi(
                size: size,
                look: look ?? TeviLook.crestUp,
                night: TeviGround.nightAt(context),
              ),
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
    this.note,
  });

  final _Geometry geometry;
  final Widget? note;
  final Widget lead;
  final List<Widget> pictures;
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
        if (pictures.isNotEmpty) ...[
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
              SizedBox(width: g.start, child: start),
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
      enabled: true,
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

/// The door to every pacotinho of the day, first among the blocks: no
/// world of its own, only the home's ground inside a cream outline, and
/// the pacotinhos' sign. One button, read "Pacotinhos".
class PacksDoor extends StatefulWidget {
  const PacksDoor({
    super.key,
    required this.size,
    required this.onTap,
    this.wide = false,
  });

  final Size size;
  final VoidCallback? onTap;
  final bool wide;

  /// The outline's width.
  static const stroke = 2.0;

  @override
  State<PacksDoor> createState() => _PacksDoorState();
}

class _PacksDoorState extends State<PacksDoor> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final line = ColourWorlds.home.figure;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.card),
    );
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      label: PackGlyph.label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: widget.size,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: shape.copyWith(side: ring ?? BorderSide.none),
            ),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: ShapeDecoration(
                shape: shape.copyWith(
                  side: BorderSide(
                    color: line,
                    width: PacksDoor.stroke,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  onFocusChange: (f) => setState(() => _focused = f),
                  focusColor: Colors.transparent,
                  hoverColor: line.withValues(alpha: .08),
                  highlightColor: line.withValues(alpha: .12),
                  splashColor: line.withValues(alpha: .12),
                  child: Center(
                    child: PackGlyph(size: widget.wide ? 80 : KidSizes.target),
                  ),
                ),
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
class MosaicLoading extends StatelessWidget {
  const MosaicLoading({super.key, this.note});

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
            final g = _Geometry.of(
              box,
              wide:
                  MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint,
              pack: false,
              pictures: false,
              blocks: _blocks,
              grow: true,
            );
            return _Arrangement(
              geometry: g,
              note: note,
              lead: _Highlight(
                geometry: g,
                look: TeviLook.watching,
                child: quiet(g.highlight, FieldSizes.heroCorner),
              ),
              pictures: const [],
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
