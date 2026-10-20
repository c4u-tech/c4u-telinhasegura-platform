@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/widgets.dart'
    show Directionality, HtmlElementView, TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/kid_frame.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/youtube_kid_player.dart';
import 'package:web/web.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:youtube_player_iframe_web/youtube_player_iframe_web.dart';
// The plugin registers its platform only in a real app; a test registers it
// by hand.
// ignore: implementation_imports
import 'package:youtube_player_iframe_web/src/web_youtube_player_iframe_platform.dart';

/// The iframe that holds the player page, as the web player builds it.
HTMLIFrameElement frameOf(PlatformWebViewController controller) {
  final params =
      controller.params as WebYoutubePlayerIframeControllerCreationParams;
  // ignore: invalid_use_of_visible_for_testing_member
  return params.ytiFrame.element;
}

HTMLIFrameElement frameOfPlayback(KidPlayback playback) =>
    frameOf((playback.view as WebViewWidget).platform.params.controller);

/// Closes [playback] without waiting: a frame that is never put on a real
/// page never loads YouTube, and stopping a player that never became ready
/// waits for it until the package gives up.
void closeLater(KidPlayback playback) => unawaited(playback.close());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    WebViewPlatform.instance = WebYoutubePlayerIframePlatform();
  });

  test('the web hardener sandboxes the player frame', () {
    final controller = YoutubePlayerController(params: kidPlayerParams());
    addTearDown(() => unawaited(controller.close()));

    expect(hardenKidFrame(controller), isTrue);
    expect(
      frameOf(controller.webViewController.platform).getAttribute('sandbox'),
      kKidFrameSandbox,
    );
  });

  testWidgets('the frame a kid playback puts on the screen is sandboxed '
      'before its page loads', (tester) async {
    final playback = YouTubeKidPlayer().open('yt1');
    addTearDown(() => closeLater(playback));

    // Before the player page arrives the restriction is already there.
    final frame = frameOfPlayback(playback);
    expect(frame.getAttribute('sandbox'), kKidFrameSandbox);
    expect(frame.getAttribute('srcdoc'), isNull);

    // What the player puts on the screen must show that same frame: the
    // web view is identified by the id of the element it displays.
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: playback.view),
    );
    final shown = tester.widget<HtmlElementView>(find.byType(HtmlElementView));
    expect(shown.viewType, frame.id);
  });

  test('the guardian side\'s frame is not sandboxed', () {
    final playback = YouTubeAdultPlayer().open('yt1');
    addTearDown(() => closeLater(playback));
    final frame = frameOfPlayback(playback);

    expect(frame.hasAttribute('sandbox'), isFalse);
  });
}
