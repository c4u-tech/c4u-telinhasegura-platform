import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lets no touch through for a short moment after the screen it covers
/// appears, or appears again once what stood over it goes. A child taps
/// again where the last screen's target was, and that tap must not land
/// on whatever stands there now. Only touches wait: a screen reader's
/// action is deliberate, and keeps working throughout.
class TapGuard extends StatefulWidget {
  const TapGuard({super.key, required this.child});

  /// How long touches wait after the screen appears.
  static const window = Duration(milliseconds: 300);

  final Widget child;

  @override
  State<TapGuard> createState() => _TapGuardState();
}

class _TapGuardState extends State<TapGuard> {
  Timer? _timer;
  bool _shut = false;
  bool? _current;

  @override
  void initState() {
    super.initState();
    _shutFor();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the route makes this run as it is covered and
    // uncovered: uncovered, the screen has appeared again.
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (_current == false && current) setState(_shutFor);
    _current = current;
  }

  void _shutFor() {
    _shut = true;
    _timer?.cancel();
    _timer = Timer(TapGuard.window, () {
      if (mounted) setState(() => _shut = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Shut(shut: _shut, child: widget.child);
}

/// Misses every hit test while [shut], leaving semantics alone.
class _Shut extends SingleChildRenderObjectWidget {
  const _Shut({required this.shut, super.child});

  final bool shut;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShut(shut);

  @override
  void updateRenderObject(BuildContext context, _RenderShut renderObject) =>
      renderObject.shut = shut;
}

class _RenderShut extends RenderProxyBox {
  _RenderShut(this.shut);

  bool shut;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !shut && super.hitTest(result, position: position);
}
