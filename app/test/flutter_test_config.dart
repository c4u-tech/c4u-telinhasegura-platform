import 'dart:async';

import 'package:telinha_segura/design/tokens.dart';

/// Every test starts with the loaders' loops still, so a screen that
/// shows one can still settle, and with the app's opening cut, so its
/// first screen shows as soon as the mode is known; a test that watches
/// either turns it on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Motion.loops = false;
  Motion.opens = false;
  await testMain();
}
