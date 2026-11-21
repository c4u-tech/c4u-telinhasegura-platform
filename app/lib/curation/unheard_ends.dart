import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/api_client.dart' show AuthStatus;

/// The ends of videos that played on this device in this session, each
/// for the video's round, and among them those the server has not heard
/// of, because the report failed. One holder serves the curator's review,
/// where the video screen and the approval flow both report through it,
/// and another the moderator's held screen. An end seen here counts on
/// every screen of the session at once, even before the server's reads
/// have it, but only in its round: the server forgets a round's ends when
/// the round closes, and so does a video back in a new round. The server
/// stays the gate: before the write it refuses without the end, an
/// approval or a doubt's publication, a report still on its way is
/// awaited and one that failed is sent again; when the server still says
/// the video did not play to its end, the screen [forget]s it. Held only
/// for this run and only for the session that saw it: any change of
/// [session] forgets them all, so an end one account saw is never counted
/// or sent for another. It tells its listeners when an end is forgotten,
/// so a screen still open beneath the refused write stops saying it
/// played.
class UnheardEnds extends ChangeNotifier {
  UnheardEnds({
    required ValueListenable<AuthStatus> session,
    required this._send,
  }) {
    session.addListener(() {
      _seen.clear();
      _failed.clear();
      _pending.clear();
      _session++;
    });
  }

  final Future<void> Function(String videoId) _send;

  /// Every end seen in this session, heard by the server or not.
  final _seen = <_End>{};

  /// The ends whose report failed.
  final _failed = <_End>{};

  /// The reports on their way.
  final _pending = <_End, Future<void>>{};

  /// Counts the session changes, so a report that fails after one is not
  /// kept for the session that followed.
  int _session = 0;

  /// Tells the server that [videoId] played to its end in [round]; a
  /// failure is kept here, never thrown.
  Future<void> report(String videoId, int round) {
    final end = (videoId, round);
    final sent = _report(end);
    _pending[end] = sent;
    unawaited(
      sent.whenComplete(() {
        if (_pending[end] == sent) _pending.remove(end);
      }),
    );
    return sent;
  }

  Future<void> _report(_End end) async {
    final session = _session;
    _seen.add(end);
    try {
      await _send(end.$1);
      _failed.remove(end);
    } on Exception {
      if (session == _session) _failed.add(end);
    }
  }

  /// Whether [videoId] played to its end here in this session in [round],
  /// whether or not the server has heard it yet.
  bool seen(String videoId, int round) => _seen.contains((videoId, round));

  /// Forgets the end of [videoId] in [round]: the server says it never
  /// heard one.
  void forget(String videoId, int round) {
    _seen.remove((videoId, round));
    _failed.remove((videoId, round));
    forgotten = (videoId, round);
    notifyListeners();
  }

  /// The end last forgotten, as video and round.
  (String, int)? forgotten;

  /// Before a write that needs the end of [videoId] in [round]: waits for
  /// a report still on its way, then reports once more one that failed.
  Future<void> resend(String videoId, int round) async {
    final end = (videoId, round);
    if (_pending[end] case final sent?) await sent;
    if (_failed.contains(end)) await report(videoId, round);
  }
}

/// A video's end in one of its rounds.
typedef _End = (String, int);
