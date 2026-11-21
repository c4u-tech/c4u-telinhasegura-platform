import 'package:flutter/foundation.dart';

import '../auth/api_client.dart' show AuthStatus;

/// The videos that played to their end on this device in this session,
/// and among them those the server has not heard of, because the report
/// failed. One holder serves the curator's review, where the video screen
/// and the approval flow both report through it, and another the
/// moderator's held screen. An end seen here counts on every screen of the
/// session at once, even before the server's reads have it; the server
/// stays the gate, so an end it has not heard is sent again before the
/// write it refuses without it, an approval or a doubt's publication. Held
/// only for this run and only for the session that saw it: any change of
/// [session] forgets them all, so an end one account saw is never counted
/// or sent for another.
class UnheardEnds {
  UnheardEnds({
    required ValueListenable<AuthStatus> session,
    required this._send,
  }) {
    session.addListener(() {
      _seen.clear();
      _videos.clear();
      _session++;
    });
  }

  final Future<void> Function(String videoId) _send;

  /// Every end seen in this session, heard by the server or not.
  final _seen = <String>{};

  /// The ends whose report failed.
  final _videos = <String>{};

  /// Counts the session changes, so a report that fails after one is not
  /// kept for the session that followed.
  int _session = 0;

  /// Tells the server that [videoId] played to its end; a failure is kept
  /// here, never thrown.
  Future<void> report(String videoId) async {
    final session = _session;
    _seen.add(videoId);
    try {
      await _send(videoId);
      _videos.remove(videoId);
    } on Exception {
      if (session == _session) _videos.add(videoId);
    }
  }

  /// Whether [videoId] played to its end here in this session, whether or
  /// not the server has heard it yet.
  bool seen(String videoId) => _seen.contains(videoId);

  /// Reports the end of [videoId] once more when the last report failed.
  Future<void> resend(String videoId) async {
    if (_videos.contains(videoId)) await report(videoId);
  }
}
