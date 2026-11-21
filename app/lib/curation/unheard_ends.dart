import 'package:flutter/foundation.dart';

import '../auth/api_client.dart' show AuthStatus;

/// The videos that played to their end on this device while the server
/// has not heard it, because the report failed. One holder serves the
/// curator's review, where the video screen and the approval flow both
/// report through it, and another the moderator's held screen; each sends
/// an end again before the write the server refuses without it, an
/// approval or a doubt's publication. Held only for this run and only for
/// the session that saw it: any change of [session] forgets them all, so
/// an end one account saw is never sent for another.
class UnheardEnds {
  UnheardEnds({
    required ValueListenable<AuthStatus> session,
    required this._send,
  }) {
    session.addListener(() {
      _videos.clear();
      _session++;
    });
  }

  final Future<void> Function(String videoId) _send;

  final _videos = <String>{};

  /// Counts the session changes, so a report that fails after one is not
  /// kept for the session that followed.
  int _session = 0;

  /// Tells the server that [videoId] played to its end; a failure is kept
  /// here, never thrown.
  Future<void> report(String videoId) async {
    final session = _session;
    try {
      await _send(videoId);
      _videos.remove(videoId);
    } on Exception {
      if (session == _session) _videos.add(videoId);
    }
  }

  /// Whether [videoId] played to its end here while the server has not
  /// heard it yet.
  bool holds(String videoId) => _videos.contains(videoId);

  /// Reports the end of [videoId] once more when the last report failed.
  Future<void> resend(String videoId) async {
    if (_videos.contains(videoId)) await report(videoId);
  }
}
