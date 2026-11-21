import 'dart:async';

import 'package:flutter/widgets.dart';

import '../shell/system_bars.dart';

/// A phone's screen is under this on its shortest side; a tablet's is not.
const phoneShortestSide = 600.0;

/// Whether the child's player goes fullscreen:
/// a phone turned sideways, on Android or iOS, never the web. A tablet
/// or a desktop keeps the rail, since landscape is how it is held, not a
/// turn of the hand. The screen decides the rest: only while the embed is
/// in the window.
bool playerFullscreen({
  required Size size,
  required TargetPlatform platform,
  required bool web,
}) {
  if (web) return false;
  if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
    return false;
  }
  return size.shortestSide < phoneShortestSide && size.width > size.height;
}

/// Hides the system bars while [active] (immersive sticky: an edge swipe
/// shows them for a moment) and brings them back when it is not, or when
/// the screen goes, so no route is left without them.
/// They come back as the app shows them everywhere else. While the child's
/// mode keeps the bars hidden on its own ([ModeBars]), this leaves them
/// alone: turning upright must not bring them back.
class SystemBarsHidden extends StatefulWidget {
  const SystemBarsHidden({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<SystemBarsHidden> createState() => _SystemBarsHiddenState();
}

class _SystemBarsHiddenState extends State<SystemBarsHidden> {
  /// Whether this screen asked for the bars hidden, and has not yet
  /// brought them back.
  bool _hid = false;

  /// Whether the mode keeps them hidden, as last read.
  bool _byMode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _byMode = ModeBars.hides(context);
    _sync();
  }

  @override
  void didUpdateWidget(SystemBarsHidden old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    if (_hid && !_byMode) unawaited(showSystemBars());
    super.dispose();
  }

  void _sync() {
    if (_byMode) {
      _hid = false;
      return;
    }
    if (widget.active == _hid) return;
    _hid = widget.active;
    unawaited(_hid ? hideSystemBars() : showSystemBars());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
