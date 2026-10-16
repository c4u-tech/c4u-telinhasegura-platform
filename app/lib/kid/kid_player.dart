import 'package:flutter/widgets.dart';

/// What the embedded player tells the player screen. The
/// screen decides what each means; the player only says.
sealed class PlayerEvent {
  const PlayerEvent();
}

/// The video is playing.
class PlayerPlaying extends PlayerEvent {
  const PlayerPlaying();
}

/// The video is paused, by us or by the player.
class PlayerPaused extends PlayerEvent {
  const PlayerPaused();
}

/// The video reached its end.
class PlayerEnded extends PlayerEvent {
  const PlayerEnded();
}

/// The player could not play the video: not embeddable, removed, private
/// or an invalid id (YouTube's error codes 2, 5, 100, 101, 150).
class PlayerFailed extends PlayerEvent {
  const PlayerFailed();
}

/// The player asked to go somewhere outside its embed: the YouTube logo,
/// the title, "Assistir no YouTube", a suggestion. Nothing was loaded.
class PlayerLeaving extends PlayerEvent {
  const PlayerLeaving(this.url);

  final Uri url;
}

/// The player started a video other than the one it was opened for, such
/// as a suggestion played in place: not a video the community screened.
class PlayerStrayed extends PlayerEvent {
  const PlayerStrayed();
}

/// Opens one embedded player per screen. The app's seam over the YouTube
/// embed, so widget tests run without a WebView (Player seam).
abstract interface class KidPlayer {
  /// A player for [youtubeId] that starts on its own: the child's tap on
  /// the thumbnail was the choice.
  KidPlayback open(String youtubeId);
}

/// One open player.
abstract interface class KidPlayback {
  /// The embed itself, to be laid out whole, with nothing drawn over it.
  Widget get view;

  Stream<PlayerEvent> get events;

  Future<void> play();

  Future<void> pause();

  /// Stops the video and lets the embed go; nothing plays after it.
  Future<void> close();
}
