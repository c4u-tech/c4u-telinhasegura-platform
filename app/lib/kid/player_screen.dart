import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_error.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../screentime/kid_time.dart';
import 'beat_loop.dart';
import 'hold_to_exit.dart';
import 'kid_error_note.dart';
import 'kid_layout.dart';
import 'kid_player.dart';
import 'player_fullscreen.dart';
import 'player_keys.dart';
import 'player_stage.dart';

/// `/crianca/assistir/:id`: one video in a telinha inside the telinha.
/// The embed stands whole in a 16:9 window,
/// nothing ever drawn over it and no gesture of ours on it (YouTube's
/// Required Minimum Functionality); back and play/pause sit beside it.
/// When the video ends the player goes and the
/// shelves come back; nothing plays next.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.videoId, this.play});

  /// Our video's id, as the shelves know it.
  final String videoId;

  /// The YouTube id a play just returned; null when the route was opened
  /// without one (a reload, a typed URL), which plays first.
  final KidPlay? play;

  static const back = 'Voltar';
  static const pauseLabel = 'Pausar';
  static const playLabel = 'Continuar';

  /// The server took the video off this child's shelves.
  static const videoGone = 'Esse vídeo saiu da prateleira.';

  /// The player could not play it.
  static const videoFailed = 'Esse vídeo não abriu. Escolha outro.';

  /// A play that failed for another reason (network, server).
  static const cannotOpen = 'Não deu para abrir o vídeo agora.';

  /// How long the error note stays before the shelves come back.
  static const errorPause = Duration(seconds: 4);

  /// The widest the player grows.
  static const maxWidth = PlayerStage.maxWidth;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  KidPlayback? _playback;
  BeatLoop? _beats;
  StreamSubscription<PlayerEvent>? _events;
  Timer? _return;
  bool _started = false;

  /// What the player last said. Until it says it plays, the key offers
  /// to play: a browser may hold autoplay until a tap.
  bool _playing = false;
  bool _failed = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.play case final play?) {
      _open(play);
    } else {
      unawaited(_playFirst());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _return?.cancel();
    _beats?.stop();
    unawaited(_events?.cancel());
    unawaited(_playback?.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _beats?.paused();
      unawaited(_playback?.pause());
    }
  }

  /// A route opened without a play asks the server first; a day
  /// without time sends it to the sleeping home.
  Future<void> _playFirst() async {
    final services = AppScope.of(context);
    try {
      final play = await services.child.play(widget.videoId);
      if (mounted) setState(() => _open(play));
    } on Object catch (e) {
      final note = refusalNote(e);
      services.kidReturn.value = (note: note, refetch: refetchAfter(note));
      if (mounted) context.go(Routes.kidHome);
    }
  }

  void _open(KidPlay play) {
    final services = AppScope.of(context);
    final playback = services.player.open(play.youtubeId);
    _playback = playback;
    _events = playback.events.listen(_on);
    _beats = BeatLoop(
      playId: play.playId,
      beat: (id, playing) => services.child.beat(id, playing: playing),
      reopen: () => services.child.play(widget.videoId),
      // The day ran out between videos: leaving, the home reads the
      // catalogue again and sleeps.
      onTimeUp: () {
        unawaited(_playback?.pause());
        if (mounted) _leave();
      },
    );
  }

  void _on(PlayerEvent event) {
    switch (event) {
      case PlayerPlaying():
        setState(() => _playing = true);
        _beats?.playing();
      case PlayerPaused():
        setState(() => _playing = false);
        _beats?.paused();
      case PlayerEnded() || PlayerStrayed():
        _beats?.stop();
        _leave();
      case PlayerFailed():
        _fail();
      case PlayerLeaving(:final url):
        _door(url);
    }
  }

  /// A link out of the embed (the logo, the title, a suggestion) waits
  /// behind the parents' PIN; the video waits paused beneath the gate.
  /// The link is held in memory, never in the route.
  void _door(Uri url) {
    final services = AppScope.of(context);
    if (services.linkErrand != null) return;
    _beats?.paused();
    unawaited(_playback?.pause());
    services.linkErrand = url;
    unawaited(context.push<void>(Routes.kidExit));
  }

  /// Back to the shelves, the player let go first. The home reads its
  /// catalogue again, quietly: a video the player could not play may have
  /// left the shelves, and the day may have run out while it played.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    unawaited(_close());
    final returns = AppScope.of(context).kidReturn;
    returns.value ??= (note: null, refetch: true);
    context.go(Routes.kidHome);
  }

  /// Lets the player go at once; nothing it says afterwards counts.
  Future<void> _close() async {
    _beats?.stop();
    final playback = _playback;
    final events = _events;
    _playback = null;
    _events = null;
    unawaited(events?.cancel());
    await playback?.close();
  }

  /// The player could not play it: told once to the server, the player
  /// gone, the note where it stood, then the shelves.
  void _fail() {
    if (_failed) return;
    _beats?.stop();
    final services = AppScope.of(context);
    unawaited(_report(services));
    unawaited(_close());
    setState(() => _failed = true);
    _return = Timer(PlayerScreen.errorPause, () {
      if (mounted) _leave();
    });
  }

  Future<void> _report(AppServices services) async {
    try {
      await services.child.reportUnavailable(widget.videoId);
    } on Object {
      // The shelves come back either way; the server re-checks its own.
    }
  }

  void _toggle() {
    final playback = _playback;
    if (playback == null) return;
    unawaited(_playing ? playback.pause() : playback.play());
  }

  @override
  Widget build(BuildContext context) {
    // A phone turned sideways shows the video alone, while the video is
    // what stands in the window (fullscreen design).
    final full =
        !_failed &&
        playerFullscreen(
          size: MediaQuery.sizeOf(context),
          platform: defaultTargetPlatform,
          web: kIsWeb,
        );
    return SystemBarsHidden(
      active: full,
      child: KidLayout(
        exit: HoldToExit(onExit: () => context.go(Routes.kidExit)),
        fullWidth: true,
        scrolls: false,
        strip: !full,
        child: PlayerStage(
          bare: full,
          // Failed, the player is gone and the kid note takes its place,
          // growing past the window's height at large text rather than clip.
          window: (size) => _failed
              ? ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: KidErrorNote(
                        PlayerScreen.videoFailed,
                        picture: math.min(96, size.height * .45),
                      ),
                    ),
                  ),
                )
              : SizedBox.fromSize(size: size, child: _playback?.view),
          back: PlayerKey(
            glyph: PlayerGlyph.back,
            label: PlayerScreen.back,
            onPressed: _leave,
          ),
          toggle: _failed
              ? null
              : PlayerKey(
                  glyph: _playing ? PlayerGlyph.pause : PlayerGlyph.play,
                  label: _playing
                      ? PlayerScreen.pauseLabel
                      : PlayerScreen.playLabel,
                  filled: true,
                  onPressed: _toggle,
                ),
        ),
      ),
    );
  }
}

/// What the shelves say after a play the server or the network refused;
/// null for a day without time, which the sleeping home says
/// instead.
String? refusalNote(Object error) => switch (error) {
  ApiError(code: 'time_up') => null,
  ApiError(code: 'video_not_allowed' || 'not_found') => PlayerScreen.videoGone,
  _ => PlayerScreen.cannotOpen,
};

/// Whether the shelves must be read again after a refusal worded [note]:
/// the video left them, or the day ran out.
bool refetchAfter(String? note) =>
    note == null || note == PlayerScreen.videoGone;
