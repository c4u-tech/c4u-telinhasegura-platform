import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart' show StateModule;
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
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import 'kid_mosaic_test.dart' show blocks, video;
import 'pack_player_test.dart' show packKid, withPack;
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

Finder get door => find.byType(PacksDoor);
Finder get page => find.byType(RoomScreen);
Finder get packTiles =>
    find.descendant(of: page, matching: find.byType(PackTile));

/// The child home with [threePacks], then the pacotinhos' page.
Future<Harness> packsPage(WidgetTester tester, {Size? size}) async {
  final h = packKid(catalog: () => threePacks);
  await h.pump(tester, initial: '/crianca', size: size ?? const Size(390, 844));
  await tester.ensureVisible(door);
  await tester.pumpAndSettle();
  await tester.tap(door);
  await tester.pumpAndSettle();
  await tester.pump(TapGuard.window);
  return h;
}

void main() {
  testWidgets('with two pacotinhos or more, the blocks open on a door to all '
      'of them, outlined on the home\'s ground, read "Pacotinhos"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = packKid(catalog: () => threePacks);
    await h.pump(tester, initial: '/crianca');

    expect(door, findsOneWidget);
    final at = tester.getRect(door);
    expect(at.width, tester.getSize(blocks.first).width);
    expect(at.height, closeTo(tester.getSize(blocks.first).height, 1e-6));
    expect(at.left, lessThan(tester.getRect(blocks.first).left));
    expect(at.top, tester.getRect(blocks.first).top);
    expect(
      find.descendant(of: door, matching: find.byType(PackGlyph)),
      findsOne,
    );
    expect(find.bySemanticsLabel('Pacotinhos'), findsOne);
    final sides = [
      for (final d in tester.widgetList<DecoratedBox>(
        find.descendant(of: door, matching: find.byType(DecoratedBox)),
      ))
        if (d.decoration case ShapeDecoration(
          shape: RoundedRectangleBorder(:final side),
        ))
          side.color,
    ];
    expect(sides, contains(BrandColors.cream));
    expect(
      tester
          .widget<Material>(
            find.descendant(of: door, matching: find.byType(Material)).first,
          )
          .color,
      anyOf(isNull, Colors.transparent),
    );
    semantics.dispose();
  });

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
