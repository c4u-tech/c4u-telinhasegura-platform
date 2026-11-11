import 'dart:async';

import '../auth/api_error.dart';
import '../screentime/kid_time.dart';
import 'player_screen.dart' show doesNotFit;

/// Tells the server how long a play plays: a beat when the video starts, every [interval] while it
/// plays, and one when it stops. Beats go one after another. A closed play
/// (a long pause) is reopened; a day without time, or a video whose rest
/// no longer fits it, stops the loop and the screen is told.
/// Anything else is quiet: the server never credits more than 45 s, and
/// the video plays on.
class BeatLoop {
  BeatLoop({
    required this._playId,
    required this._beat,
    required this._reopen,
    required this._onTimeUp,
    required this._onDoesNotFit,
    this._position,
    this._sendPosition = false,
    Timer Function(Duration, void Function(Timer))? periodic,
  }) : _periodic = periodic ?? Timer.periodic;

  static const interval = Duration(seconds: 30);

  /// The play id, whether it plays, and where the video is when that is
  /// sent.
  final Future<KidTime> Function(String, bool, int?) _beat;

  /// Reads where the video is.
  final Future<int> Function()? _position;

  /// Whether the beats say where the video is: a family work's do. A
  /// reopened play says it again for itself.
  bool _sendPosition;
  final Future<KidPlay> Function(String closedPlayId) _reopen;
  final void Function() _onTimeUp;
  final void Function() _onDoesNotFit;
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
      await _beat(_playId, playing, await _at()).timeout(interval);
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

  /// Where the video is, or null when it is not sent or cannot be read: a
  /// beat without a position still counts the time.
  Future<int?> _at() async {
    final read = _position;
    if (!_sendPosition || read == null) return null;
    try {
      return await read().timeout(const Duration(seconds: 5));
    } on Object {
      return null;
    }
  }

  Future<void> _reopenPlay() async {
    try {
      final reopened = await _reopen(_playId).timeout(interval);
      _playId = reopened.playId;
      _sendPosition = reopened.family;
      if (_playing) {
        await _beat(_playId, true, await _at()).timeout(interval);
      }
    } on ApiError catch (e) {
      if (e.code == 'time_up' || doesNotFit(e)) {
        // Said only if the video was still meant to play: a screen that
        // paused or went has no one left to tell. A screen told stops the
        // video: left playing, nothing would count it.
        final wasPlaying = _playing && !_stopped;
        _halt();
        _stopped = true;
        if (!wasPlaying) return;
        if (e.code == 'time_up') {
          _onTimeUp();
        } else {
          _onDoesNotFit();
        }
      }
    } on Object {
      // Tried again on the next play.
    }
  }
}
