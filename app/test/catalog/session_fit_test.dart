import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/catalog/session_fit.dart';
import 'package:telinha_segura/screentime/screentime_api.dart';

import '../screentime/fixtures.dart' show rulesJson;

ScreenTimeRules day({
  int daily = 90,
  int extension = 0,
  int usedMinutes = 40,
  int remainingMinutes = 50,
  String state = 'ok',
}) => ScreenTimeRules.fromJson(
  rulesJson(
    dailyMinutes: daily,
    extension: extension,
    usedSeconds: usedMinutes * 60,
    state: state,
    remainingSeconds: remainingMinutes * 60,
  ),
);

SessionFit fit(ScreenTimeRules rules, int workMinutes) =>
    SessionFit(rules, Duration(minutes: workMinutes));

void main() {
  test('a work within the time left fits with no more time', () {
    final f = fit(day(remainingMinutes: 50), 45);

    expect(f.left, const Duration(minutes: 50));
    expect(f.fitsWith(0), isTrue);
    expect(f.smallest, 0);
    expect(f.shortfall, Duration.zero);
  });

  test('the server\'s minute of tolerance counts', () {
    expect(fit(day(remainingMinutes: 50), 51).smallest, 0);
    expect(fit(day(remainingMinutes: 50), 52).smallest, 15);
  });

  test('a longer work needs the smallest extension that makes it fit; the '
      'shortfall is rounded up to the minute', () {
    final f = SessionFit(
      day(remainingMinutes: 40),
      const Duration(minutes: 57, seconds: 30),
    );

    expect(f.fitsWith(0), isFalse);
    expect(f.fitsWith(15), isFalse, reason: '55 min and its minute of grace');
    expect(f.fitsWith(30), isTrue);
    expect(f.smallest, 30);
    expect(f.shortfall, const Duration(minutes: 18));
  });

  test('an extension that would pass 4 hours a day is no way to fit', () {
    final f = fit(day(daily: 200, remainingMinutes: 40), 90);

    expect(f.fitsWith(30), isFalse, reason: '200 + 30 is under 240 but short');
    expect(f.fitsWith(60), isFalse, reason: '260 passes the cap');
    expect(f.smallest, isNull);
  });

  test('today\'s extensions count towards the cap', () {
    final f = fit(day(daily: 90, extension: 120, remainingMinutes: 10), 60);

    expect(f.fitsWith(30), isFalse);
    expect(f.fitsWith(60), isFalse);
    expect(f.smallest, isNull);
  });

  test('a spent day leaves nothing without more time; more time adds to '
      'the day\'s limit', () {
    final f = fit(
      day(usedMinutes: 90, remainingMinutes: 0, state: 'time_up'),
      40,
    );

    expect(f.left, Duration.zero);
    expect(f.fitsWith(0), isFalse);
    expect(f.fitsWith(30), isFalse);
    expect(f.smallest, 60);
    expect(f.shortfall, const Duration(minutes: 40));
  });

  test('outside the hours, more time opens them only for its own minutes', () {
    final f = fit(
      day(usedMinutes: 10, remainingMinutes: 0, state: 'outside_window'),
      45,
    );

    expect(f.fitsWith(30), isFalse);
    expect(f.smallest, 60);
  });
}
