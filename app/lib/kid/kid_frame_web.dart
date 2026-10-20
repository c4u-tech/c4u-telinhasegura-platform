import 'package:flutter/foundation.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:youtube_player_iframe_web/youtube_player_iframe_web.dart';

import 'kid_frame_sandbox.dart';

/// Sandboxes the iframe that holds the player page, so links out of the
/// YouTube embed (the logo, the title, the end screen) cannot open a tab or
/// leave the app: on the web there is no navigation hook to turn them into
/// the parents' gate. Must run before the player page is loaded into the
/// frame, since a sandbox only applies to documents loaded after it is set.
///
/// Returns false when the frame cannot be reached (the web player package
/// changed how it builds it). The caller then refuses to play: a player
/// that shows nothing is safe, one that plays with open links is not.
bool hardenKidFrame(YoutubePlayerController controller) {
  final params = controller.webViewController.platform.params;
  if (params is! WebYoutubePlayerIframeControllerCreationParams) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'the YouTube player frame could not be restricted; '
          'got ${params.runtimeType}',
        ),
        library: 'kid player',
      ),
    );
    return false;
  }
  // The package offers no other way to reach the frame it creates; the
  // browser test of this function fails if that access ever stops working.
  // ignore: invalid_use_of_visible_for_testing_member
  final frame = params.ytiFrame.element;
  frame.setAttribute('sandbox', kKidFrameSandbox);
  return frame.getAttribute('sandbox') == kKidFrameSandbox;
}
