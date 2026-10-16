import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/adult_player.dart';
import 'package:telinha_segura/kid/kid_player.dart';

import '../access/harness.dart';
import '../kid/fake_player.dart';

void main() {
  group('followAdultPlayer', () {
    late FakePlayback playback;
    late FakeLinks links;

    setUp(() {
      playback = FakePlayback('yt1');
      links = FakeLinks();
    });

    Future<AdultPlayerOutcome> follow(PlayerEvent event) =>
        followAdultPlayer(event, playback: playback, links: links);

    test('a link out of the embed opens in the browser, without the PIN, '
        'and the video stays', () async {
      final url = Uri.parse('https://www.youtube.com/watch?v=yt1');

      expect(await follow(PlayerLeaving(url)), AdultPlayerOutcome.playing);

      expect(links.opened, [url]);
      expect(playback.closed, isFalse);
    });

    test('another video playing in place stops the player', () async {
      expect(await follow(const PlayerStrayed()), AdultPlayerOutcome.stopped);

      expect(playback.closed, isTrue);
      expect(links.opened, isEmpty);
    });

    test('a failure lets the player go, for the error note in its '
        'place', () async {
      expect(await follow(const PlayerFailed()), AdultPlayerOutcome.failed);

      expect(playback.closed, isTrue);
    });

    test('playing, pausing and ending are YouTube\'s own business', () async {
      for (final event in const [
        PlayerPlaying(),
        PlayerPaused(),
        PlayerEnded(),
      ]) {
        expect(await follow(event), AdultPlayerOutcome.playing);
      }
      expect(playback.calls, isEmpty);
    });
  });

  test('the guardian side has its own player, beside the child\'s', () {
    final h = Harness();

    expect(h.services.adultPlayer, same(h.adultPlayer));
    expect(h.services.adultPlayer, isNot(same(h.services.player)));
  });
}
