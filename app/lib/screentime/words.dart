import 'kid_time.dart';
import 'screentime_api.dart';

/// PT-BR words for a child's screen time, as the guardian reads it
/// (screen-time screens). Minutes read in words
/// ("1 h 10 min"); a watched time rounds down to the minute.
abstract final class ScreenTimeWords {
  /// "0 min", "45 min", "1 h", "1 h 10 min".
  static String minutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  static String watched(Duration watched) => minutes(watched.inMinutes);

  /// The day's limit: the daily minutes plus today's extension.
  static int limit(ScreenTimeRules rules) =>
      rules.dailyMinutes + rules.today.extensionMinutes;

  /// Today's state on the children's list.
  static String state(ScreenTimeRules rules) =>
      switch (rules.today.time.state) {
        KidTimeState.ok =>
          '${rules.today.used.inMinutes} de ${limit(rules)} min hoje',
        KidTimeState.timeUp => 'Acabou por hoje',
        KidTimeState.outsideWindow => 'Fora do horário',
      };

  /// The hub's line for today.
  static String today(ScreenTimeRules rules) {
    final used = rules.today.used.inMinutes;
    if (used < 1) return 'Ainda não assistiu hoje.';
    return 'Assistiu $used min de ${limit(rules)}.';
  }

  /// The hub's second line, only when today has an extension.
  static String? extension(ScreenTimeRules rules) =>
      rules.today.extensionMinutes > 0
      ? 'Mais ${rules.today.extensionMinutes} min dados hoje.'
      : null;

  /// "90 min por dia · das 08:00 às 19:30".
  static String rules(ScreenTimeRules rules) =>
      '${rules.dailyMinutes} min por dia · das ${rules.windowStart} às '
      '${rules.windowEnd}';

  static const _weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  /// The [daysAgo]th day of the seven, today first: "Hoje", "Ontem", then
  /// [date]'s short weekday. The position decides, since the dates are
  /// the family's and the device may be in another zone.
  static String day(int daysAgo, DateTime date) => switch (daysAgo) {
    0 => 'Hoje',
    1 => 'Ontem',
    _ => _weekdays[date.weekday - 1],
  };

  /// The IANA ids whose city carries an accent in PT-BR.
  static const _cities = {
    'Sao_Paulo': 'São Paulo',
    'Belem': 'Belém',
    'Maceio': 'Maceió',
    'Cuiaba': 'Cuiabá',
    'Araguaina': 'Araguaína',
    'Santarem': 'Santarém',
    'Eirunepe': 'Eirunepé',
  };

  /// The family's zone by its city: "Horários de São Paulo".
  static String zone(String iana) {
    final city = iana.split('/').last;
    return 'Horários de ${_cities[city] ?? city.replaceAll('_', ' ')}';
  }
}
