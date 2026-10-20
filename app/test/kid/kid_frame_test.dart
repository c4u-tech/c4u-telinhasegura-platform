import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/kid_frame.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/youtube_kid_player.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'fake_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the kid player\'s frame restrictions', () {
    test('scripts and the embed\'s own origin only', () {
      expect(kKidFrameSandbox, 'allow-scripts allow-same-origin');
    });

    test('no new windows and no taking over the page', () {
      final tokens = kKidFrameSandbox.split(' ');
      for (final token in tokens) {
        expect(token, isNot(startsWith('allow-popups')));
        expect(token, isNot(startsWith('allow-top-navigation')));
      }
    });
  });

  group('which player restricts its frame', () {
    late FakeWebViewPlatform platform;
    late List<int> pagesLoadedWhenRestricted;
    late bool restricts;

    bool fakeHardener(YoutubePlayerController controller) {
      final fake = controller.webViewController.platform;
      pagesLoadedWhenRestricted.add(
        (fake as FakeWebViewController).loadedHtml.length,
      );
      return restricts;
    }

    setUp(() {
      platform = FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      pagesLoadedWhenRestricted = [];
      restricts = true;
    });

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('kid mode restricts it before the player page loads', () async {
      YouTubeKidPlayer(hardenFrame: fakeHardener).open('yt1');
      await settle();

      expect(pagesLoadedWhenRestricted, [0]);
      expect(platform.controllers.single.loadedHtml, hasLength(1));
    });

    test('the guardian side leaves it alone', () async {
      YouTubeAdultPlayer().open('yt1');
      await settle();

      expect(pagesLoadedWhenRestricted, isEmpty);
      expect(platform.controllers.single.loadedHtml, hasLength(1));
    });

    test('when the frame cannot be restricted, kid mode reports a failure '
        'and never loads the player', () async {
      restricts = false;
      final playback = YouTubeKidPlayer(hardenFrame: fakeHardener).open('yt1');
      final events = <PlayerEvent>[];
      final sub = playback.events.listen(events.add);
      await settle();

      expect(events, [isA<PlayerFailed>()]);
      expect(platform.controllers.single.loadedHtml, isEmpty);
      await sub.cancel();
      await playback.close();
    });
  });
}
