import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart' show StateModule;
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/kid_catalog.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/sleeping_telinha.dart';
import 'package:telinha_segura/kid/tap_guard.dart';
import 'package:telinha_segura/kid/theme_glyph.dart';
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'shelf_picture.dart';

/// A 1 × 1 PNG: real image bytes, as `/v1/child/thumbs` answers.
final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg==',
);

Map<String, Object?> video(String id, [String? title]) => {
  'id': id,
  'title': title ?? 'Vídeo $id',
  'duration_seconds': 120,
};

/// Two themes: animals with three videos, music with one.
final twoShelves = {
  'themes': [
    {
      'theme': 'bichos',
      'videos': [video('v1', 'O cachorro e a bola'), video('v2'), video('v3')],
    },
    {
      'theme': 'musica',
      'videos': [video('v4')],
    },
  ],
};

/// Every theme, in the server's order: animals and stories with two
/// videos, the rest with one.
final sixThemes = {
  'themes': [
    {
      'theme': 'bichos',
      'videos': [video('v1', 'O cachorro e a bola'), video('v2')],
    },
    {
      'theme': 'musica',
      'videos': [video('v3', 'A canção do sapo')],
    },
    {
      'theme': 'historias',
      'videos': [video('v4', 'A lua dorminhoca'), video('v5')],
    },
    {
      'theme': 'aprender',
      'videos': [video('v6')],
    },
    {
      'theme': 'brincar',
      'videos': [video('v7')],
    },
    {
      'theme': 'natureza',
      'videos': [video('v8')],
    },
  ],
};

/// [sixThemes] with two pacotinhos, the first opening on `v2`'s cover.
final withPacks = {
  ...sixThemes,
  'packs': [
    {
      'id': 'k1',
      'title': 'Bichos do mar',
      'cover_video_id': 'v2',
      'videos': [video('v1'), video('v2'), video('v3')],
    },
    {
      'id': 'k2',
      'title': 'Canções',
      'cover_video_id': 'v3',
      'videos': [video('v3'), video('v1')],
    },
  ],
};

/// [sixThemes] with the first of [withPacks]' pacotinhos only: today's
/// day, led by its one pacotinho.
final Map<String, Object?> onePack = {
  ...sixThemes,
  'packs': [(withPacks['packs']! as List).first],
};

/// `/crianca` on a shared device whose catalogue answers [catalog] and
/// whose child is in [band]; a thumbnail answers [thumb] (the pixel by
/// default).
Future<Harness> mosaic(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? catalog,
  FutureOr<http.Response> Function(String id)? thumb,
  String band = '5-8',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h = Harness(
    signedIn: true,
    api: (req) {
      final path = req.url.path;
      if (path == '/v1/child/profile') {
        return json(200, {...profileJson, 'age_band': band});
      }
      if (path == '/v1/child/catalog') {
        return (catalog ?? () => json(200, twoShelves))();
      }
      if (path.startsWith('/v1/child/thumbs/')) {
        final id = path.split('/').last;
        return (thumb ?? (_) => http.Response.bytes(pixel, 200))(id);
      }
      return http.Response('', 204);
    },
  )..kidMode = {'minor_id': 'm1'};
  await h.pump(tester, initial: '/crianca', size: size, textScale: textScale);
  return h;
}

Finder get highlight => find.byType(HighlightPicture);
Finder get pictures => find.byType(OneTapPicture);
Finder get blocks => find.byType(ThemeBlock);

Finder blockOf(VideoTheme theme) =>
    find.byWidgetPredicate((w) => w is ThemeBlock && w.shelf.theme == theme);

String plays(Harness h) =>
    h.actions.where((a) => a.startsWith('POST /v1/child/plays')).join(',');

/// How far the home scrolls: zero when everything is on the screen.
double scrollExtent(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(KidMosaic),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .maxScrollExtent;

void main() {
  group('the plan', () {
    KidCatalog read(Map<String, Object?> j) =>
        KidCatalog.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>);

    test('without a pacotinho, the first video of the first theme leads, '
        'then the first videos of the next two themes, then one block per '
        'theme in the catalogue\'s order', () {
      final plan = MosaicPlan.of(read(sixThemes), band: AgeBand.from5To8);
      expect(plan.pack, isNull);
      expect(plan.video?.id, 'v1');
      expect(plan.pictures.map((v) => v.id), ['v3', 'v4']);
      expect(plan.blocks.map((s) => s.theme), [
        VideoTheme.bichos,
        VideoTheme.musica,
        VideoTheme.historias,
        VideoTheme.aprender,
        VideoTheme.brincar,
        VideoTheme.natureza,
      ]);
    });

    test('the first pacotinho leads; the pictures are the first videos of '
        'the themes from the first, never its cover', () {
      final plan = MosaicPlan.of(read(withPacks), band: AgeBand.from5To8);
      expect(plan.pack?.id, 'k1');
      expect(plan.video, isNull);
      expect(plan.pictures.map((v) => v.id), ['v1', 'v3']);
      final coverFirst = read({
        ...withPacks,
        'packs': [
          {
            ...(withPacks['packs']! as List).first as Map,
            'cover_video_id': 'v1',
          },
        ],
      });
      expect(
        MosaicPlan.of(
          coverFirst,
          band: AgeBand.from5To8,
        ).pictures.map((v) => v.id),
        ['v3', 'v4'],
      );
    });

    test('up to 4, no pictures: the blocks grow instead; every other band, '
        'and an unknown one, has two', () {
      expect(
        MosaicPlan.of(read(sixThemes), band: AgeBand.upTo4).pictures,
        isEmpty,
      );
      for (final band in [
        AgeBand.from5To8,
        AgeBand.from9To12,
        AgeBand.unknown,
      ]) {
        expect(
          MosaicPlan.of(read(sixThemes), band: band).pictures,
          hasLength(2),
          reason: '$band',
        );
      }
    });

    test('a theme with no videos has no block and gives no picture; the '
        'pictures stop at two', () {
      final plan = MosaicPlan.of(
        read({
          'themes': [
            {'theme': 'bichos', 'videos': <Object>[]},
            {
              'theme': 'musica',
              'videos': [video('m1')],
            },
            {'theme': 'historias', 'videos': <Object>[]},
            {
              'theme': 'aprender',
              'videos': [video('a1')],
            },
            {
              'theme': 'brincar',
              'videos': [video('b1')],
            },
            {
              'theme': 'natureza',
              'videos': [video('n1')],
            },
          ],
        }),
        band: AgeBand.from5To8,
      );
      expect(plan.video?.id, 'm1');
      expect(plan.pictures.map((v) => v.id), ['a1', 'b1']);
      expect(plan.blocks.map((s) => s.theme), [
        VideoTheme.musica,
        VideoTheme.aprender,
        VideoTheme.brincar,
        VideoTheme.natureza,
      ]);
    });
  });

  testWidgets('the home shows, in order, the highlight, two pictures and one '
      'block per theme; no shelf rows remain', (tester) async {
    final h = await mosaic(tester, catalog: () => json(200, sixThemes));

    expect(h.actions, contains('GET /v1/child/catalog'));
    expect(highlight, findsOneWidget);
    expect(pictures, findsNWidgets(2));
    expect(blocks, findsNWidgets(6));
    expect(tester.widgetList<ThemeBlock>(blocks).map((b) => b.shelf.theme), [
      VideoTheme.bichos,
      VideoTheme.musica,
      VideoTheme.historias,
      VideoTheme.aprender,
      VideoTheme.brincar,
      VideoTheme.natureza,
    ]);
    final top = tester.getRect(highlight);
    final picture = tester.getRect(pictures.first);
    expect(picture.top, greaterThan(top.bottom));
    expect(tester.getRect(blocks.first).top, greaterThan(picture.bottom));
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('at 390 × 844 the highlight is 350 × 197 at corner 40, the '
      'pictures 169 × 95, the blocks 169 wide in two columns 12 apart', (
    tester,
  ) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));

    final top = tester.getRect(highlight);
    expect(top.size.width, 350);
    expect(top.size.height, closeTo(350 * 9 / 16, 0.01));
    expect(top.left, 20);
    final tile = tester.widget<VideoTile>(
      find.descendant(of: highlight, matching: find.byType(VideoTile)),
    );
    expect(tile.radius, FieldSizes.heroCorner);
    for (final p in [pictures.first, pictures.at(1)]) {
      expect(tester.getSize(p).width, 169);
      expect(tester.getSize(p).height, closeTo(169 * 9 / 16, 0.01));
    }
    expect(
      tester.getRect(pictures.at(1)).left -
          tester.getRect(pictures.first).right,
      12,
    );
    final first = tester.getRect(blocks.first);
    final second = tester.getRect(blocks.at(1));
    expect(first.width, 169);
    expect(second.left - first.right, 12);
    expect(second.top, first.top);
    expect(tester.getRect(blocks.at(2)).top - first.bottom, 12);
    expect(first.height, greaterThanOrEqualTo(KidSizes.target));
  });

  testWidgets('the mascot stands on the highlight\'s top edge, crest up, in '
      'its day colours on ink; the sun play disc sits in its bottom end '
      'corner, 64 across', (tester) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));

    final top = tester.getRect(highlight);
    final figure = find.descendant(
      of: find.byType(KidMosaic),
      matching: find.byType(Tevi),
    );
    expect(figure, findsOneWidget);
    final tevi = tester.widget<Tevi>(figure);
    expect((tevi.look, tevi.night, tevi.size), (TeviLook.crestUp, false, 104));
    final at = tester.getRect(figure);
    expect(
      at.top + at.height * TeviPainter.perchY,
      closeTo(top.top + TeviPainter.perchOverlap, 1e-6),
    );
    final body = at.left + at.width * TeviPainter.body.center.dx;
    expect(body, closeTo(top.center.dx, 1e-6));
    // Its head rises into the strip, between the avatar and the exit.
    final crest = at.top + at.height * TeviPainter.top;
    expect(crest, lessThan(KidLayout.stripHeight));
    expect(crest, greaterThan(0));
    expect(at.overlaps(tester.getRect(find.byType(HoldToExit))), isFalse);

    final disc = find.descendant(
      of: highlight,
      matching: find.byType(PlayDisc),
    );
    expect(disc, findsOneWidget);
    final d = tester.getRect(disc);
    expect(d.width, closeTo(64, 1e-9));
    expect(d.right, lessThan(top.right));
    expect(d.bottom, lessThan(top.bottom));
    expect(d.center.dx, greaterThan(top.center.dx));
    expect(d.center.dy, greaterThan(top.center.dy));
  });

  testWidgets('the one-tap pictures carry a smaller play disc', (tester) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));
    final disc = find.descendant(
      of: pictures.first,
      matching: find.byType(PlayDisc),
    );
    expect(disc, findsOneWidget);
    expect(tester.getSize(disc).width, lessThan(64));
    expect(
      find.descendant(of: blocks.first, matching: find.byType(PlayDisc)),
      findsNothing,
    );
  });

  testWidgets('a tap on the highlight or a picture plays it, as a tile did', (
    tester,
  ) async {
    final h = await mosaic(tester, catalog: () => json(200, sixThemes));

    await tester.tap(highlight);
    await tester.pumpAndSettle();
    expect(plays(h), 'POST /v1/child/plays {"video_id":"v1"}');
  });

  testWidgets('a tap on a picture plays its video', (tester) async {
    final h = await mosaic(tester, catalog: () => json(200, sixThemes));

    await tester.tap(pictures.at(1));
    await tester.pumpAndSettle();
    expect(plays(h), 'POST /v1/child/plays {"video_id":"v4"}');
  });

  testWidgets('the highlight, the pictures and the blocks are each one '
      'button, read by the title, or by the theme\'s name', (tester) async {
    final semantics = tester.ensureSemantics();
    await mosaic(tester, catalog: () => json(200, sixThemes));

    SemanticsData node(Finder f) => tester.getSemantics(f).getSemanticsData();
    expect(node(highlight).label, 'O cachorro e a bola');
    expect(node(pictures.first).label, 'A canção do sapo');
    expect(node(pictures.at(1)).label, 'A lua dorminhoca');
    for (final (i, name) in [
      'Bichos',
      'Música',
      'Histórias',
      'Aprender',
      'Brincar',
      'Natureza',
    ].indexed) {
      final data = node(blocks.at(i));
      expect(data.label, name);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
    }
    for (final f in [highlight, pictures.first]) {
      expect(node(f).hasAction(SemanticsAction.tap), isTrue);
      expect(node(f).flagsCollection.isButton, isTrue);
    }
    semantics.dispose();
  });

  testWidgets('every target on the home is at least 64 dp', (tester) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));
    for (final f in [highlight, pictures.first, pictures.at(1), blocks]) {
      for (final e in f.evaluate()) {
        final size = e.size!;
        expect(size.shortestSide, greaterThanOrEqualTo(KidSizes.target));
      }
    }
  });

  testWidgets('a block stands on its theme\'s colour world, with the glyph '
      'at its top start in the world\'s figure, its first video\'s cover '
      'large and the second peeking behind it', (tester) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));

    for (final theme in VideoTheme.values.take(6)) {
      final block = blockOf(theme);
      final world = worldOf(theme);
      expect(tester.widget<ThemeBlock>(block).world, world);
      final glyph = find.descendant(
        of: block,
        matching: find.byType(ThemeGlyph),
      );
      expect(tester.widget<ThemeGlyph>(glyph).theme, theme);
      expect(tester.widget<ThemeGlyph>(glyph).color, world.figure);
      final box = tester.getRect(block);
      final g = tester.getRect(glyph);
      expect(g.left - box.left, lessThan(box.width / 4));
      expect(g.top - box.top, lessThan(box.height / 4));
      final covers = tester
          .widgetList<BlockCover>(
            find.descendant(of: block, matching: find.byType(BlockCover)),
          )
          .toList();
      final shelf = tester.widget<ThemeBlock>(block).shelf;
      expect(covers.map((c) => c.videoId), [
        if (shelf.videos.length > 1) shelf.videos[1].id,
        shelf.videos.first.id,
      ]);
    }
    expect(worldOf(VideoTheme.bichos), ColourWorlds.bichos);
    expect(worldOf(VideoTheme.musica), ColourWorlds.musica);
    expect(worldOf(VideoTheme.historias), ColourWorlds.historias);
    expect(worldOf(VideoTheme.aprender), ColourWorlds.aprender);
    expect(worldOf(VideoTheme.brincar), ColourWorlds.brincar);
    expect(worldOf(VideoTheme.natureza), ColourWorlds.natureza);

    // The front cover is the larger, and the one behind shows above it.
    final animals = blockOf(VideoTheme.bichos);
    final behind = tester.getRect(
      find.descendant(of: animals, matching: find.byType(BlockCover)).first,
    );
    final front = tester.getRect(
      find.descendant(of: animals, matching: find.byType(BlockCover)).last,
    );
    expect(front.width, greaterThan(behind.width));
    expect(behind.top, lessThan(front.top));
    expect(front.width, greaterThan(tester.getSize(animals).width / 2));
  });

  testWidgets('a block\'s glyph is painted in its world\'s figure on its '
      'ground', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ThemeGlyph(VideoTheme.musica, color: BrandColors.dark),
        ),
      ),
    );
    expect(find.byType(ThemeGlyph), paints..rrect(color: BrandColors.dark));
  });

  testWidgets('a quiet read that brings other videos redraws every picture '
      'in its slot: the highlight, the pictures and the covers', (
    tester,
  ) async {
    KidCatalog read(Map<String, Object?> j) =>
        KidCatalog.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>);
    // The same day, every video replaced by another.
    final renamed = jsonDecode(
      jsonEncode(sixThemes)
          .replaceAllMapped(RegExp(r'"id":"v(\d)"'), (m) => '"id":"w${m[1]}"'),
    ) as Map<String, Object?>;
    final asked = <String>[];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget day(KidCatalog catalog) => MaterialApp(
      theme: buildTheme(Brightness.dark, Palette.kid),
      home: KidLayout(
        fullWidth: true,
        scrolls: false,
        rise: KidMosaic.rise,
        child: KidMosaic(
          catalog: catalog,
          band: AgeBand.from5To8,
          thumbnail: (id) async {
            asked.add(id);
            return pixel;
          },
          onPlay: (_) {},
          onOpenPack: (_) {},
          onOpenTheme: (_, _) {},
        ),
      ),
    );
    await tester.pumpWidget(day(read(sixThemes)));
    await tester.pumpAndSettle();
    expect(asked, isNotEmpty);
    expect(asked.every((id) => id.startsWith('v')), isTrue);

    await tester.pumpWidget(day(read(renamed)));
    await tester.pumpAndSettle();
    final shown = {
      for (final p in tester.widgetList<ThumbnailPicture>(
        find.byType(ThumbnailPicture),
      ))
        p.videoId,
    };
    expect(shown.every((id) => id.startsWith('w')), isTrue);
    expect(asked, containsAll(shown));
  });

  testWidgets('a tap on a block opens its theme from where the block '
      'stands, through the home\'s one seam for it', (tester) async {
    final opened = <(VideoTheme, Rect)>[];
    final catalog = KidCatalog.fromJson(
      jsonDecode(jsonEncode(sixThemes)) as Map<String, dynamic>,
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, Palette.kid),
        home: KidLayout(
          fullWidth: true,
          scrolls: false,
          rise: KidMosaic.rise,
          child: KidMosaic(
            catalog: catalog,
            band: AgeBand.from5To8,
            thumbnail: (_) async => pixel,
            onPlay: (_) {},
            onOpenPack: (_) {},
            onOpenTheme: (theme, from) => opened.add((theme, from)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(blockOf(VideoTheme.historias));
    await tester.tap(blockOf(VideoTheme.natureza));
    expect(opened, [
      (VideoTheme.historias, tester.getRect(blockOf(VideoTheme.historias))),
      (VideoTheme.natureza, tester.getRect(blockOf(VideoTheme.natureza))),
    ]);
  });

  testWidgets('a tap on a block plays nothing and opens the theme\'s page', (
    tester,
  ) async {
    final h = await mosaic(tester, catalog: () => json(200, sixThemes));
    await tester.tap(blocks.first);
    await tester.pumpAndSettle();
    expect(plays(h), isEmpty);
    expect(h.location(tester), '/crianca/tema/bichos');
  });

  group('a pacotinho leads', () {
    testWidgets('its cover, its modules beneath it, read by its title and '
        'count; the others wait behind their own door', (tester) async {
      final h = await mosaic(tester, catalog: () => json(200, withPacks));

      final pack = find.descendant(
        of: highlight,
        matching: find.byType(PackTile),
      );
      expect(pack, findsOneWidget);
      expect(tester.widget<PackTile>(pack).pack.id, 'k1');
      expect(find.byType(PackTile), findsOneWidget);
      expect(h.actions, contains('GET /v1/child/thumbs/v2'));
      final modules = tester
          .widgetList<StateModule>(
            find.descendant(of: pack, matching: find.byType(StateModule)),
          )
          .toList();
      expect(modules, hasLength(3));
      expect(modules.every((m) => !m.filled), isTrue);
      final cover = tester.getRect(
        find.descendant(of: pack, matching: find.byType(VideoTile)),
      );
      expect(cover.width, 350);
      expect(
        tester.getRect(find.byType(StateModule).first).top,
        greaterThan(cover.bottom),
      );
      expect(
        tester.getSemantics(pack).label,
        'Bichos do mar, pacotinho de 3 vídeos',
      );
      expect(
        PackTile.label(tester.widget<PackTile>(pack).pack),
        'Bichos do mar, pacotinho de 3 vídeos',
      );
      expect(
        find.descendant(of: pack, matching: find.byType(PlayDisc)),
        findsOneWidget,
      );
    });

    testWidgets('a tap opens it on its first video', (tester) async {
      final h = await mosaic(tester, catalog: () => json(200, withPacks));
      await tester.tap(highlight);
      await tester.pumpAndSettle();
      // This server refuses every play, so the pacotinho tries each in
      // turn, from its first.
      expect(plays(h), startsWith('POST /v1/child/plays {"video_id":"v1"}'));
    });

    testWidgets('a cover that did not come shows the hollow screen and still '
        'opens', (tester) async {
      final h = await mosaic(
        tester,
        catalog: () => json(200, withPacks),
        thumb: (id) => id == 'v2'
            ? http.Response('', 404)
            : http.Response.bytes(pixel, 200),
      );
      expect(
        find.descendant(of: highlight, matching: find.byType(HollowThumbnail)),
        findsOneWidget,
      );
      await tester.tap(highlight);
      await tester.pump();
      expect(plays(h), contains('"video_id":"v1"'));
    });
  });

  testWidgets('a pacotinho\'s path is one id segment under '
      '/crianca/pacotinho, reachable where a video is', (tester) async {
    expect(Routes.pack('k1'), '/crianca/pacotinho/k1');
    expect(Routes.isPack('/crianca/pacotinho/k1'), isTrue);
    expect(Routes.isPack('/crianca/pacotinho'), isFalse);
    expect(Routes.isPack('/crianca/pacotinho/k1/x'), isFalse);
    expect(Routes.sharedKidMay('/crianca/pacotinho/k1'), isTrue);
    expect(Routes.linkedDeviceMay('/crianca/pacotinho/k1'), isTrue);
    expect(Routes.isKidSide('/crianca/pacotinho/k1'), isTrue);
  });

  testWidgets('the play disc is a mark, not an action: it wears the '
      'indicator\'s colours wherever those differ from the action\'s', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Center(child: PlayDisc()),
      ),
    );
    expect(Palette.light.indicator, isNot(Palette.light.action));
    expect(
      find.descendant(
        of: find.byType(PlayDisc),
        matching: find.byType(CustomPaint),
      ),
      paints
        ..circle(color: Palette.light.indicator)
        ..path(color: Palette.light.onIndicator),
    );
  });

  testWidgets('up to 4, no pictures, and the blocks grow', (tester) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));
    final older = tester.getSize(blocks.first);
    await tester.pumpWidget(const SizedBox());

    await mosaic(tester, catalog: () => json(200, sixThemes), band: 'ate-4');
    expect(pictures, findsNothing);
    expect(highlight, findsOneWidget);
    expect(blocks, findsNWidgets(6));
    final younger = tester.getSize(blocks.first);
    expect(younger.width, older.width);
    expect(younger.height, greaterThan(older.height));
  });

  for (final (band, catalog, name) in [
    ('5-8', sixThemes, ''),
    ('5-8', onePack, ', a pacotinho leading'),
    ('5-8', withPacks, ', the pacotinhos\' door among the blocks'),
    ('ate-4', sixThemes, ''),
    ('ate-4', onePack, ', a pacotinho leading'),
    ('ate-4', withPacks, ', the pacotinhos\' door among the blocks'),
  ]) {
    testWidgets('at 390 × 844 with six themes the home needs no scrolling '
        '($band$name)', (tester) async {
      await mosaic(tester, catalog: () => json(200, catalog), band: band);
      expect(scrollExtent(tester), 0);
      expect(tester.getRect(blocks.last).bottom, lessThanOrEqualTo(844));
    });
  }

  for (final (catalog, name) in [
    (sixThemes, ''),
    (onePack, ', a pacotinho leading'),
  ]) {
    testWidgets('on a 390 × 844 phone with its insets (47 at the top, 34 at '
        'the foot) six themes still need no scrolling$name', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      await mosaic(tester, catalog: () => json(200, catalog));
      expect(scrollExtent(tester), 0);
      expect(tester.getRect(blocks.last).bottom, lessThanOrEqualTo(844 - 34));
    });
  }

  testWidgets('from 840 px the highlight and the pictures stand at the start, '
      'the blocks in two columns at the end, with no scrolling', (
    tester,
  ) async {
    await mosaic(
      tester,
      catalog: () => json(200, onePack),
      size: const Size(1280, 800),
    );
    final top = tester.getRect(highlight);
    final first = tester.getRect(blocks.first);
    final second = tester.getRect(blocks.at(1));
    expect(top.left, closeTo(48, 1e-6));
    expect(first.left, greaterThan(top.right));
    expect(second.left, greaterThan(first.right));
    expect(second.top, first.top);
    expect(second.right, closeTo(1280 - 48, 1e-6));
    expect(tester.getRect(pictures.first).top, greaterThan(top.bottom));
    expect(tester.getRect(pictures.first).right, lessThan(first.left));
    expect(scrollExtent(tester), 0);
    final tevi = tester.widget<Tevi>(
      find.descendant(of: find.byType(KidMosaic), matching: find.byType(Tevi)),
    );
    expect(tevi.size, 128);
  });

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('at 200% text at ${size.width.toInt()} × '
        '${size.height.toInt()} the home holds, the exit stays reachable and '
        'the last block can be scrolled to', (tester) async {
      await mosaic(
        tester,
        catalog: () => json(200, withPacks),
        size: size,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(HoldToExit).hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(
        blocks.last,
        200,
        scrollable: find
            .descendant(
              of: find.byType(KidMosaic),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(blocks.last.hitTestable(), findsOneWidget);
      expect(find.byType(HoldToExit).hitTestable(), findsOneWidget);
    });
  }

  testWidgets('the strip holds the child\'s avatar at the start, 48 dp, read '
      'by the nickname, and the exit at the end; no small mark', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mosaic(tester);

    final avatar = find.descendant(
      of: find.byType(KidHomeScreen),
      matching: find.byType(AvatarDisc),
    );
    expect(tester.getSize(avatar), const Size.square(KidMosaic.avatar));
    expect(KidMosaic.avatar, 48);
    final a = tester.getRect(avatar);
    final exit = tester.getRect(find.byType(HoldToExit));
    expect(a.left, Space.xl);
    expect(a.center.dy, exit.center.dy);
    expect(find.bySemanticsLabel('Lia'), findsOneWidget);
    // No mark drawn, though the strip still says the app's name.
    expect(
      find.byWidgetPredicate((w) => w is Tevi && w.tier == TeviTier.simplified),
      findsNothing,
    );
    expect(find.bySemanticsLabel(KidLayout.name), findsOne);
    semantics.dispose();
  });

  testWidgets('a thumbnail shows the bytes from our API, and no image comes '
      'from anywhere else', (tester) async {
    final h = await mosaic(tester);

    expect(h.actions, contains('GET /v1/child/thumbs/v1'));
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.image, isA<MemoryImage>());
    }
    expect((images.first.image as MemoryImage).bytes, pixel);
  });

  testWidgets('a failed thumbnail shows a hollow screen and stays a target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await mosaic(
      tester,
      catalog: () => json(200, sixThemes),
      thumb: (id) => id == 'v1'
          ? problem(503, 'thumbnail_unavailable')
          : http.Response.bytes(pixel, 200),
    );

    expect(
      find.descendant(of: highlight, matching: find.byType(HollowThumbnail)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: highlight, matching: find.byType(Image)),
      findsNothing,
    );
    final node = tester.getSemantics(highlight);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    // The animals' block shows the same hollow screen for its cover.
    expect(
      find.descendant(
        of: blockOf(VideoTheme.bichos),
        matching: find.byType(HollowThumbnail),
      ),
      findsOneWidget,
    );
    await tester.tap(highlight);
    await tester.pump();
    expect(plays(h), contains('"video_id":"v1"'));
    semantics.dispose();
  });

  testWidgets('no YouTube logo anywhere on the home', (tester) async {
    final semantics = tester.ensureSemantics();
    await mosaic(tester, catalog: () => json(200, sixThemes));
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.bySemanticsLabel('YouTube'), findsNothing);
    semantics.dispose();
  });

  testWidgets('while the catalogue loads, quiet fills hold the home\'s shapes '
      'with the mascot watching, read "Carregando vídeos"', (tester) async {
    final semantics = tester.ensureSemantics();
    final gate = Completer<http.Response>();
    final h = Harness(
      signedIn: true,
      api: (req) => switch (req.url.path) {
        '/v1/child/profile' => json(200, profileJson),
        '/v1/child/catalog' => gate.future,
        _ => http.Response('', 204),
      },
    )..kidMode = {'minor_id': 'm1'};
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.app(initial: '/crianca'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final loading = find.byType(MosaicLoading);
    expect(loading, findsOneWidget);
    expect(find.bySemanticsLabel(MosaicLoading.label), findsOneWidget);
    expect(MosaicLoading.label, 'Carregando vídeos');
    final tevi = tester.widget<Tevi>(
      find.descendant(of: loading, matching: find.byType(Tevi)),
    );
    expect((tevi.look, tevi.night), (TeviLook.watching, false));
    expect(
      find.descendant(of: loading, matching: find.byType(Image)),
      findsNothing,
    );
    expect(find.byType(EmptyShelf), findsNothing);
    expect(find.bySemanticsLabel('Lia'), findsOneWidget);

    gate.complete(json(200, twoShelves));
    await tester.pumpAndSettle();
    expect(loading, findsNothing);
    expect(blocks, findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('a catalogue with no videos keeps the empty shelf, the mascot '
      'on the hollow frame, the avatar in the strip', (tester) async {
    final semantics = tester.ensureSemantics();
    await mosaic(tester, catalog: () => json(200, {'themes': []}));

    expect(find.byType(KidMosaic), findsNothing);
    expectPerched(tester, find.byType(EmptyShelf), TeviLook.watching);
    expect(find.text(EmptyShelf.line), findsOneWidget);
    final avatar = find.descendant(
      of: find.byType(KidHomeScreen),
      matching: find.byType(AvatarDisc),
    );
    expect(tester.getSize(avatar), const Size.square(KidMosaic.avatar));
    expect(find.bySemanticsLabel('Lia'), findsOneWidget);
    // No mark drawn, though the strip still says the app's name.
    expect(
      find.byWidgetPredicate((w) => w is Tevi && w.tier == TeviTier.simplified),
      findsNothing,
    );
    expect(find.bySemanticsLabel(KidLayout.name), findsOne);
    expect(find.byType(SvgPicture), findsNothing);
    semantics.dispose();
  });

  testWidgets('a failed catalogue shows its picture and one "Tentar de '
      'novo" that fetches again', (tester) async {
    var fail = true;
    final h = await mosaic(
      tester,
      catalog: () => fail ? problem(503, 'internal') : json(200, twoShelves),
    );

    expect(find.byType(ShelvesFailed), findsOneWidget);
    expectPerched(tester, find.byType(ShelvesFailed), TeviLook.crestUp);
    expect(find.text(ShelvesFailed.line), findsOneWidget);
    final retry = find.widgetWithText(FilledButton, ShelvesFailed.retry);
    expect(ShelvesFailed.retry, 'Tentar de novo');
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(KidSizes.target));
    // No mark drawn, though the strip still says the app's name.
    expect(
      find.byWidgetPredicate((w) => w is Tevi && w.tier == TeviTier.simplified),
      findsNothing,
    );
    expect(find.bySemanticsLabel(KidLayout.name), findsOne);

    fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(h.actions.where((c) => c == 'GET /v1/child/catalog'), hasLength(2));
    expect(blocks, findsNWidgets(2));
  });

  testWidgets('a second tap on "Tentar de novo" never lands on a picture '
      'that just took its place', (tester) async {
    var fail = true;
    final h = await mosaic(
      tester,
      catalog: () => fail ? problem(503, 'internal') : json(200, twoShelves),
    );
    final retry = find.widgetWithText(FilledButton, ShelvesFailed.retry);
    final at = tester.getCenter(retry);

    fail = false;
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(highlight, findsOne);
    await tester.tapAt(at);
    await tester.tap(highlight, warnIfMissed: false);
    await tester.pump();
    expect(plays(h), isEmpty);

    await tester.pump(TapGuard.window);
    await tester.tap(highlight);
    await tester.pump();
    expect(plays(h), isNotEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('the sleeping home shows no mosaic', (tester) async {
    await mosaic(
      tester,
      catalog: () => json(200, {
        ...withPacks,
        'time': {'state': 'time_up', 'reason': 'daily'},
      }),
    );
    expect(find.byType(SleepingTelinha), findsOneWidget);
    expect(find.byType(KidMosaic), findsNothing);
  });

  testWidgets('the exit stays in the corner above the home', (tester) async {
    await mosaic(tester);
    expect(find.byType(HoldToExit), findsOneWidget);
  });
}
