import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/youtube_kid_player.dart';

void main() {
  group('the embed parameters', () {
    test('no YouTube controls, same-channel suggestions, no fullscreen, no '
        'keyboard, no annotations, inline, privacy-enhanced', () {
      final params = kidPlayerParams(origin: 'https://br.com.coding4u.app');
      final vars = params.toMap();

      expect(params.host, 'https://www.youtube-nocookie.com');
      expect(vars['controls'], 0);
      expect(vars['rel'], 0);
      expect(vars['fs'], 0);
      expect(vars['disablekb'], 1);
      expect(vars['iv_load_policy'], 3);
      expect(vars['playsinline'], 1);
    });

    test('the app identifies itself as the embed\'s origin and referrer', () {
      final vars = kidPlayerParams(origin: 'https://br.com.coding4u.app')
          .toMap();
      expect(vars['origin'], 'https://br.com.coding4u.app');
      expect(vars['widget_referrer'], 'https://br.com.coding4u.app');
    });
  });

  group('the guardian side\'s embed parameters', () {
    test('YouTube\'s own controls, fullscreen and keyboard, same-channel '
        'suggestions, no annotations, inline, privacy-enhanced', () {
      final params = adultPlayerParams(origin: 'https://br.com.coding4u.app');
      final vars = params.toMap();

      expect(params.host, 'https://www.youtube-nocookie.com');
      expect(vars['controls'], 1);
      expect(vars['fs'], 1);
      expect(vars['disablekb'], 0);
      expect(vars['rel'], 0);
      expect(vars['iv_load_policy'], 3);
      expect(vars['playsinline'], 1);
      // Captions stay the viewer's choice, from YouTube's own controls.
      expect(vars['cc_load_policy'], 0);
      expect(vars['cc_lang_pref'], 'pt');
      expect(vars['hl'], 'pt');
      expect(vars['origin'], 'https://br.com.coding4u.app');
      expect(vars['widget_referrer'], 'https://br.com.coding4u.app');
    });

    test('kid mode\'s parameters are not the adult ones', () {
      final kid = kidPlayerParams(origin: 'o').toMap();
      expect(kid['controls'], 0);
      expect(kid['fs'], 0);
      expect(kid['disablekb'], 1);
    });
  });

  group('what the player may load', () {
    final base = Uri.parse('https://br.com.coding4u.telinha_segura');
    KidNavigation decide(String url, {bool mainFrame = true}) =>
        decideNavigation(Uri.parse(url), mainFrame: mainFrame, base: base);

    test('its own page and the embed load', () {
      expect(decide('about:blank'), KidNavigation.allow);
      expect(
        decide('https://br.com.coding4u.telinha_segura/'),
        KidNavigation.allow,
      );
      expect(
        decide(
          'https://www.youtube-nocookie.com/embed/yt1?controls=0',
          mainFrame: false,
        ),
        KidNavigation.allow,
      );
      expect(decide('https://www.youtube.com/embed/yt1'), KidNavigation.allow);
    });

    test('a link out of the embed is handed over, never loaded: the logo, '
        'the title, a suggestion', () {
      for (final url in [
        'https://www.youtube.com/watch?v=yt1&feature=emb_logo',
        'https://www.youtube.com/watch?v=other&feature=emb_rel_end',
        'https://youtu.be/yt1',
        'https://www.youtube.com/channel/UC123',
      ]) {
        expect(decide(url), KidNavigation.leave, reason: url);
      }
    });

    test('anything else inside the player is dropped', () {
      expect(
        decide('https://ads.example.com/frame', mainFrame: false),
        KidNavigation.block,
      );
      expect(decide('intent://scan/#Intent;end'), KidNavigation.block);
      expect(decide('javascript:alert(1)'), KidNavigation.block);
      expect(
        decideNavigation(null, mainFrame: true, base: base),
        KidNavigation.block,
      );
    });

    test('a page on our own host other than the player\'s is not the '
        'player', () {
      expect(
        decide('https://br.com.coding4u.telinha_segura/other'),
        KidNavigation.leave,
      );
    });
  });
}
