import 'package:flutter/foundation.dart';

import '../auth/api_client.dart' show AuthStatus;
import 'curation_api.dart';

/// The videos that played to their end on this device while the server
/// has not heard it, because the report failed. The video screen and the
/// approval flow both report through it, so an end seen on either is sent
/// again before an approval, which the server refuses without it. Held
/// only for this run and only for the session that saw it: any change of
/// [session] forgets them all, so an end one account saw is never sent for
/// another.
class UnheardEnds {
  UnheardEnds({required ValueListenable<AuthStatus> session}) {
    session.addListener(() {
      _videos.clear();
      _session++;
    });
  }

  final _videos = <String>{};

  /// Counts the session changes, so a report that fails after one is not
  /// kept for the session that followed.
  int _session = 0;

  /// Tells the draft of [videoId] that the video played to its end; a
  /// failure is kept here, never thrown.
  Future<void> report(CurationApi api, String videoId) async {
    final session = _session;
    try {
      await api.draftEnded(videoId);
      _videos.remove(videoId);
    } on Exception {
      if (session == _session) _videos.add(videoId);
    }
  }

  /// Reports the end of [videoId] once more when the last report failed.
  Future<void> resend(CurationApi api, String videoId) async {
    if (_videos.contains(videoId)) await report(api, videoId);
  }
}
