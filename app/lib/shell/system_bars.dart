import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _clear = Color(0x00000000);

/// The system bars over a ground of [ground]'s brightness: both clear,
/// with no scrim of the system's behind them (Android 15 and later draw
/// the app under the navigation bar and would lay a light band there),
/// their icons in the tone that reads on that ground. iOS reads only the
/// status bar's brightness from it.
SystemUiOverlayStyle barsOver(Brightness ground) {
  final icons = ground == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarIconBrightness: icons,
    statusBarBrightness: ground,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: _clear,
    systemNavigationBarDividerColor: _clear,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Whether the system bars are Android's to show and hide here: a phone's
/// or a tablet's, never the web's.
bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Brings the system bars back. On Android the app keeps drawing edge to
/// edge, under clear bars, as Android 15 and later always do; elsewhere
/// every overlay is shown, the mode the app boots in.
Future<void> showSystemBars() => _android
    ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
    : SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );

/// Hides the system bars: an edge swipe shows them for a moment, and they
/// hide again.
Future<void> hideSystemBars() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

/// Keeps the system bars hidden while [hidden] (a child holds the device),
/// and shown otherwise, from the app's start: on Android the buttons would
/// otherwise stay in reach of the child for the whole mode. Elsewhere the
/// bars are left to the screens.
///
/// A screen that hides the bars for a while of its own (the child's
/// player turned sideways) leaves them alone while this keeps them hidden.
class ModeBars extends StatefulWidget {
  const ModeBars({super.key, required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  /// Whether the mode keeps the bars hidden around [context].
  static bool hides(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HiddenByMode>()?.hidden ??
      false;

  @override
  State<ModeBars> createState() => _ModeBarsState();
}

class _ModeBarsState extends State<ModeBars> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(ModeBars old) {
    super.didUpdateWidget(old);
    if (widget.hidden != old.hidden) _apply();
  }

  void _apply() {
    if (!_android) return;
    unawaited(widget.hidden ? hideSystemBars() : showSystemBars());
  }

  @override
  Widget build(BuildContext context) =>
      _HiddenByMode(hidden: _android && widget.hidden, child: widget.child);
}

class _HiddenByMode extends InheritedWidget {
  const _HiddenByMode({required this.hidden, required super.child});

  final bool hidden;

  @override
  bool updateShouldNotify(_HiddenByMode old) => old.hidden != hidden;
}
