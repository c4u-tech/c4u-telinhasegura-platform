import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// A screen that reads again when the guardian comes back to it from a
/// screen above it: the router keeps it mounted
/// beneath, so it watches the location leave its [ownPath] and return.
mixin RefetchOnReturn<T extends StatefulWidget> on State<T> {
  GoRouter? _router;
  bool _away = false;

  /// The location this screen stands at.
  String get ownPath;

  /// Called once each time the location comes back to [ownPath].
  void onReturn();

  /// Whether this screen is the one shown, not one beneath another.
  bool get isHere =>
      _router?.routerDelegate.currentConfiguration.uri.path == ownPath;

  /// Starts watching; call once the context has the router. Opened
  /// beneath another screen (a deep link), coming up counts as a return.
  void watchReturns() {
    _router = GoRouter.of(context)..routerDelegate.addListener(_check);
    _away = !isHere;
  }

  void _check() {
    final here = isHere;
    if (!here) {
      _away = true;
    } else if (_away) {
      _away = false;
      onReturn();
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_check);
    super.dispose();
  }
}
