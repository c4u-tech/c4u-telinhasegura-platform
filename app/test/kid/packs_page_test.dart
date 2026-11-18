import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart' show StateModule;
import 'package:telinha_segura/curation/curation.dart' show VideoTheme;
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/pack_player_screen.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/room_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/tap_guard.dart';
import 'package:telinha_segura/kid/theme_glyph.dart';
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import 'kid_mosaic_test.dart' show blocks, mosaic, sixThemes, video;
import 'pack_player_test.dart' show opened, packKid, withPack;
import 'theme_page_test.dart' show plays;

/// The day with three pacotinhos, the last longer than the time left.
final Map<String, Object?> threePacks = {
  ...withPack,
  'packs': [
    ...withPack['packs']! as List,
    {
      'id': 'k2',
      'title': 'Canções',
      'cover_video_id': 'v4',
      'videos': [video('v4'), video('v1')],
    },
    {
      'id': 'k3',
      'title': 'Histórias longas',
      'cover_video_id': 'v2',
      'videos': [video('v2'), video('v3')],
      'fits': false,
    },
  ],
};

/// Six themes and three pacotinhos, as a full day brings them.
final Map<String, Object?> sixThemesWithPacks = {
  ...sixThemes,
  'packs': [
    {
      'id': 'k1',
      'title': 'Bichos do mar',
      'cover_video_id': 'v2',
      'videos': [video('v1'), video('v2')],
    },
    {
      'id': 'k2',
      'title': 'Canções',
      'cover_video_id': 'v3',
      'videos': [video('v3'), video('v1')],
    },
    {
      'id': 'k3',
      'title': 'Histórias',
      'cover_video_id': 'v4',
      'videos': [video('v4'), video('v5')],
    },
  ],
};

Finder get door => find.byType(PacksDoor);
Finder get page => find.byType(RoomScreen);
Finder get packTiles =>
    find.descendant(of: page, matching: find.byType(PackTile));

/// The child home with [threePacks], then the pacotinhos' page.
Future<Harness> packsPage(
  WidgetTester tester, {
  Size? size,
  FutureOr<http.Response> Function(String videoId)? play,
}) async {
  final h = packKid(catalog: () => threePacks, play: play);
  await h.pump(tester, initial: '/crianca', size: size ?? const Size(390, 844));
  await tester.ensureVisible(door);
  await tester.pumpAndSettle();
  await tester.tap(door);
  await tester.pumpAndSettle();
  await tester.pump(TapGuard.window);
  return h;
}

void main() {
  for (final band in ['5-8', 'ate-4']) {
    testWidgets('with two pacotinhos or more ($band), a filled band the '
        'content\'s width opens on all of them, between the highlight and '
        'the blocks, in the one-tap pictures\' place, read "Pacotinhos"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await mosaic(
        tester,
        catalog: () => json(200, sixThemesWithPacks),
        band: band,
      );

      expect(door, findsOneWidget);
      final at = tester.getRect(door);
      final top = tester.getRect(find.byType(HighlightPicture));
      expect(at.left, top.left);
      expect(at.width, top.width);
      expect(at.height, greaterThanOrEqualTo(KidSizes.target));
      expect(at.top, greaterThan(top.bottom));
      expect(tester.getRect(blocks.first).top, greaterThan(at.bottom));
      // The pictures give way to it that day; the six worlds keep their
      // even grid.
      expect(find.byType(OneTapPicture), findsNothing);
      expect(blocks, findsNWidgets(6));
      expect(
        tester.getRect(blocks.at(1)).top,
        tester.getRect(blocks.first).top,
      );
      // Filled on the input tone, apart from the home and every world.
      final ground = tester
          .widget<Material>(
            find.descendant(of: door, matching: find.byType(Material)).first,
          )
          .color;
      expect(ground, Palette.kid.input);
      expect(ground, isNot(ColourWorlds.home.ground));
      for (final t in VideoTheme.values) {
        expect(ground, isNot(worldOf(t).ground), reason: t.name);
      }
      expect(
        find.descendant(of: door, matching: find.byType(PackGlyph)),
        findsOne,
      );
      // The next pacotinho's cover in front, another peeking behind.
      final covers = tester
          .widgetList<BlockCover>(
            find.descendant(of: door, matching: find.byType(BlockCover)),
          )
          .map((c) => c.videoId)
          .toList();
      expect(covers, unorderedEquals(['v3', 'v4']));
      expect(find.bySemanticsLabel('Pacotinhos'), findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Pacotinhos')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(h.location(tester), '/crianca');
      semantics.dispose();
    });
  }

  testWidgets('with one pacotinho, no door', (tester) async {
    final h = packKid();
    await h.pump(tester, initial: '/crianca');
    expect(door, findsNothing);
  });

  testWidgets('the door opens every pacotinho in the theme page\'s template, '
      'on the home\'s ground, the first large with the mascot on it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await packsPage(tester);

    expect(h.location(tester), Routes.kidPacks);
    expect(packTiles, findsNWidgets(3));
    expect(
      tester
          .widget<Scaffold>(
            find.descendant(of: page, matching: find.byType(Scaffold)),
          )
          .backgroundColor,
      ColourWorlds.home.ground,
    );
    final lead = tester.getRect(
      find.descendant(of: packTiles.first, matching: find.byType(VideoTile)),
    );
    expect(lead.width, 350);
    final figure = find.descendant(of: page, matching: find.byType(Tevi));
    expect(figure, findsOneWidget);
    expect(tester.widget<Tevi>(figure).night, isFalse);
    expect(
      find.descendant(of: packTiles.at(1), matching: find.byType(StateModule)),
      findsNWidgets(2),
    );
    expect(find.bySemanticsLabel('Canções, pacotinho de 2 vídeos'), findsOne);
    expect(
      find.bySemanticsLabel(
        'Histórias longas, pacotinho de 2 vídeos, '
        'não cabe hoje',
      ),
      findsOne,
    );
    expect(find.bySemanticsLabel(PlayerScreen.back), findsOne);
    expect(
      find.descendant(of: page, matching: find.byType(PackGlyph)),
      findsOne,
    );
    expect(
      tester.getSize(
        find.descendant(of: page, matching: find.byType(PackGlyph)),
      ),
      const Size.square(56),
    );
    expect(h.actions.where((a) => a == 'GET /v1/child/catalog'), hasLength(1));
    semantics.dispose();
  });

  testWidgets('a pacotinho opens as on the home, and its player comes back '
      'to the page', (tester) async {
    final h = await packsPage(tester);

    await tester.tap(packTiles.at(1));
    await tester.pumpAndSettle();
    expect(plays(h), ['v4']);
    expect(find.byType(PackPlayerScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(PlayerScreen.back).last);
    await tester.pumpAndSettle();
    expect(h.location(tester), Routes.kidPacks);
    expect(find.byType(RoomScreen), findsOneWidget);
  });

  testWidgets('leaving the page while a pacotinho opens says nothing when the '
      'play comes back, and asks for it once', (tester) async {
    final answer = Completer<http.Response>();
    final h = await packsPage(tester, play: (_) => answer.future);

    await tester.tap(packTiles.at(1));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');

    answer.complete(json(201, opened('v4')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(KidErrorNote), findsNothing);
    expect(plays(h), ['v4']);
    expect(h.actions.where((a) => a == 'GET /v1/child/catalog'), hasLength(1));
    expect(h.location(tester), '/crianca');
  });

  testWidgets('a pacotinho that does not fit asks for nothing and says why', (
    tester,
  ) async {
    final h = await packsPage(tester);

    await tester.ensureVisible(packTiles.at(2));
    await tester.pumpAndSettle();
    await tester.tap(packTiles.at(2));
    await tester.pumpAndSettle();
    expect(plays(h), isEmpty);
    expect(find.byType(KidErrorNote), findsOne);
    expect(find.text(PlayerScreen.packDoesNotFit), findsOne);
  });

  testWidgets('the back key returns to the home', (tester) async {
    final h = await packsPage(tester);
    await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');
    expect(find.byType(KidMosaic), findsOne);
  });

  testWidgets('opened cold, the page returns to the home', (tester) async {
    final h = packKid(catalog: () => threePacks);
    await h.pump(tester, initial: Routes.kidPacks);
    expect(h.location(tester), '/crianca');
  });
}
