import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'kid_frame.dart';
import 'kid_player.dart';

/// The embed's parameters for kid mode: the
/// privacy-enhanced host, no YouTube controls, related videos only from
/// the same channel, no fullscreen, no keyboard, no annotations, inline.
/// [origin] identifies the app to YouTube as the HTTP Referer its Required
/// Minimum Functionality asks of an embedded player.
YoutubePlayerParams kidPlayerParams({String? origin}) => YoutubePlayerParams(
  showControls: false,
  strictRelatedVideos: true,
  showFullscreenButton: false,
  enableKeyboard: false,
  showVideoAnnotations: false,
  playsInline: true,
  enableCaption: false,
  privacyEnhancedMode: true,
  captionLanguage: 'pt',
  interfaceLanguage: 'pt',
  origin: origin,
);

/// The embed's parameters for the guardian side (curation screens):
/// YouTube's own controls, fullscreen and keyboard, captions at
/// the viewer's choice; the same privacy-enhanced host, same-channel
/// suggestions, no annotations and inline playing as kid mode. Nothing
/// starts on its own: the adult player cues the video.
YoutubePlayerParams adultPlayerParams({String? origin}) => YoutubePlayerParams(
  showControls: true,
  strictRelatedVideos: true,
  showFullscreenButton: true,
  enableKeyboard: true,
  showVideoAnnotations: false,
  playsInline: true,
  enableCaption: false,
  privacyEnhancedMode: true,
  captionLanguage: 'pt',
  interfaceLanguage: 'pt',
  origin: origin,
);

/// The app's own identity as a URL, for the embed's Referer: Android's
/// application id and iOS's bundle id are the same. Null on the web, where
/// the page's own origin is sent.
String? appOrigin() => kIsWeb ? null : 'https://tech.coding4u.telinhasegura';

/// What the player's WebView may load.
enum KidNavigation {
  /// The player's own page and the embed itself.
  allow,

  /// Anything else inside the player: dropped.
  block,

  /// A link the viewer followed out of the embed: never loaded in the
  /// player, handed to the screen, which asks for the parents' PIN.
  leave,
}

final _embed = RegExp(r'^https://(?:www\.)?youtube(?:-nocookie)?\.com/embed/');

/// Decides a WebView navigation for kid mode. The package's own default
/// would play a suggested video in place and open YouTube with no gate;
/// here nothing outside the embed is ever loaded in the player.
KidNavigation decideNavigation(
  Uri? uri, {
  required bool mainFrame,
  required Uri base,
}) {
  if (uri == null) return KidNavigation.block;
  if (uri.scheme == 'about' || uri.scheme == 'data') {
    return KidNavigation.allow;
  }
  if (uri.scheme == base.scheme &&
      uri.host == base.host &&
      (uri.path.isEmpty || uri.path == '/')) {
    return KidNavigation.allow;
  }
  if (_embed.hasMatch(uri.toString())) return KidNavigation.allow;
  if (!mainFrame) return KidNavigation.block;
  if (uri.scheme == 'https' || uri.scheme == 'http') {
    return KidNavigation.leave;
  }
  return KidNavigation.block;
}

/// The production [KidPlayer]: the YouTube IFrame embed through
/// `youtube_player_iframe`, with the package's own widget left out (its
/// fullscreen gestures, overlay and placeholder thumbnail would break the
/// rules above), so the screen gets the bare WebView.
class YouTubeKidPlayer implements KidPlayer {
  /// [hardenFrame] restricts the player's frame before anything loads into
  /// it; tests pass a fake to watch the call.
  YouTubeKidPlayer({this.hardenFrame = hardenKidFrame});

  final FrameHardener hardenFrame;

  @override
  KidPlayback open(String youtubeId) {
    final origin = appOrigin();
    return _YouTubePlayback(
      youtubeId,
      origin: origin,
      params: kidPlayerParams(origin: origin),
      autoplay: true,
      hardenFrame: hardenFrame,
    );
  }
}

/// The guardian side's [KidPlayer] (curation screens): the same
/// embed and the same navigation rules with [adultPlayerParams], and the
/// video cued, not started: the curator presses play. A link out of the
/// embed still arrives as [PlayerLeaving] and another video as
/// [PlayerStrayed]; the screen decides (`followAdultPlayer`).
class YouTubeAdultPlayer implements KidPlayer {
  @override
  KidPlayback open(String youtubeId) {
    final origin = appOrigin();
    return _YouTubePlayback(
      youtubeId,
      origin: origin,
      params: adultPlayerParams(origin: origin),
      autoplay: false,
    );
  }
}

class _YouTubePlayback implements KidPlayback {
  _YouTubePlayback(
    this.youtubeId, {
    required String? origin,
    required YoutubePlayerParams params,
    required this._autoplay,
    FrameHardener? hardenFrame,
  }) {
    _controller = YoutubePlayerController(params: params, key: youtubeId);
    // Only kid mode passes a hardener: the guardian side may follow links
    // out to YouTube. The frame is restricted before anything loads into
    // it; when that fails the player never loads and reports a failure.
    final safe = hardenFrame == null || hardenFrame(_controller);
    if (!kIsWeb) {
      final base = Uri.parse(origin ?? params.host);
      unawaited(
        _controller.webViewController.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              switch (decideNavigation(
                uri,
                mainFrame: request.isMainFrame,
                base: base,
              )) {
                case KidNavigation.allow:
                  return NavigationDecision.navigate;
                case KidNavigation.leave:
                  _events.add(PlayerLeaving(uri!));
                  return NavigationDecision.prevent;
                case KidNavigation.block:
                  return NavigationDecision.prevent;
              }
            },
          ),
        ),
      );
    }
    _values = _controller.stream.listen(_onValue);
    _loaded = safe;
    if (safe) {
      unawaited(_start(params));
    } else {
      _failed = true;
      // After the screen has subscribed to [events].
      scheduleMicrotask(() {
        if (!_events.isClosed) _events.add(const PlayerFailed());
      });
    }
  }

  final String youtubeId;
  final bool _autoplay;
  late final YoutubePlayerController _controller;
  late final StreamSubscription<YoutubePlayerValue> _values;
  final _events = StreamController<PlayerEvent>.broadcast();
  PlayerState _state = PlayerState.unknown;
  bool _failed = false;
  late final bool _loaded;

  Future<void> _start(YoutubePlayerParams params) async {
    await _controller.initWithParams(params: params);
    if (_autoplay) {
      await _controller.loadVideoById(videoId: youtubeId);
    } else {
      await _controller.cueVideoById(videoId: youtubeId);
    }
  }

  void _onValue(YoutubePlayerValue value) {
    if (_events.isClosed) return;
    if (value.error != YoutubeError.none && !_failed) {
      _failed = true;
      _events.add(const PlayerFailed());
      return;
    }
    final playing = value.metaData.videoId;
    if (playing.isNotEmpty && playing != youtubeId) {
      _events.add(const PlayerStrayed());
      return;
    }
    if (value.playerState == _state) return;
    _state = value.playerState;
    switch (value.playerState) {
      case PlayerState.playing:
        _events.add(const PlayerPlaying());
      case PlayerState.paused:
        _events.add(const PlayerPaused());
      case PlayerState.ended:
        _events.add(const PlayerEnded());
      case _:
        break;
    }
  }

  @override
  late final Widget view = WebViewWidget(
    controller: _controller.webViewController,
  );

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<void> play() => _controller.playVideo();

  @override
  Future<void> pause() => _controller.pauseVideo();

  @override
  Future<void> close() async {
    await _values.cancel();
    await _events.close();
    // A player that never loaded has nothing to stop, and would never
    // answer the stop command.
    if (_loaded) await _controller.stopVideo();
    await _controller.close();
  }
}
