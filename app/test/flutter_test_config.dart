import 'dart:async';

import 'package:telinha_segura/design/tokens.dart';

/// Every test starts with the loaders' loops still, so a screen that
/// shows one can still settle; a test that watches a loop turns them on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Motion.loops = false;
  await testMain();
}
