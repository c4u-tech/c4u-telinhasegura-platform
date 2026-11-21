import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/pack_player_screen.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/profile_picker_screen.dart';
import 'package:telinha_segura/kid/room_screen.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'kid_exit_screen_test.dart' show submit;
import 'kid_home_screen_test.dart' show kidHome;
import 'kid_mosaic_test.dart' show mosaic, sixThemes;
import 'pack_player_test.dart' show inPack;
import 'packs_page_test.dart' show packsPage;
import 'player_screen_test.dart' show watching;
import 'profile_picker_screen_test.dart' show linkedExit;
import 'sleeping_home_test.dart' show sleepy;
import 'theme_page_test.dart' show room;

const name = 'Telinha Segura';

/// The strip is read as the app's name once, though no small mark is
/// drawn in it.
void expectNamedStrip(WidgetTester tester) {
  expect(find.bySemanticsLabel(name), findsOneWidget);
  expect(
    find.byWidgetPredicate((w) => w is Tevi && w.tier == TeviTier.simplified),
    findsNothing,
  );
}

void main() {
  for (final (what, layout) in [
    (
      'a lead',
      const KidLayout(lead: SizedBox.square(dimension: 48), child: SizedBox()),
    ),
    ('no mark', const KidLayout(mark: false, child: SizedBox())),
    (
      'content rising into it',
      const KidLayout(
        lead: SizedBox.square(dimension: 48),
        fullWidth: true,
        scrolls: false,
        rise: 20,
        child: SizedBox.expand(),
      ),
    ),
  ]) {
    testWidgets('with $what, the strip is still read as the app\'s name, '
        'drawing nothing', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(home: layout));
      expectNamedStrip(tester);
      semantics.dispose();
    });
  }

  group('every child screen\'s strip is read as the app\'s name', () {
    testWidgets('the home', (tester) async {
      final semantics = tester.ensureSemantics();
      await mosaic(tester, catalog: () => json(200, sixThemes));
      expect(find.byType(KidMosaic), findsOne);
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the home while it loads', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = Harness(
        signedIn: true,
        api: (req) async {
          if (req.url.path == '/v1/child/profile') {
            return json(200, profileJson);
          }
          if (req.url.path == '/v1/child/catalog') {
            await Completer<void>().future;
          }
          return http.Response('', 204);
        },
      )..kidMode = {'minor_id': 'm1'};
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(h.app(initial: '/crianca'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(MosaicLoading), findsOne);
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the home without videos', (tester) async {
      final semantics = tester.ensureSemantics();
      await kidHome(tester);
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the home when the videos did not load', (tester) async {
      final semantics = tester.ensureSemantics();
      await mosaic(tester, catalog: () => http.Response('', 500));
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the home asleep', (tester) async {
      final semantics = tester.ensureSemantics();
      await sleepy().pump(tester, initial: '/crianca');
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the home paused', (tester) async {
      final semantics = tester.ensureSemantics();
      await sleepy(catalog: () => problem(403, 'consent_required'))
          .pump(tester, initial: '/crianca');
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('a theme\'s page', (tester) async {
      final semantics = tester.ensureSemantics();
      await room(tester);
      expect(find.byType(RoomScreen), findsOne);
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the pacotinhos\' page', (tester) async {
      final semantics = tester.ensureSemantics();
      await packsPage(tester);
      expect(find.byType(RoomScreen), findsOne);
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the player', (tester) async {
      final semantics = tester.ensureSemantics();
      await watching(tester);
      expect(find.byType(PlayerScreen), findsOne);
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('a pacotinho\'s player', (tester) async {
      final semantics = tester.ensureSemantics();
      await inPack(tester);
      expect(find.byType(PackPlayerScreen), findsOne);
      expectNamedStrip(tester);
      semantics.dispose();
    });

    testWidgets('the choice of who watches', (tester) async {
      final semantics = tester.ensureSemantics();
      await linkedExit(tester);
      await submit(tester, '2580');
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePickerScreen), findsOne);
      expectNamedStrip(tester);
      semantics.dispose();
    });
  });
}
