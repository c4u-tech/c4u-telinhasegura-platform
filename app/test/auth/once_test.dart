import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/once.dart';

/// Apple JS loads on the first Apple sign-in and is reused:
/// the loader runs its work once, even when asked concurrently.
void main() {
  test('concurrent and later calls share one run', () async {
    var runs = 0;
    final gate = Completer<void>();
    final load = Once(() async {
      runs++;
      await gate.future;
    });

    final first = load();
    final second = load();
    gate.complete();
    await Future.wait([first, second]);
    await load();

    expect(runs, 1);
  });

  test('a failed run is retried by the next call', () async {
    var runs = 0;
    final load = Once(() async {
      runs++;
      if (runs == 1) throw StateError('network');
    });

    await expectLater(load(), throwsStateError);
    await load();

    expect(runs, 2);
  });
}
