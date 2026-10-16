import 'dart:async';

import '../auth/api_error.dart';
import '../screentime/kid_time.dart';

/// Tells the server how long a play plays: a beat when the video starts, every [interval] while it
/// plays, and one when it stops. Beats go one after another. A closed play
/// (a long pause) is reopened; a day without time stops the loop.
/// Anything else is quiet: the server never credits more than 45 s, and
/// the video plays on.
class BeatLoop {
  BeatLoop({
    required this._playId,
    required this._beat,
    required this._reopen,
    required this._onTimeUp,
    Timer Function(Duration, void Function(Timer))? periodic,
  }) : _periodic = periodic ?? Timer.periodic;

  static const interval = Duration(seconds: 30);

  final Future<KidTime> Function(String, bool) _beat;
  final Future<KidPlay> Function() _reopen;
  final void Function() _onTimeUp;
  final Timer Function(Duration, void Function(Timer)) _periodic;

  String _playId;
  bool _playing = false;
  bool _stopped = false;
  Timer? _timer;
  Future<void> _queue = Future.value();

  /// The play the beats carry now; a reopen changes it.
  String get playId => _playId;

  void playing() {
    if (_stopped || _playing) return;
    _playing = true;
    _send(true);
    _timer = _periodic(interval, (_) => _send(true));
  }

  void paused() {
    if (_stopped || !_playing) return;
    _halt();
    _send(false);
  }

  /// The player is going: a last beat if it played, then nothing more.
  void stop() {
    paused();
    _stopped = true;
  }

  void _halt() {
    _playing = false;
    _timer?.cancel();
    _timer = null;
  }

  void _send(bool playing) => _queue = _queue.then((_) => _once(playing));

  Future<void> _once(bool playing) async {
    try {
      // Bounded, so one hung call cannot stall the serialized queue.
      await _beat(_playId, playing).timeout(interval);
    } on ApiError catch (e) {
      // Only a beat that says "playing" brings a closed play back; a pause
      // or stop beat on a closed play has nothing left to tell.
      if (e.code == 'play_closed' && playing && !_stopped) {
        await _reopenPlay();
      }
    } on Object {
      // Offline or a server hiccup: the next tick beats again.
    }
  }

  Future<void> _reopenPlay() async {
    try {
      _playId = (await _reopen().timeout(interval)).playId;
      if (_playing) await _beat(_playId, true).timeout(interval);
    } on ApiError catch (e) {
      if (e.code == 'time_up') {
        // Said only if the video was still meant to play: a screen that
        // paused or went has no one left to tell.
        final wasPlaying = _playing && !_stopped;
        _halt();
        _stopped = true;
        if (wasPlaying) _onTimeUp();
      }
    } on Object {
      // Tried again on the next play.
    }
  }
}
