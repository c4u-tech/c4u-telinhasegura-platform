import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../curation/kid_catalog.dart';
import '../design/tevi.dart';
import '../design/tokens.dart';
import '../screentime/kid_time.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'beat_loop.dart';
import 'hold_to_exit.dart';
import 'kid_layout.dart';
import 'kid_player.dart';
import 'pack_row.dart' show PackModules;
import 'player_fullscreen.dart';
import 'player_keys.dart';
import 'player_screen.dart';
import 'player_stage.dart';
import 'shelves.dart' show HollowThumbnail;

/// What the shelves hand the pacotinho's player: the pacotinho, the video
/// the server let play first and its play.
class PackStart {
  const PackStart({
    required this.pack,
    required this.index,
    required this.play,
  });

  final KidPack pack;
  final int index;
  final KidPlay play;
}

enum _Phase { playing, breath, goodbye }

/// `/crianca/pacotinho/:id`: a pacotinho the child chose, played through.
/// Each video is an ordinary
/// play the server re-checks, in the player's whole window. When one ends
/// the player goes and the breath stands in its place: the next cover and
/// the mascot, continuing by itself after [breath] or at a tap. After
/// the last, the goodbye, then the shelves; nothing plays after it. A
/// video refused is passed over; a day without time sends the home to
/// sleep.
class PackPlayerScreen extends StatefulWidget {
  const PackPlayerScreen({super.key, required this.start});

  /// Null when the route was opened without its pacotinho (a reload, a
  /// typed URL): it returns to the shelves.
  final PackStart? start;

  static const breath = Duration(seconds: 4);
  static const goodbye = Duration(seconds: 3);

  /// The one crossfade between window states.
  static const fade = Motion.change;

  static String progressLabel(int k, int n) => 'Vídeo $k de $n';

  @override
  State<PackPlayerScreen> createState() => _PackPlayerScreenState();
}

class _PackPlayerScreenState extends State<PackPlayerScreen>
    with WidgetsBindingObserver {
  late final KidPack _pack;
  bool _started = false;

  /// The video playing, or the one played last.
  int _index = 0;
  _Phase _phase = _Phase.playing;

  /// The video the breath shows next.
  int _next = 0;

  /// A play for the next video is on its way; the breath waits.
  bool _advancing = false;

  KidPlayback? _playback;
  BeatLoop? _beats;
  StreamSubscription<PlayerEvent>? _events;
  Timer? _timer;
  bool _playing = false;
  bool _leaving = false;
  bool _background = false;
  final _thumbs = <String, Future<Uint8List>>{};

  int get _filled =>
      _phase == _Phase.goodbye ? _pack.videos.length : _index + 1;

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
    final start = widget.start;
    if (start == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.kidHome);
      });
      return;
    }
    _pack = start.pack;
    _open(start.index, start.play);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _beats?.stop();
    unawaited(_events?.cancel());
    unawaited(_playback?.close());
    super.dispose();
  }

  /// Going to the background pauses the video, and the breath stops
  /// counting; back, it starts over.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_background && _phase == _Phase.breath && !_advancing) {
        _background = false;
        _breathe();
      }
      _background = false;
      return;
    }
    _background = true;
    _beats?.paused();
    unawaited(_playback?.pause());
    if (_phase == _Phase.breath) _timer?.cancel();
  }

  void _open(int index, KidPlay play) {
    final services = AppScope.of(context);
    final video = _pack.videos[index];
    final playback = services.player.open(play.youtubeId);
    _index = index;
    _phase = _Phase.playing;
    _playing = false;
    _playback = playback;
    _events = playback.events.listen(_on);
    _beats = BeatLoop(
      playId: play.playId,
      beat: (id, playing, _) => services.child.beat(id, playing: playing),
      reopen: (closed) => services.child.play(video.id, continues: closed),
      // The day ran out mid-video: the home reads its catalogue and
      // sleeps.
      onTimeUp: () {
        unawaited(_playback?.pause());
        if (mounted) _leave();
      },
      // A pause outlived the play and the rest of the video no longer fits
      // the day: stopped, and the pacotinho ends with its goodbye.
      onDoesNotFit: () {
        unawaited(_playback?.pause());
        if (!mounted || _leaving) return;
        unawaited(_close());
        _goodbye();
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
      case PlayerEnded():
        unawaited(_close());
        _after();
      case PlayerStrayed():
        // Not the pacotinho's video: stopped at once.
        _leave();
      case PlayerFailed():
        unawaited(_report(_pack.videos[_index].id));
        unawaited(_close());
        setState(() => _advancing = true);
        unawaited(_advance(_index + 1));
      case PlayerLeaving(:final url):
        _door(url);
    }
  }

  /// A link out waits behind the parents' PIN, as in the single player.
  void _door(Uri url) {
    final services = AppScope.of(context);
    if (services.linkErrand != null) return;
    _beats?.paused();
    unawaited(_playback?.pause());
    services.linkErrand = url;
    unawaited(context.push<void>(Routes.kidExit));
  }

  /// A video ended: the breath before the next, or the goodbye after the
  /// last.
  void _after() {
    final next = _index + 1;
    if (next >= _pack.videos.length) {
      _goodbye();
      return;
    }
    setState(() {
      _phase = _Phase.breath;
      _next = next;
    });
    if (!_background) _breathe();
  }

  void _breathe() {
    _timer?.cancel();
    _timer = Timer(PackPlayerScreen.breath, _continue);
  }

  /// The breath is over, by itself or at a tap.
  void _continue() {
    if (_phase != _Phase.breath || _advancing || _leaving) return;
    _timer?.cancel();
    setState(() => _advancing = true);
    unawaited(_advance(_next));
  }

  /// Plays the first video from [from] the server lets play: a refusal is
  /// passed over with no note; a day without time or a paused profile
  /// ends the pacotinho, and the home says which; none left, the goodbye.
  Future<void> _advance(int from) async {
    final services = AppScope.of(context);
    for (var i = from; i < _pack.videos.length; i++) {
      try {
        final play = await services.child.play(_pack.videos[i].id);
        if (!mounted || _leaving) return;
        setState(() {
          _advancing = false;
          _open(i, play);
        });
        return;
      } on Object catch (e) {
        if (!mounted || _leaving) return;
        if (refusesEvery(e)) {
          _leave();
          return;
        }
        // The time left only shrinks, so the pacotinho ends here with the
        // goodbye rather than reaching for another video.
        if (doesNotFit(e)) {
          setState(() => _advancing = false);
          _goodbye();
          return;
        }
      }
    }
    if (!mounted || _leaving) return;
    setState(() => _advancing = false);
    _goodbye();
  }

  void _goodbye() {
    setState(() => _phase = _Phase.goodbye);
    _timer?.cancel();
    _timer = Timer(PackPlayerScreen.goodbye, _leave);
  }

  /// Back to the shelves, the player let go first; the home reads its
  /// catalogue again, quietly.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    unawaited(_close());
    final returns = AppScope.of(context).kidReturn;
    returns.value ??= (note: null, refetch: true);
    backFromPlayer(context);
  }

  Future<void> _close() async {
    _beats?.stop();
    final playback = _playback;
    final events = _events;
    _playback = null;
    _events = null;
    _playing = false;
    unawaited(events?.cancel());
    await playback?.close();
  }

  Future<void> _report(String videoId) async {
    try {
      await AppScope.of(context).child.reportUnavailable(videoId);
    } on Object {
      // The pacotinho moves on either way; the server re-checks its own.
    }
  }

  void _toggle() {
    final playback = _playback;
    if (playback == null) return;
    unawaited(_playing ? playback.pause() : playback.play());
  }

  Future<Uint8List> _thumbnail(String id) =>
      _thumbs[id] ??= AppScope.of(context).child.thumbnail(id);

  /// Our frames fade in from the ground; the embed never fades, since
  /// nothing veils it in any state (the Whole Window Rule).
  Widget _fadeIn(Key key, Widget child) {
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : PackPlayerScreen.fade,
      curve: Motion.settle,
      builder: (_, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }

  Widget _window(Size size) => switch (_phase) {
    _Phase.playing when _playback != null => SizedBox.fromSize(
      size: size,
      child: _playback!.view,
    ),
    // A failed video's place while the next is asked for.
    _Phase.playing => SizedBox.fromSize(size: size),
    _Phase.breath => _fadeIn(
      ValueKey('breath-$_next'),
      PackBreath(
        size: size,
        cover: _thumbnail(_pack.videos[_next].id),
        onTap: _continue,
      ),
    ),
    _Phase.goodbye => _fadeIn(
      const ValueKey('goodbye'),
      PackGoodbye(size: size, onTap: _leave),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    if (start == null) return const SizedBox.shrink();
    final n = _pack.videos.length;
    // A phone turned sideways shows each video alone; the breath and the
    // goodbye keep the strip and the rail.
    final full =
        _phase == _Phase.playing &&
        playerFullscreen(
          size: MediaQuery.sizeOf(context),
          platform: defaultTargetPlatform,
          web: kIsWeb,
        );
    return SystemBarsHidden(
      active: full,
      child: KidLayout(
        exit: HoldToExit(onExit: () => context.go(Routes.kidExit)),
        // Watching is a dark room; turned sideways, the video alone keeps
        // the child's ground around it, as it always has.
        ground: full ? null : BrandColors.dark,
        mark: false,
        fullWidth: true,
        scrolls: false,
        strip: !full,
        child: PlayerStage(
          bare: full,
          // The breath and the goodbye hold the mascot in the window's
          // place.
          perched: _phase == _Phase.playing,
          window: _window,
          progress: Semantics(
            label: PackPlayerScreen.progressLabel(_filled, n),
            child: ExcludeSemantics(
              child: PackModules(
                count: n,
                filled: _filled,
                height: PlayerStage.module,
                color: BrandColors.sky,
              ),
            ),
          ),
          back: PlayerKey(
            glyph: PlayerGlyph.back,
            label: PlayerScreen.back,
            onPressed: _leave,
          ),
          toggle: switch (_phase) {
            _Phase.goodbye => null,
            _Phase.breath => PlayerKey(
              glyph: PlayerGlyph.play,
              label: PlayerScreen.playLabel,
              filled: true,
              size: PlayerStage.toggleSize,
              onPressed: _continue,
            ),
            _Phase.playing => PlayerKey(
              glyph: _playing ? PlayerGlyph.pause : PlayerGlyph.play,
              label: _playing
                  ? PlayerScreen.pauseLabel
                  : PlayerScreen.playLabel,
              filled: true,
              size: PlayerStage.toggleSize,
              onPressed: _toggle,
            ),
          },
        ),
      ),
    );
  }
}

/// The breath between two videos, in the window's place: on the night
/// itself, the next video's cover in a rounded frame with the mascot
/// standing on its top edge toward the end, watching it. No number, no
/// filling bar. A tap continues; the key beside it says so to assistive
/// technology.
class PackBreath extends StatelessWidget {
  const PackBreath({
    super.key,
    required this.size,
    required this.cover,
    required this.onTap,
  });

  final Size size;
  final Future<Uint8List> cover;
  final VoidCallback onTap;

  /// The frame's corner against its height: the highlight's on the home.
  static const corner = FieldSizes.heroCorner / 197;

  /// The mascot's box against the frame's height.
  static const _tevi = .45;

  /// How much of the window the frame and the mascot over it take, so the
  /// window's own ground still frames them.
  static const _width = .58;
  static const _height = .85;

  @override
  Widget build(BuildContext context) {
    // The room the mascot takes above the frame, for each unit of the
    // frame's height.
    const stand = _tevi * (TeviPainter.perchY - TeviPainter.top);
    final h = math.min(
      size.width * _width * 9 / 16,
      size.height * _height / (1 + stand),
    );
    final frame = Size(h * 16 / 9, h);
    final tevi = h * _tevi;
    final above = h * stand - TeviPainter.perchOverlap;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The keys beside it say the same to assistive technology.
      excludeFromSemantics: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: size,
          child: ColoredBox(
            color: BrandColors.dark,
            // The window's stand-in is the dark room itself: what stands in it
            // reads on the night, as the player's keys do.
            child: TeviGround(
              color: BrandColors.dark,
              child: Center(
                child: SizedBox(
                  width: frame.width,
                  height: above + frame.height,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: above,
                        width: frame.width,
                        height: frame.height,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(h * corner),
                          child: FutureBuilder(
                            future: cover,
                            builder: (context, snap) => switch (snap) {
                              AsyncSnapshot(hasData: true, :final data!) =>
                                Image.memory(
                                  data,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) =>
                                      HollowThumbnail(radius: h * corner),
                                ),
                              AsyncSnapshot(hasError: true) => HollowThumbnail(
                                radius: h * corner,
                              ),
                              _ => const SizedBox.expand(),
                            },
                          ),
                        ),
                      ),
                      // Toward the end, looking on into the picture.
                      PositionedDirectional(
                        start:
                            frame.width * .78 -
                            tevi * TeviPainter.body.center.dx,
                        top:
                            above +
                            TeviPainter.perchOverlap -
                            tevi * TeviPainter.perchY,
                        width: tevi,
                        height: tevi,
                        child: FacingTevi(size: tevi),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pacotinho's end, in the window's place: the mascot winking goodbye,
/// and one word beneath it, "Fim". Nothing more to watch; a tap goes back
/// to the shelves sooner.
class PackGoodbye extends StatelessWidget {
  const PackGoodbye({super.key, required this.size, required this.onTap});

  final Size size;
  final VoidCallback onTap;

  static const word = 'Fim';

  @override
  Widget build(BuildContext context) {
    // The word grows with the window, as the nickname does from 840 px.
    final wide = size.width >= FieldSizes.wideBreakpoint;
    final text = wide
        ? Theme.of(context).textTheme.displaySmall
        : Theme.of(context).textTheme.headlineSmall;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The keys beside it say the same to assistive technology.
      excludeFromSemantics: true,
      onTap: onTap,
      child: SizedBox.fromSize(
        size: size,
        child: ColoredBox(
          color: BrandColors.dark,
          // The window's stand-in is the dark room itself: what stands in it
          // reads on the night, as the player's keys do.
          child: TeviGround(
            color: BrandColors.dark,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              // At large text the figure and the word shrink together
              // rather than leave the window.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FacingTevi(size: size.height * .55, look: TeviLook.winking),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        word,
                        textAlign: TextAlign.center,
                        style: text?.copyWith(color: BrandColors.cream),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
