import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../curation/kid_catalog.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'empty_shelf.dart';
import 'pack_row.dart';
import 'theme_glyph.dart';

/// Reads a video's thumbnail bytes from our API.
typedef ThumbnailLoader = Future<Uint8List> Function(String videoId);

/// The child's shelves, one per theme in the catalogue's order:
/// each led by its glyph, its videos sliding sideways and
/// ending on the last of them. No YouTube logo: the operator relies on
/// the embed's own branding (fullscreen design). The day's
/// pacotinhos, when there are any, stand above them in a row of their own.
/// A bounded set, never a feed: a few
/// rows, each ending on its last tile.
class KidShelves extends StatelessWidget {
  const KidShelves({
    super.key,
    required this.catalog,
    required this.thumbnail,
    required this.onPlay,
    required this.onOpenPack,
  });

  final KidCatalog catalog;
  final ThumbnailLoader thumbnail;

  /// Null while a play is pending, so further taps do nothing.
  final ValueChanged<KidVideo>? onPlay;
  final ValueChanged<KidPack>? onOpenPack;

  /// The child's avatar above the shelves: a small "this is you".
  static const avatar = 56.0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (catalog.packs.isNotEmpty) ...[
        PackRow(packs: catalog.packs, thumbnail: thumbnail, onOpen: onOpenPack),
        if (catalog.shelves.isNotEmpty) const SizedBox(height: Space.xxl),
      ],
      for (final (i, shelf) in catalog.shelves.indexed) ...[
        if (i > 0) const SizedBox(height: Space.xxl),
        Shelf(shelf: shelf, thumbnail: thumbnail, onPlay: onPlay),
      ],
    ],
  );
}

/// One theme's shelf: the glyph at the column's start, then its videos in
/// a row that runs to the screen's edge, the next tile peeking.
class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.shelf,
    required this.thumbnail,
    required this.onPlay,
  });

  final KidShelf shelf;
  final ThumbnailLoader thumbnail;
  final ValueChanged<KidVideo>? onPlay;

  @override
  Widget build(BuildContext context) {
    final tile = VideoTile.sizeFor(context);
    return ShelfRow(
      glyph: ThemeGlyph(shelf.theme),
      height: tile.height,
      children: [
        for (final video in shelf.videos)
          VideoTile(
            video: video,
            size: tile,
            thumbnail: thumbnail,
            onTap: onPlay == null ? null : () => onPlay!(video),
          ),
      ],
    );
  }
}

/// A shelf's row: its [glyph] at the column's start, then [children]
/// sliding sideways to the screen's edge, ending on the last of them
/// (fullscreen design). [height] is the tallest child's.
class ShelfRow extends StatelessWidget {
  const ShelfRow({
    super.key,
    required this.glyph,
    required this.height,
    required this.children,
  });

  final Widget glyph;
  final double height;
  final List<Widget> children;

  /// The focus ring stands 3 px outside a tile; the row keeps its room.
  static const ring = 3.0;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: Space.xl),
      glyph,
      const SizedBox(width: Space.md),
      Expanded(
        child: SizedBox(
          height: height + 2 * ring,
          // A mouse drags the row too, as a finger does: on the
          // web, Flutter's default leaves mouse drags out.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(
                start: ring,
                end: Space.xl,
                top: ring,
                bottom: ring,
              ),
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (_, i) =>
                  Align(alignment: Alignment.topCenter, child: children[i]),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A video on a shelf: its picture in a screen-ratio frame, read as one
/// button by its title.
class VideoTile extends StatefulWidget {
  const VideoTile({
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

  static const narrow = Size(160, 90);
  static const wide = Size(224, 126);

  static Size sizeFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint
      ? wide
      : narrow;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late final Future<Uint8List> _bytes = widget.thumbnail(widget.video.id);
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        widget.size.height * Radii.screenRatio,
      ),
    );
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      label: widget.video.title,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: widget.size,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: shape.copyWith(side: ring ?? BorderSide.none),
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder(
                    future: _bytes,
                    builder: (context, snap) => switch (snap) {
                      AsyncSnapshot(hasData: true, :final data!) =>
                        Image.memory(
                          data,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const HollowThumbnail(),
                        ),
                      AsyncSnapshot(hasError: true) => const HollowThumbnail(),
                      _ => ColoredBox(color: p.outline.withValues(alpha: .24)),
                    },
                  ),
                  InkWell(
                    onTap: widget.onTap,
                    // Kept focusable while a play is pending: the ring
                    // stays where the child left it.
                    canRequestFocus: true,
                    onFocusChange: (f) => setState(() => _focused = f),
                    focusColor: Colors.transparent,
                    hoverColor: p.outline.withValues(alpha: .08),
                    highlightColor: p.outline.withValues(alpha: .12),
                    splashColor: p.outline.withValues(alpha: .12),
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

/// A thumbnail that did not come: the screen, hollow, in the outline tone.
/// The tile around it still plays.
class HollowThumbnail extends StatelessWidget {
  const HollowThumbnail({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HollowPainter(context.palette.outline));
}

class _HollowPainter extends CustomPainter {
  const _HollowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.5;
    final r = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r,
        Radius.circular(size.height * Radii.screenRatio - stroke / 2),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_HollowPainter old) => old.color != color;
}

/// The shelves' place while the catalogue loads: quiet bars in the outline
/// tone, two shelves' worth, read as what is loading.
class ShelvesLoading extends StatelessWidget {
  const ShelvesLoading({super.key});

  static const label = 'Carregando vídeos';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tile = VideoTile.sizeFor(context);
    final bar = p.outline.withValues(alpha: .24);
    Widget block(Size size) => Container(
      width: size.width,
      height: size.height,
      decoration: ShapeDecoration(
        color: bar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            size.shortestSide * Radii.screenRatio,
          ),
        ),
      ),
    );
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var row = 0; row < 2; row++) ...[
              if (row > 0) const SizedBox(height: Space.xxl),
              // Bars run past the edge as tiles do; nothing scrolls yet.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    const SizedBox(width: Space.xl),
                    block(const Size.square(KidSizes.target)),
                    const SizedBox(width: Space.md + 3),
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: Space.sm),
                      block(tile),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The catalogue did not come: the hollow screen, a line for the adult
/// and one way to try again.
class ShelvesFailed extends StatelessWidget {
  const ShelvesFailed({super.key, required this.onRetry});

  final VoidCallback onRetry;

  static const line = 'Os vídeos não carregaram.';
  static const retry = 'Tentar de novo';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: ExcludeSemantics(
          child: CustomPaint(
            size: EmptyShelf.size,
            painter: const EmptyShelfPainter(),
          ),
        ),
      ),
      const SizedBox(height: Space.lg),
      Text(
        line,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xl),
      FilledButton(
        onPressed: onRetry,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(KidSizes.target),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              KidSizes.target * Radii.screenRatio,
            ),
          ),
        ),
        child: const Text(retry),
      ),
    ],
  );
}
