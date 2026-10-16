import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart' show StateModule;
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/sleeping_telinha.dart';
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import 'kid_shelves_test.dart'
    show hollowEnd, pixel, shelves, twoShelves, video;
import 'pack_player_test.dart' show withPack;

/// Two pacotinhos: three videos, then two.
final Map<String, Object?> twoPacks = {
  ...twoShelves,
  'packs': [
    (withPack['packs']! as List).single,
    {
      'id': 'k2',
      'title': 'Canções',
      'cover_video_id': 'v4',
      'videos': [video('v4'), video('v1')],
    },
  ],
};

void main() {
  testWidgets('the pacotinhos row stands above the first theme shelf, led '
      'by its glyph, read "Pacotinhos" and not a target', (tester) async {
    await shelves(tester, catalog: () => json(200, twoPacks));

    final row = find.byType(PackRow);
    expect(row, findsOneWidget);
    expect(
      tester.getTopLeft(row).dy,
      lessThan(tester.getTopLeft(find.byType(Shelf).first).dy),
    );
    final glyph = find.descendant(of: row, matching: find.byType(PackGlyph));
    expect(glyph, findsOneWidget);
    final data = tester.getSemantics(glyph).getSemanticsData();
    expect(data.label, 'Pacotinhos');
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(tester.getSize(glyph), const Size.square(64));
  });

  testWidgets('with no pacotinhos the row is absent', (tester) async {
    await shelves(tester);
    expect(find.byType(PackRow), findsNothing);
    expect(find.byType(PackGlyph), findsNothing);
    expect(find.byType(Shelf), findsNWidgets(2));
  });

  testWidgets('one tile per pacotinho in order, its cover\'s picture with '
      'one hollow module per video, the row ending on its last tile', (
    tester,
  ) async {
    final h = await shelves(tester, catalog: () => json(200, twoPacks));

    final tiles = tester.widgetList<PackTile>(find.byType(PackTile)).toList();
    expect([for (final t in tiles) t.pack.id], ['k1', 'k2']);
    expect(h.actions, contains('GET /v1/child/thumbs/v2'));
    final first = find.byType(PackTile).first;
    final modules = tester
        .widgetList<StateModule>(
          find.descendant(of: first, matching: find.byType(StateModule)),
        )
        .toList();
    expect(modules, hasLength(3));
    expect(modules.every((m) => !m.filled), isTrue);
    // The row slides and ends on its last tile, with no hollow screen
    // (fullscreen design).
    final row = find.byType(PackRow);
    await tester.drag(row, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.descendant(of: row, matching: hollowEnd), findsNothing);
  });

  testWidgets('a tile is one target of at least 64 dp, read by its title and '
      'its count, nothing written on it', (tester) async {
    await shelves(tester, catalog: () => json(200, twoPacks));

    final tile = find.byType(PackTile).first;
    final data = tester.getSemantics(tile).getSemanticsData();
    expect(data.label, 'Bichos do mar, pacotinho de 3 vídeos');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    final picture = find.descendant(of: tile, matching: find.byType(VideoTile));
    expect(tester.getSize(picture), const Size(192, 108));
    expect(
      find.descendant(of: tile, matching: find.byType(Text)),
      findsNothing,
    );
  });

  testWidgets('from 840 px the tiles grow', (tester) async {
    await shelves(
      tester,
      catalog: () => json(200, twoPacks),
      size: const Size(1280, 800),
    );
    final picture = find.descendant(
      of: find.byType(PackTile).first,
      matching: find.byType(VideoTile),
    );
    expect(tester.getSize(picture), const Size(256, 144));
  });

  testWidgets('a cover that did not come shows the hollow screen and still '
      'plays', (tester) async {
    final h = await shelves(
      tester,
      catalog: () => json(200, twoPacks),
      thumb: (id) =>
          id == 'v2' ? http.Response('', 404) : http.Response.bytes(pixel, 200),
    );
    final tile = find.byType(PackTile).first;
    expect(
      find.descendant(of: tile, matching: find.byType(HollowThumbnail)),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pump();
    expect(h.actions, contains('POST /v1/child/plays {"video_id":"v1"}'));
  });

  testWidgets('the sleeping home shows no row', (tester) async {
    await shelves(
      tester,
      catalog: () => json(200, {
        ...twoPacks,
        'time': {'state': 'time_up', 'reason': 'daily'},
      }),
    );
    expect(find.byType(SleepingTelinha), findsOneWidget);
    expect(find.byType(PackRow), findsNothing);
  });

  testWidgets('the empty catalogue shows no row', (tester) async {
    await shelves(
      tester,
      catalog: () => json(200, {'themes': <Object>[], 'packs': <Object>[]}),
    );
    expect(find.byType(EmptyShelf), findsOneWidget);
    expect(find.byType(PackRow), findsNothing);
  });

  testWidgets('a failed catalogue shows no row', (tester) async {
    await shelves(tester, catalog: () => problem(500, 'internal'));
    expect(find.byType(ShelvesFailed), findsOneWidget);
    expect(find.byType(PackRow), findsNothing);
  });

  test('a pacotinho\'s path is one id segment under /crianca/pacotinho, '
      'reachable where a video is', () {
    expect(Routes.pack('k1'), '/crianca/pacotinho/k1');
    expect(Routes.isPack('/crianca/pacotinho/k1'), isTrue);
    expect(Routes.isPack('/crianca/pacotinho'), isFalse);
    expect(Routes.isPack('/crianca/pacotinho/k1/x'), isFalse);
    expect(Routes.sharedKidMay('/crianca/pacotinho/k1'), isTrue);
    expect(Routes.linkedDeviceMay('/crianca/pacotinho/k1'), isTrue);
    expect(Routes.isKidSide('/crianca/pacotinho/k1'), isTrue);
  });
}
