import 'package:youtube_player_iframe/youtube_player_iframe.dart';

export 'kid_frame_sandbox.dart';
export 'kid_frame_stub.dart' if (dart.library.js_interop) 'kid_frame_web.dart';

/// Restricts what the frame behind [controller] may do before the player
/// page loads; false when it could not, and then the player must not play.
typedef FrameHardener = bool Function(YoutubePlayerController controller);
