/// A child's day as the server counts it.
enum KidTimeState {
  ok,
  timeUp,
  outsideWindow;

  /// A state this app does not know reads as [ok]: the server still
  /// refuses the play.
  static KidTimeState parse(Object? v) => switch (v) {
    'time_up' => timeUp,
    'outside_window' => outsideWindow,
    _ => ok,
  };
}

/// The day state: what may be watched now. [remaining] informs; the app
/// never cuts a video.
class KidTime {
  const KidTime({required this.state, this.reason, required this.remaining});

  /// No time on the wire (an older server): nothing to say.
  static const unknown = KidTime(
    state: KidTimeState.ok,
    remaining: Duration.zero,
  );

  factory KidTime.fromJson(Map<String, dynamic>? j) => j == null
      ? unknown
      : KidTime(
          state: KidTimeState.parse(j['state']),
          reason: j['reason'] as String?,
          remaining: Duration(seconds: j['remaining_seconds'] as int? ?? 0),
        );

  final KidTimeState state;

  /// `daily` or `window`, when the state is not [KidTimeState.ok].
  final String? reason;
  final Duration remaining;
}

/// An opened play: the id its beats carry and the video for the player.
class KidPlay {
  const KidPlay({
    required this.playId,
    required this.youtubeId,
    required this.remaining,
  });

  factory KidPlay.fromJson(Map<String, dynamic> j) => KidPlay(
    playId: j['play_id'] as String,
    youtubeId: j['youtube_id'] as String,
    remaining: Duration(seconds: j['remaining_seconds'] as int? ?? 0),
  );

  final String playId;
  final String youtubeId;
  final Duration remaining;
}
