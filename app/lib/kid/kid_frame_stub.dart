import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Outside the web the player is a WebView whose navigation rules already
/// keep links inside; there is no frame to restrict.
bool hardenKidFrame(YoutubePlayerController controller) => true;
