import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/theme_glyph.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;

/// A 1 × 1 PNG: real image bytes, as `/v1/child/thumbs` answers.
final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg==',
);

Map<String, Object?> video(String id, [String? title]) => {
  'id': id,
  'title': title ?? 'Vídeo $id',
  'duration_seconds': 120,
};

/// Two shelves: animals with three videos, music with one.
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

/// `/crianca` on a shared device whose catalogue answers [catalog]; a
/// thumbnail answers [thumb] (the pixel by default).
Future<Harness> shelves(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? catalog,
  FutureOr<http.Response> Function(String id)? thumb,
  Size size = const Size(390, 844),
}) async {
  final h = Harness(
    signedIn: true,
    api: (req) {
      final path = req.url.path;
      if (path == '/v1/child/profile') return json(200, profileJson);
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
  await h.pump(tester, initial: '/crianca', size: size);
  return h;
}

Finder shelfOf(VideoTheme theme) =>
    find.byWidgetPredicate((w) => w is Shelf && w.shelf.theme == theme);

Finder tilesIn(Finder shelf) =>
    find.descendant(of: shelf, matching: find.byType(VideoTile));

/// The hollow screen the empty shelf draws, which no row's end repeats.
final hollowEnd = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is EmptyShelfPainter,
);

void main() {
  testWidgets('one shelf per theme in the catalogue\'s order, each led by '
      'its glyph, its videos in the order received', (tester) async {
    final h = await shelves(tester);

    expect(h.actions, contains('GET /v1/child/catalog'));
    final order = tester
        .widgetList<Shelf>(find.byType(Shelf))
        .map((s) => s.shelf.theme);
    expect(order, [VideoTheme.bichos, VideoTheme.musica]);
    final animals = shelfOf(VideoTheme.bichos);
    final glyph = find.descendant(
      of: animals,
      matching: find.byType(ThemeGlyph),
    );
    expect(tester.widget<ThemeGlyph>(glyph).theme, VideoTheme.bichos);
    expect(tester.getSize(glyph), const Size.square(KidSizes.target));
    expect(tester.widget<Shelf>(animals).shelf.videos.map((v) => v.id), [
      'v1',
      'v2',
      'v3',
    ]);
    // The row builds what is near the screen, in that order.
    final tiles = tilesIn(animals);
    expect(tester.widgetList<VideoTile>(tiles).map((t) => t.video.id), [
      'v1',
      'v2',
    ]);
    expect(
      tester.getRect(glyph).right,
      lessThanOrEqualTo(tester.getRect(tiles.first).left),
    );
  });

  testWidgets('a glyph reads as its theme and is not a target; a thumbnail '
      'reads as one button by its title', (tester) async {
    final semantics = tester.ensureSemantics();
    await shelves(tester);

    for (final (theme, name) in [
      (VideoTheme.bichos, 'Bichos'),
      (VideoTheme.musica, 'Música'),
    ]) {
      expect(themeName(theme), name);
      final node = tester.getSemantics(
        find.descendant(of: shelfOf(theme), matching: find.byType(ThemeGlyph)),
      );
      expect(node.label, name);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    }
    expect(
      [for (final t in VideoTheme.values.take(6)) themeName(t)],
      ['Bichos', 'Música', 'Histórias', 'Aprender', 'Brincar', 'Natureza'],
    );
    final tile = tester.getSemantics(tilesIn(shelfOf(VideoTheme.bichos)).first);
    expect(tile.label, 'O cachorro e a bola');
    expect(tile.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(tile.getSemanticsData().flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  testWidgets('a thumbnail shows the bytes from our API, and no image comes '
      'from anywhere else', (tester) async {
    final h = await shelves(tester);

    expect(h.actions, contains('GET /v1/child/thumbs/v1'));
    final images = tester.widgetList<Image>(
      find.descendant(
        of: shelfOf(VideoTheme.bichos),
        matching: find.byType(Image),
      ),
    );
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.image, isA<MemoryImage>());
    }
    expect((images.first.image as MemoryImage).bytes, pixel);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
      findsNothing,
    );
  });

  testWidgets('thumbnails are 16:9 at 160 × 90', (tester) async {
    await shelves(tester);
    expect(
      tester.getSize(tilesIn(shelfOf(VideoTheme.bichos)).first),
      VideoTile.narrow,
    );
    expect(VideoTile.narrow, const Size(160, 90));
  });

  testWidgets('from 840 px wide they grow to 224 × 126', (tester) async {
    await shelves(tester, size: const Size(1280, 800));
    expect(
      tester.getSize(tilesIn(shelfOf(VideoTheme.bichos)).first),
      VideoTile.wide,
    );
    expect(VideoTile.wide, const Size(224, 126));
  });

  testWidgets('every shelf ends on its last tile, with no hollow screen '
      'after it (fullscreen design)', (tester) async {
    await shelves(tester);

    for (final theme in [VideoTheme.musica, VideoTheme.bichos]) {
      expect(
        find.descendant(of: shelfOf(theme), matching: hollowEnd),
        findsNothing,
        reason: '$theme',
      );
    }
  });

  testWidgets('with shelves, the avatar is small above them, read by the '
      'nickname', (tester) async {
    final semantics = tester.ensureSemantics();
    await shelves(tester);

    final avatar = find.descendant(
      of: find.byType(KidHomeScreen),
      matching: find.byType(AvatarDisc),
    );
    expect(tester.getSize(avatar), const Size.square(KidShelves.avatar));
    expect(KidShelves.avatar, 56);
    expect(
      tester.getRect(avatar).bottom,
      lessThan(tester.getRect(find.byType(Shelf).first).top),
    );
    expect(find.bySemanticsLabel('Lia'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('no YouTube logo on the shelves, at their foot or anywhere '
      '(fullscreen design)', (tester) async {
    final semantics = tester.ensureSemantics();
    await shelves(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.bySemanticsLabel('YouTube'), findsNothing);
    semantics.dispose();
  });

  testWidgets('while the catalogue loads, quiet bars hold the shelves\' place '
      'and say what is loading', (tester) async {
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

    expect(find.byType(ShelvesLoading), findsOneWidget);
    expect(find.bySemanticsLabel(ShelvesLoading.label), findsOneWidget);
    expect(ShelvesLoading.label, 'Carregando vídeos');
    expect(find.byType(EmptyShelf), findsNothing);

    gate.complete(json(200, twoShelves));
    await tester.pumpAndSettle();
    expect(find.byType(ShelvesLoading), findsNothing);
    expect(find.byType(Shelf), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('a catalogue with no themes keeps the empty shelf', (
    tester,
  ) async {
    await shelves(tester, catalog: () => json(200, {'themes': []}));

    expect(find.byType(Shelf), findsNothing);
    expect(find.byType(EmptyShelf), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('a failed catalogue shows its picture and one "Tentar de '
      'novo" that fetches again', (tester) async {
    var fail = true;
    final h = await shelves(
      tester,
      catalog: () => fail ? problem(503, 'internal') : json(200, twoShelves),
    );

    expect(find.byType(ShelvesFailed), findsOneWidget);
    final retry = find.widgetWithText(FilledButton, ShelvesFailed.retry);
    expect(ShelvesFailed.retry, 'Tentar de novo');
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(KidSizes.target));

    fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(h.actions.where((c) => c == 'GET /v1/child/catalog'), hasLength(2));
    expect(find.byType(Shelf), findsNWidgets(2));
  });

  testWidgets('a failed thumbnail shows a hollow screen and stays a target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await shelves(
      tester,
      thumb: (id) => id == 'v2'
          ? problem(503, 'thumbnail_unavailable')
          : http.Response.bytes(pixel, 200),
    );

    final tile = tilesIn(shelfOf(VideoTheme.bichos)).at(1);
    expect(
      find.descendant(of: tile, matching: find.byType(HollowThumbnail)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.byType(Image)),
      findsNothing,
    );
    final node = tester.getSemantics(tile);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('a full shelf slides sideways and reaches its end', (
    tester,
  ) async {
    final full = {
      'themes': [
        {
          'theme': 'bichos',
          'videos': [for (var i = 1; i <= 12; i++) video('v$i')],
        },
      ],
    };
    await shelves(tester, catalog: () => json(200, full));

    final animals = shelfOf(VideoTheme.bichos);
    final last = find.byWidgetPredicate(
      (w) => w is VideoTile && w.video.id == 'v12',
    );
    final row = find.descendant(of: animals, matching: find.byType(Scrollable));
    await tester.dragUntilVisible(last, row, const Offset(-300, 0));
    await tester.drag(row, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(last).right, lessThanOrEqualTo(390 - Space.xl));
  });

  testWidgets('a mouse drags a shelf sideways too, as on the web', (
    tester,
  ) async {
    await shelves(tester);

    final row = find.descendant(
      of: shelfOf(VideoTheme.bichos),
      matching: find.byType(Scrollable),
    );
    final before = tester.getRect(tilesIn(shelfOf(VideoTheme.bichos)).first);
    await tester.dragFrom(
      tester.getCenter(row),
      const Offset(-120, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final after = tester.getRect(tilesIn(shelfOf(VideoTheme.bichos)).first);
    expect(after.left, lessThan(before.left));
  });

  testWidgets('the exit stays in the corner above the shelves', (tester) async {
    await shelves(tester);
    expect(find.byType(HoldToExit), findsOneWidget);
  });
}
