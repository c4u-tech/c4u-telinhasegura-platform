import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'empty_shelf.dart';

/// The child side's error note: the picture
/// first, the mascot on its hollow screen with its crest raised, as on the
/// empty shelf but surprised, then one calm line in ember on dark for the
/// adult nearby. No alarm icon: a pre-reader reads the picture, and the
/// picture is calm.
///
/// Asleep, nothing went wrong: the video is only longer than the time left.
/// The mascot sleeps on its wire, as on the day without time, and the
/// line is the sleeping telinha's muted one, with no error ground, so a
/// child who cannot read yet sees "not now", not "broken".
class KidErrorNote extends StatelessWidget {
  const KidErrorNote(
    this.message, {
    super.key,
    this.picture = 96,
    this.asleep = false,
    this.beside = false,
    this.mascot = true,
  });

  final String message;

  /// Whether the note brings its own mascot.
  final bool mascot;

  /// The mascot asleep and the line calm: "not now".
  final bool asleep;

  /// The picture's height.
  final double picture;

  /// The picture at the line's start rather than above it: a note that
  /// floats in a card keeps low. There the mascot stands alone, without
  /// its screen or wire, [picture] tall, so it leads the card.
  final bool beside;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // A warning is an answer: the crest rises as the note appears.
    final from = asleep ? null : TeviLook.watching;
    const corner = Radius.circular(48 * Radii.screenRatio);
    final line = DecoratedBox(
      decoration: BoxDecoration(
        color: asleep ? null : p.errorGround,
        borderRadius: const BorderRadius.all(corner),
      ),
      child: Padding(
        // Beside the picture with no box of its own, the line needs no
        // inset from a box's edge.
        padding: EdgeInsets.symmetric(
          horizontal: beside && asleep ? 0 : Space.lg,
          vertical: Space.md,
        ),
        child: Text(
          message,
          textAlign: beside ? TextAlign.start : TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: asleep ? p.muted : p.error),
        ),
      ),
    );
    if (!mascot) {
      return Semantics(liveRegion: true, container: true, child: line);
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Flex(
        direction: beside ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (beside)
            FacingTevi(
              size: picture,
              look: asleep ? TeviLook.asleep : TeviLook.crestUp,
              markColor: BrandColors.sky,
              blinks: false,
              arrivesFrom: from,
            )
          else
            ShelfPicture(
              look: asleep ? TeviLook.asleep : TeviLook.crestUp,
              perch: asleep ? Perch.wire : Perch.screen,
              scale: picture / ShelfPicture.size.height,
              blinks: false,
              arrivesFrom: from,
            ),
          beside
              ? const SizedBox(width: Space.sm)
              : const SizedBox(height: Space.md),
          beside ? Flexible(child: line) : line,
        ],
      ),
    );
  }
}

/// A note floating in a dark card: the mascot large at the start, the
/// line beside it. Its night is the card's, whatever the ground beneath; on a
/// ground as dark as the card, a line holds its edge.
class FloatingNote extends StatelessWidget {
  const FloatingNote(this.message, {super.key, this.asleep = false});

  final String message;
  final bool asleep;

  /// The mascot's box in the card: the card's largest thing, so a child
  /// who cannot read sees it first.
  static const picture = 96.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ground = context.dependOnInheritedWidgetOfExactType<TeviGround>();
    final edge = ground != null && TeviGround.nightOn(ground.color);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.dark,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.card)),
        border: edge ? Border.all(color: p.outline, width: 1.5) : null,
      ),
      child: TeviGround(
        color: BrandColors.dark,
        // At large text the card scrolls inside the room it has.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.md),
          child: KidErrorNote(
            message,
            asleep: asleep,
            beside: true,
            picture: picture,
          ),
        ),
      ),
    );
  }
}

/// [content] with [note], when there is one, floating over its foot, so
/// what the screen shows stays where it is: the note never pushes it down.
/// The note keeps below [top], clear of the keys there, and [content] is
/// told the [note]'s room, to let its last row scroll clear of it.
class NoteOver extends StatefulWidget {
  const NoteOver({super.key, required this.content, this.note, this.top = 0});

  final Widget Function(double room) content;
  final Widget? note;
  final double top;

  /// The widest a note grows, centred on a wide screen.
  static const maxWidth = 600.0;

  @override
  State<NoteOver> createState() => _NoteOverState();
}

class _NoteOverState extends State<NoteOver> {
  double _room = 0;

  void _measured(Size size) {
    final room = size.height + 2 * Space.md;
    if (room == _room) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _room = room);
    });
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Positioned.fill(
            child: _NoteShowing(
              showing: note != null,
              child: widget.content(note == null ? 0 : _room),
            ),
          ),
          if (note != null)
            Positioned(
              left: Space.lg,
              right: Space.lg,
              bottom: Space.md,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: NoteOver.maxWidth,
                    maxHeight: math.max(
                      0,
                      box.maxHeight - widget.top - 2 * Space.md,
                    ),
                  ),
                  child: _Measured(onSize: _measured, child: note),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Whether a note floats over the content beneath it.
class _NoteShowing extends InheritedWidget {
  const _NoteShowing({required this.showing, required super.child});

  final bool showing;

  @override
  bool updateShouldNotify(_NoteShowing old) => showing != old.showing;
}

/// A screen's own mascot, which steps aside while a note floats over the
/// screen: the note brings its own, and a child sees one mascot at a
/// time. It keeps its place, so nothing around it moves, and fades back
/// when the note leaves.
class MascotUnderNote extends StatelessWidget {
  const MascotUnderNote({super.key, required this.child});

  final Widget child;

  static const fade = Motion.quick;

  @override
  Widget build(BuildContext context) {
    final showing =
        context.dependOnInheritedWidgetOfExactType<_NoteShowing>()?.showing ??
        false;
    return AnimatedOpacity(
      opacity: showing ? 0 : 1,
      duration: Motion.of(context, fade),
      child: child,
    );
  }
}

/// Tells [onSize] the size its child took at each layout.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) =>
      renderObject.onSize = onSize;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onSize);

  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}
