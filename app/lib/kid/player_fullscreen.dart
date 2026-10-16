import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A phone's screen is under this on its shortest side; a tablet's is not.
const phoneShortestSide = 600.0;

/// Whether the child's player goes fullscreen (fullscreen design):
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
/// the screen goes, so no route is left without them (fullscreen design).
/// They come back in Flutter's own default, every overlay shown,
/// the mode the app boots in: never a mode the guardian's screens were
/// not built in.
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
  @override
  void initState() {
    super.initState();
    if (widget.active) _hide();
  }

  @override
  void didUpdateWidget(SystemBarsHidden old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    widget.active ? _hide() : _show();
  }

  @override
  void dispose() {
    if (widget.active) _show();
    super.dispose();
  }

  void _hide() => unawaited(
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
  );

  void _show() => unawaited(
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    ),
  );

  @override
  Widget build(BuildContext context) => widget.child;
}
