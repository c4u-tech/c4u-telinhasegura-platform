import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/staff/elevation_note.dart';

void main() {
  final now = DateTime.utc(2026, 10, 8, 12);

  test('holds until the elevation\'s time, never past it', () {
    final note = ElevationNote();
    expect(withClock(Clock.fixed(now), () => note.holds), isFalse);

    note.elevated(now.add(const Duration(minutes: 30)));

    bool at(Duration later) =>
        withClock(Clock.fixed(now.add(later)), () => note.holds);
    expect(at(const Duration(minutes: 29)), isTrue);
    expect(at(const Duration(minutes: 30)), isFalse);
    expect(at(const Duration(hours: 2)), isFalse);
  });

  test('holds while the server does not ask, until forgotten', () {
    final note = ElevationNote()..notAsked();
    expect(note.holds, isTrue);

    note.forget();

    expect(note.holds, isFalse);
  });

  test('forgets an elevation', () {
    final note = ElevationNote()
      ..elevated(DateTime.now().add(const Duration(minutes: 30)));

    note.forget();

    expect(note.holds, isFalse);
  });

  test('once: callers asking together share one run, and a later caller '
      'runs again', () async {
    final note = ElevationNote();
    final answer = Completer<bool>();
    var runs = 0;
    Future<bool> ask() {
      runs++;
      return answer.future;
    }

    final first = note.once('k', ask);
    final second = note.once('k', ask);
    answer.complete(true);

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(runs, 1);
    expect(await note.once('k', () async => false), isFalse);
    expect(runs, 1);
  });
}
