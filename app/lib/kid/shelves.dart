import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../curation/kid_catalog.dart';
import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'empty_shelf.dart';
import 'player_keys.dart';

/// Reads a video's thumbnail bytes from our API.
typedef ThumbnailLoader = Future<Uint8List> Function(String videoId);

/// A video the child can play: its picture in a rounded frame, read as
/// one button by its title.
class VideoTile extends StatefulWidget {
  const VideoTile({
    super.key,
    required this.video,
    required this.size,
    required this.thumbnail,
    required this.onTap,
    this.radius,
    this.resting = false,
    this.playDisc = false,
    this.playDiscScale = 1,
    this.world,
  });

  final KidVideo video;
  final Size size;
  final ThumbnailLoader thumbnail;
  final VoidCallback? onTap;

  /// The frame's corner; by default the shape ratio's for its height.
  final double? radius;

  /// Longer than the time left today: the picture rests, quieted and
  /// outlined, still in its place and still a target, and it is read as
  /// not for today. No number, clock or word is drawn on it.
  final bool resting;

  /// Marks the picture with a [PlayDisc]: what it opens plays through.
  final bool playDisc;

  /// The [PlayDisc]'s size and inset, against its size on a phone's tile.
  final double playDiscScale;

  /// The theme's world the tile stands on, off the kid ground: a resting
  /// picture sinks toward its ground and is outlined in its figure, and
  /// the disc carries its ring where the ground is light.
  final ColourWorld? world;

  /// What a screen reader hears for [title], resting or not.
  static String label(String title, {required bool resting}) =>
      resting ? '$title, não cabe hoje' : title;

  /// The resting tile's outline, the hollow screen's stroke.
  static const restingStroke = 1.5;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  bool _focused = false;

  /// A resting picture loses its colour and sinks toward the ground it
  /// stands on, so it reads "not now" beside the awake tiles without a
  /// sign on it.
  Widget _picture(Widget picture, Color ground) => !widget.resting
      ? picture
      : Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(colorFilter: _grey, child: picture),
            ColoredBox(color: ground.withValues(alpha: .38)),
          ],
        );

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = widget.radius ?? widget.size.height * Radii.screenRatio;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final world = widget.world;
    final line = world?.figure ?? p.outline;
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    final rest = widget.resting
        ? BorderSide(
            color: line,
            width: VideoTile.restingStroke,
            strokeAlign: BorderSide.strokeAlignInside,
          )
        : BorderSide.none;
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      label: VideoTile.label(widget.video.title, resting: widget.resting),
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: widget.size,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: shape.copyWith(side: ring ?? BorderSide.none),
            ),
            // The resting stroke sits inside the frame and the focus ring
            // outside it, so a focused resting tile keeps both signs.
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: ShapeDecoration(shape: shape.copyWith(side: rest)),
              child: Material(
                type: MaterialType.transparency,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The disc is part of the picture, so a resting
                    // tile quiets it with the rest.
                    _picture(
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          ThumbnailPicture(
                            videoId: widget.video.id,
                            thumbnail: widget.thumbnail,
                            radius: radius,
                          ),
                          if (widget.playDisc)
                            PositionedDirectional(
                              end: PlayDisc.inset * widget.playDiscScale,
                              bottom: PlayDisc.inset * widget.playDiscScale,
                              child: PlayDisc(
                                scale: widget.playDiscScale,
                                ring: world?.ringsDisc ?? false
                                    ? ColourWorlds.discRing
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      world?.ground ?? p.ground,
                    ),
                    InkWell(
                      onTap: widget.onTap,
                      // Kept focusable while a play is pending: the ring
                      // stays where the child left it.
                      canRequestFocus: true,
                      onFocusChange: (f) => setState(() => _focused = f),
                      focusColor: Colors.transparent,
                      hoverColor: line.withValues(alpha: .08),
                      highlightColor: line.withValues(alpha: .12),
                      splashColor: line.withValues(alpha: .12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sun disc with a dark play triangle, set in the corner of a picture
/// that plays at one tap. Decoration only: the tile under it is the
/// target and says what it opens, so the disc wears the indicator's
/// colours, a mark's, not the action's. On a light ground, where the
/// sun would sink into its surroundings, a [ring] holds its edge.
class PlayDisc extends StatelessWidget {
  const PlayDisc({super.key, this.scale = 1, this.ring});

  /// The disc's diameter at scale 1.
  static const size = 44.0;

  /// Its distance from the picture's bottom and end edges at scale 1,
  /// which keeps it inside the rounded corner.
  static const inset = 10.0;

  /// Grows or shrinks the disc with its picture; its inset by the same.
  final double scale;

  /// The line around the disc's edge, if any.
  final Color? ring;

  /// The ring's width at scale 1.
  static const ringWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IgnorePointer(
      child: CustomPaint(
        size: Size.square(size * scale),
        painter: _PlayDiscPainter(
          disc: p.indicator,
          glyph: p.onIndicator,
          ring: ring,
          ringWidth: ringWidth * scale,
        ),
      ),
    );
  }
}

class _PlayDiscPainter extends CustomPainter {
  const _PlayDiscPainter({
    required this.disc,
    required this.glyph,
    this.ring,
    this.ringWidth = 0,
  });

  final Color disc;
  final Color glyph;
  final Color? ring;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(centre, radius, Paint()..color = disc);
    if (ring case final ring?) {
      // Inside the disc's edge, so the disc keeps its size.
      canvas.drawCircle(
        centre,
        radius - ringWidth / 2,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth,
      );
    }
    // The player's own play glyph, at a size the disc holds with room.
    PlayerGlyphPainter(
      PlayerGlyph.play,
      glyph,
      side: size.shortestSide * .45,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_PlayDiscPainter old) =>
      old.disc != disc ||
      old.glyph != glyph ||
      old.ring != ring ||
      old.ringWidth != ringWidth;
}

/// A video's thumbnail from our API, read once per video it shows: the
/// picture filling its box, a quiet fill while it comes, and the hollow
/// screen if it does not.
class ThumbnailPicture extends StatefulWidget {
  const ThumbnailPicture({
    super.key,
    required this.videoId,
    required this.thumbnail,
    this.radius,
    this.color,
  });

  final String videoId;
  final ThumbnailLoader thumbnail;

  /// The corner of the frame it fills, which a hollow screen follows.
  final double? radius;

  /// The hollow screen's and the quiet fill's tone; the outline's by
  /// default.
  final Color? color;

  @override
  State<ThumbnailPicture> createState() => _ThumbnailPictureState();
}

class _ThumbnailPictureState extends State<ThumbnailPicture> {
  late Future<Uint8List> _bytes = widget.thumbnail(widget.videoId);

  /// A catalogue read again can put another video in this slot: its
  /// picture is read then, or the slot would keep the one before.
  @override
  void didUpdateWidget(ThumbnailPicture old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) {
      _bytes = widget.thumbnail(widget.videoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hollow = HollowThumbnail(radius: widget.radius, color: widget.color);
    return FutureBuilder(
      future: _bytes,
      builder: (context, snap) => switch (snap) {
        AsyncSnapshot(hasData: true, :final data!) => Image.memory(
          data,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => hollow,
        ),
        AsyncSnapshot(hasError: true) => hollow,
        _ => ColoredBox(
          color: (widget.color ?? context.palette.outline).withValues(
            alpha: .24,
          ),
        ),
      },
    );
  }
}

/// A thumbnail that did not come: the screen, hollow, in the outline tone
/// (or [color]). The tile around it still plays.
class HollowThumbnail extends StatelessWidget {
  const HollowThumbnail({super.key, this.radius, this.color});

  /// The corner; by default the shape ratio's for its height.
  final double? radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _HollowPainter(color ?? context.palette.outline, radius),
  );
}

class _HollowPainter extends CustomPainter {
  const _HollowPainter(this.color, this.radius);

  final Color color;
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.5;
    final r = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r,
        Radius.circular(
          (radius ?? size.height * Radii.screenRatio) - stroke / 2,
        ),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_HollowPainter old) =>
      old.color != color || old.radius != radius;
}

/// The catalogue did not come: the mascot's crest raised over the hollow
/// screen, a line for the adult and one way to try again.
class ShelvesFailed extends StatelessWidget {
  const ShelvesFailed({super.key, required this.onRetry, this.scale = 1});

  final VoidCallback onRetry;

  /// The picture's scale, as the empty shelf's.
  final double scale;

  static const line = 'Os vídeos não carregaram.';
  static const retry = 'Tentar de novo';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: ShelfPicture(look: TeviLook.crestUp, scale: scale),
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
