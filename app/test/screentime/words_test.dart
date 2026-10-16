import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/screentime/kid_time.dart';
import 'package:telinha_segura/screentime/screentime_api.dart';
import 'package:telinha_segura/screentime/words.dart';

ScreenTimeRules rulesWith({
  int dailyMinutes = 90,
  int usedSeconds = 2400,
  int extension = 0,
  KidTimeState state = KidTimeState.ok,
}) => ScreenTimeRules(
  dailyMinutes: dailyMinutes,
  windowStart: '08:00',
  windowEnd: '19:30',
  timeZone: 'America/Sao_Paulo',
  isDefault: false,
  today: ScreenTimeToday(
    used: Duration(seconds: usedSeconds),
    extensionMinutes: extension,
    time: KidTime(state: state, remaining: Duration.zero),
  ),
);

void main() {
  group('minutes in words', () {
    for (final (minutes, words) in [
      (0, '0 min'),
      (1, '1 min'),
      (45, '45 min'),
      (60, '1 h'),
      (70, '1 h 10 min'),
      (90, '1 h 30 min'),
      (240, '4 h'),
      (299, '4 h 59 min'),
    ]) {
      test('$minutes reads "$words"', () {
        expect(ScreenTimeWords.minutes(minutes), words);
      });
    }

    test('a watched time rounds down to the minute', () {
      expect(ScreenTimeWords.watched(const Duration(seconds: 59)), '0 min');
      expect(
        ScreenTimeWords.watched(const Duration(minutes: 70, seconds: 59)),
        '1 h 10 min',
      );
    });
  });

  group('the seven days, today first', () {
    test('today and yesterday by name, then the short weekday', () {
      // 2026-10-05 is a Monday.
      final days = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 5 - i)];
      expect(
        [for (final (i, d) in days.indexed) ScreenTimeWords.day(i, d)],
        ['Hoje', 'Ontem', 'Sáb', 'Sex', 'Qui', 'Qua', 'Ter'],
      );
      expect(ScreenTimeWords.day(6, DateTime(2026, 10, 4)), 'Dom');
      expect(ScreenTimeWords.day(6, DateTime(2026, 10, 5)), 'Seg');
    });
  });

  group("today's state on the list", () {
    test('ok reads the used and the limit plus the extension, rounded '
        'down', () {
      expect(
        ScreenTimeWords.state(
          rulesWith(usedSeconds: 40 * 60 + 59, extension: 15),
        ),
        '40 de 105 min hoje',
      );
    });

    test('time_up and outside_window read in words', () {
      expect(
        ScreenTimeWords.state(rulesWith(state: KidTimeState.timeUp)),
        'Acabou por hoje',
      );
      expect(
        ScreenTimeWords.state(rulesWith(state: KidTimeState.outsideWindow)),
        'Fora do horário',
      );
    });
  });

  group("the hub's today", () {
    test('the watched minutes of the day\'s limit', () {
      expect(
        ScreenTimeWords.today(rulesWith(usedSeconds: 40 * 60 + 30)),
        'Assistiu 40 min de 90.',
      );
      expect(
        ScreenTimeWords.today(rulesWith(usedSeconds: 600, extension: 30)),
        'Assistiu 10 min de 120.',
      );
    });

    test('under a minute, not yet', () {
      expect(
        ScreenTimeWords.today(rulesWith(usedSeconds: 59)),
        'Ainda não assistiu hoje.',
      );
    });

    test('an extension has its own line, none without one', () {
      expect(
        ScreenTimeWords.extension(rulesWith(extension: 30)),
        'Mais 30 min dados hoje.',
      );
      expect(ScreenTimeWords.extension(rulesWith()), isNull);
    });
  });

  test('the rules read as one line', () {
    expect(
      ScreenTimeWords.rules(rulesWith()),
      '90 min por dia · das 08:00 '
      'às 19:30',
    );
  });

  group('the time zone by its city', () {
    for (final (zone, words) in [
      ('America/Sao_Paulo', 'Horários de São Paulo'),
      ('America/Manaus', 'Horários de Manaus'),
      ('America/Belem', 'Horários de Belém'),
      ('America/Argentina/Buenos_Aires', 'Horários de Buenos Aires'),
      ('Europe/Lisbon', 'Horários de Lisbon'),
      ('UTC', 'Horários de UTC'),
    ]) {
      test('$zone reads "$words"', () {
        expect(ScreenTimeWords.zone(zone), words);
      });
    }
  });
}
