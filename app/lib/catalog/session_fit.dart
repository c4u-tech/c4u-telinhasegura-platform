import '../screentime/kid_time.dart';
import '../screentime/screentime_api.dart';

/// Whether a long work fits what is left of a child's day, read from the
/// guardian's view of that day, and the least more time that makes it
/// fit. The server decides at the start; this only chooses what to offer,
/// and a refusal there reads the day again.
class SessionFit {
  const SessionFit(this.rules, this.work);

  /// The more time a guardian may add at the start: none, or 15, 30 or
  /// 60 minutes, as the PIN door offers.
  static const options = [0, 15, 30, 60];

  /// The most a day may hold, extensions included.
  static const capMinutes = 240;

  /// The server lets a work start up to a minute past the time left.
  static const tolerance = Duration(seconds: 60);

  final ScreenTimeRules rules;

  /// What has to fit: the work's length.
  final Duration work;

  KidTimeState get _state => rules.today.time.state;

  /// What the child may still watch now, with no more time.
  Duration get left =>
      _state == KidTimeState.ok ? rules.today.time.remaining : Duration.zero;

  /// What the child could watch with [minutes] more today; null when they
  /// would carry the day past [capMinutes].
  Duration? withMore(int minutes) {
    if (minutes == 0) return left;
    final limit = rules.dailyMinutes + rules.today.extensionMinutes + minutes;
    if (limit > capMinutes) return null;
    final more = Duration(minutes: minutes);
    final dayLeft = Duration(minutes: limit) - rules.today.used;
    return switch (_state) {
      KidTimeState.ok => left + more,
      KidTimeState.timeUp => dayLeft,
      // Outside the hours, more time opens them only for its own minutes.
      KidTimeState.outsideWindow => dayLeft < more ? dayLeft : more,
    };
  }

  bool fitsWith(int minutes) => switch (withMore(minutes)) {
    final room? => work <= room + tolerance,
    null => false,
  };

  /// The least of [options] that makes the work fit; null when none does.
  int? get smallest {
    for (final m in options) {
      if (fitsWith(m)) return m;
    }
    return null;
  }

  /// How much more the work needs than [left], rounded up to the minute;
  /// zero when it fits as it is.
  Duration get shortfall {
    if (fitsWith(0)) return Duration.zero;
    final seconds = (work - left).inSeconds;
    return Duration(minutes: (seconds + 59) ~/ 60);
  }
}
