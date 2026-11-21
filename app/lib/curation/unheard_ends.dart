import 'curation_api.dart';

/// The videos that played to their end on this device while the server
/// has not heard it, because the report failed. The video screen and the
/// approval flow both report through it, so an end seen on either is sent
/// again before an approval, which the server refuses without it. Held
/// only for this run.
class UnheardEnds {
  final _videos = <String>{};

  /// Tells the draft of [videoId] that the video played to its end; a
  /// failure is kept here, never thrown.
  Future<void> report(CurationApi api, String videoId) async {
    try {
      await api.draftEnded(videoId);
      _videos.remove(videoId);
    } on Exception {
      _videos.add(videoId);
    }
  }

  /// Reports the end of [videoId] once more when the last report failed.
  Future<void> resend(CurationApi api, String videoId) async {
    if (_videos.contains(videoId)) await report(api, videoId);
  }
}
