import '../kid/kid_player.dart';
import '../kid/link_opener.dart';

/// Where a guardian-side player stands after an event.
enum AdultPlayerOutcome {
  /// Still there, as YouTube's own controls leave it.
  playing,

  /// Another video played in place: the player is gone.
  stopped,

  /// The video could not play: the player is gone, and the screen shows
  /// the error note in the window's place, the decision doors still there.
  failed,

  /// The video played to its end: the player stays, the same video waiting
  /// in it again, and the screen may say so to whoever needs to know a
  /// review watched it all.
  ended,
}

/// What the curator's and admin's screens do with their player's [event]:
/// a link out of the embed opens in the
/// browser through [links], without the PIN, since kid mode and linked
/// devices never reach these routes; another video playing in place,
/// not the one under review, stops the player; a failure lets it go; the
/// video's end is told, the player kept and the same video cued again, so
/// the window shows its own poster rather than YouTube's end screen of
/// other videos.
/// Kid mode's player screen keeps its own rules.
Future<AdultPlayerOutcome> followAdultPlayer(
  PlayerEvent event, {
  required KidPlayback playback,
  required LinkOpener links,
}) async {
  switch (event) {
    case PlayerLeaving(:final url):
      await links.open(url);
      return AdultPlayerOutcome.playing;
    case PlayerStrayed():
      await playback.close();
      return AdultPlayerOutcome.stopped;
    case PlayerFailed():
      await playback.close();
      return AdultPlayerOutcome.failed;
    case PlayerEnded():
      // The end counts whether or not the window can show the video again
      // (its web view may already be gone): an approval waits on it.
      try {
        await playback.cue();
      } on Object {
        // The poster stays unrestored; nothing else depends on it.
      }
      return AdultPlayerOutcome.ended;
    case PlayerPlaying() || PlayerPaused():
      return AdultPlayerOutcome.playing;
  }
}
