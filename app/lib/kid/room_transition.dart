import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';

/// A page opening from the home's door: the door's ground grows from
/// where the door stood until it is the whole screen, and the page shows
/// on it; going back, it shrinks onto the door again, so the child sees
/// it is the same place. Under reduced motion it is a cut; at rest it
/// leaves [child] untouched.
class RoomTransition extends AnimatedWidget {
  const RoomTransition({
    super.key,
    required Animation<double> animation,
    required this.from,
    required this.ground,
    required this.child,
  }) : super(listenable: animation);

  static const duration = Duration(milliseconds: 300);

  /// Where the door stood on the screen, if the page opened from one.
  final Rect? from;
  final Color ground;
  final Widget child;

  /// The page shows once the ground has grown past the door.
  static const _show = Interval(.3, 1);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final from = this.from;
    if (from == null ||
        MediaQuery.disableAnimationsOf(context) ||
        animation.isCompleted) {
      return child;
    }
    final size = MediaQuery.sizeOf(context);
    final door = RRect.fromRectAndRadius(
      from,
      const Radius.circular(Radii.card),
    );
    final full = RRect.fromRectAndRadius(Offset.zero & size, Radius.zero);
    final t = Easing.standard.transform(animation.value);
    return ClipPath(
      clipper: RoomClipper(RRect.lerp(door, full, t)!),
      child: ColoredBox(
        color: ground,
        child: Opacity(opacity: _show.transform(animation.value), child: child),
      ),
    );
  }
}

/// Clips the page to the growing ground.
class RoomClipper extends CustomClipper<Path> {
  const RoomClipper(this.rrect);

  final RRect rrect;

  @override
  Path getClip(Size size) => Path()..addRRect(rrect);

  @override
  bool shouldReclip(RoomClipper old) => old.rrect != rrect;
}

/// The go_router page of a page opened from the home's door at [from]
/// (popping it plays the reverse).
CustomTransitionPage<T> roomPage<T>({
  LocalKey? key,
  required Rect? from,
  required Color ground,
  required Widget child,
}) => CustomTransitionPage<T>(
  key: key,
  transitionDuration: RoomTransition.duration,
  reverseTransitionDuration: RoomTransition.duration,
  child: child,
  transitionsBuilder: (context, animation, _, child) => RoomTransition(
    animation: animation,
    from: from,
    ground: ground,
    child: child,
  ),
);
