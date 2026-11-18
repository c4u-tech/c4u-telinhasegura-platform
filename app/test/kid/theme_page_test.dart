import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/curation/curation.dart' show VideoTheme;
import 'package:telinha_segura/curation/kid_catalog.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/room_screen.dart';
import 'package:telinha_segura/kid/room_transition.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/tap_guard.dart';
import 'package:telinha_segura/kid/theme_glyph.dart';
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'kid_mosaic_test.dart' show blockOf, pixel, video;

/// [child] on the kid ground, as a child screen paints it.
Widget onKid(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.dark, Palette.kid),
  home: Scaffold(body: Center(child: child)),
);

const _video = KidVideo(id: 'v1', title: 'O cachorro', duration: Duration.zero);

void main() {
  group('on a theme\'s ground', () {
    testWidgets('the play disc carries a dark ring', (tester) async {
      await tester.pumpWidget(
        onKid(const PlayDisc(ring: ColourWorlds.discRing)),
      );
      expect(
        find.descendant(
          of: find.byType(PlayDisc),
          matching: find.byType(CustomPaint),
        ),
        paints
          ..circle(color: Palette.kid.indicator)
          ..circle(color: ColourWorlds.discRing, style: PaintingStyle.stroke)
          ..path(color: Palette.kid.onIndicator),
      );
    });

    testWidgets('a tile\'s disc wears the ring only where the world rings it', (
      tester,
    ) async {
      Future<PlayDisc> discOn(ColourWorld world) async {
        await tester.pumpWidget(
          onKid(
            VideoTile(
              video: _video,
              size: const Size(160, 90),
              thumbnail: (_) async => pixel,
              onTap: () {},
              playDisc: true,
              world: world,
            ),
          ),
        );
        return tester.widget<PlayDisc>(find.byType(PlayDisc));
      }

      expect((await discOn(ColourWorlds.bichos)).ring, ColourWorlds.discRing);
      expect((await discOn(ColourWorlds.aprender)).ring, isNull);
      expect((await discOn(ColourWorlds.natureza)).ring, isNull);
    });

    testWidgets('a resting tile sinks toward the world\'s ground and is '
        'outlined in its figure, which reads on it', (tester) async {
      await tester.pumpWidget(
        onKid(
          VideoTile(
            video: _video,
            size: const Size(160, 90),
            thumbnail: (_) async => pixel,
            onTap: () {},
            resting: true,
            world: ColourWorlds.bichos,
          ),
        ),
      );
      final quiet = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(VideoTile),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && (w.color.a - .38).abs() < .01,
          ),
        ),
      );
      expect(quiet.color.withValues(alpha: 1), ColourWorlds.bichos.ground);
      final sides = [
        for (final d in tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(VideoTile),
            matching: find.byType(DecoratedBox),
          ),
        ))
          if (d.decoration case ShapeDecoration(
            shape: RoundedRectangleBorder(:final side),
          ))
            side.color,
      ];
      expect(sides, contains(ColourWorlds.bichos.figure));
    });
  });

  group('a theme\'s page', () {
    testWidgets('a path is one theme under /crianca/tema, reachable where '
        'the home is', (tester) async {
      expect(Routes.theme(VideoTheme.bichos), '/crianca/tema/bichos');
      expect(Routes.isTheme('/crianca/tema/bichos'), isTrue);
      expect(Routes.isTheme('/crianca/tema'), isFalse);
      expect(Routes.isTheme('/crianca/tema/bichos/x'), isFalse);
      for (final path in ['/crianca/tema/bichos', Routes.kidPacks]) {
        expect(Routes.sharedKidMay(path), isTrue, reason: path);
        expect(Routes.linkedDeviceMay(path), isTrue, reason: path);
        expect(Routes.isKidSide(path), isTrue, reason: path);
      }
      expect(Routes.kidPacks, '/crianca/pacotinhos');
    });

    testWidgets('a tap on a block opens its page with every video of the '
        'theme from the catalogue already read, the first large, each read '
        'by its title', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await room(tester);

      expect(h.location(tester), '/crianca/tema/bichos');
      expect(reads(h), 1);
      expect(tiles, findsNWidgets(5));
      expect(tester.getSize(tiles.first).width, 350);
      for (final title in ['O cachorro', 'O gato', 'A tartaruga', 'O peixe']) {
        expect(find.bySemanticsLabel(title), findsOne, reason: title);
      }
      semantics.dispose();
    });

    testWidgets('the theme\'s world fills the screen: a back key of 64 dp at '
        'the top start, the glyph beside it, the exit at the top end', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await room(tester);

      final scaffold = tester.widget<Scaffold>(
        find.descendant(of: page, matching: find.byType(Scaffold)),
      );
      expect(scaffold.backgroundColor, ColourWorlds.bichos.ground);
      final back = tester.getRect(find.bySemanticsLabel(PlayerScreen.back));
      expect(back.width, greaterThanOrEqualTo(KidSizes.target));
      expect(back.height, greaterThanOrEqualTo(KidSizes.target));
      expect(back.top, lessThan(KidLayout.stripHeight / 2));
      expect(back.left, lessThan(Space.xl));
      final glyph = tester.getRect(find.bySemanticsLabel('Bichos'));
      expect(glyph.left, greaterThan(back.right));
      expect(glyph.center.dy, closeTo(back.center.dy, 1));
      final exit = tester.getRect(find.byType(HoldToExit));
      expect(exit.right, greaterThan(390 - Space.xl));
      expect(exit.center.dy, closeTo(back.center.dy, 1));
      final drawn = tester.widget<ThemeGlyph>(
        find.descendant(of: page, matching: find.byType(ThemeGlyph)),
      );
      expect(drawn.color, ColourWorlds.bichos.figure);
      semantics.dispose();
    });

    testWidgets('a tap plays as on the home, and when the player ends the '
        'page is where the child comes back to', (tester) async {
      final h = await room(tester);

      await tester.tap(tiles.at(1));
      await tester.pumpAndSettle();
      expect(plays(h), ['v2']);
      expect(find.byType(PlayerScreen), findsOneWidget);

      h.player.current!.emit(const PlayerEnded());
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca/tema/bichos');
      expect(find.byType(RoomScreen), findsOneWidget);
    });

    testWidgets('the player\'s back key also comes back to the page', (
      tester,
    ) async {
      final h = await room(tester);
      await tester.tap(tiles.first);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel(PlayerScreen.back).last);
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca/tema/bichos');
    });

    testWidgets('the back key returns to the home, and so does the system '
        'back', (tester) async {
      final h = await room(tester);
      await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');
      expect(find.byType(RoomScreen), findsNothing);

      await tester.pump(TapGuard.window);
      await tester.tap(blockOf(VideoTheme.bichos));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca/tema/bichos');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');
      expect(reads(h), 1);
    });

    testWidgets('a video that does not fit stays in place, quieted, read as '
        'not for today; its tap asks for nothing and says why', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await room(tester);

      final resting = tester.widget<VideoTile>(tiles.at(2));
      expect(resting.video.id, 'v3');
      expect(resting.resting, isTrue);
      expect(resting.world, ColourWorlds.bichos);
      expect(find.bySemanticsLabel('O pato, não cabe hoje'), findsOne);

      await tester.tap(tiles.at(2));
      await tester.pumpAndSettle();
      expect(plays(h), isEmpty);
      expect(h.location(tester), '/crianca/tema/bichos');
      final note = tester.widget<KidErrorNote>(find.byType(KidErrorNote));
      expect(note.asleep, isTrue);
      expect(find.text(PlayerScreen.doesNotFit), findsOne);
      semantics.dispose();
    });

    testWidgets('the note floats at the foot of the page in a dark card, '
        'over the pictures, which stay where they were', (tester) async {
      await room(tester);
      final before = [
        for (final t in tiles.evaluate())
          tester.getRect(find.byWidget(t.widget)),
      ];

      await tester.tap(tiles.at(2));
      await tester.pumpAndSettle();

      final after = [
        for (final t in tiles.evaluate())
          tester.getRect(find.byWidget(t.widget)),
      ];
      expect(after, before, reason: 'nothing pushed down');
      final card = find.byType(FloatingNote);
      expect(card, findsOne);
      expect(
        find.descendant(of: card, matching: find.byType(KidErrorNote)),
        findsOne,
      );
      final box = tester.getRect(card);
      expect(box.bottom, closeTo(844 - Space.md, .5));
      expect(box.left, Space.lg);
      expect(box.right, 390 - Space.lg);
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: card,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, BrandColors.dark);
      // The mascot and the line side by side, in the card's night.
      final note = find.byType(KidErrorNote);
      final picture = tester.getRect(
        find.descendant(of: note, matching: find.byType(Tevi)),
      );
      final line = tester.getRect(find.text(PlayerScreen.doesNotFit));
      expect(line.left, greaterThan(picture.right - 1));
      expect(
        tester
            .widget<Tevi>(
              find.descendant(of: note, matching: find.byType(Tevi)),
            )
            .night,
        isTrue,
      );
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('at 200% text at ${size.width.toInt()} px the note never '
          'reaches the back key, and the last picture scrolls clear of it', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await room(tester, catalog: () => many(12), size: size);
        // A resting video's note, from the shared day.
        final day = tester.widget<RoomScreen>(page).day!;
        day.note(PlayerScreen.doesNotFit);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byType(FloatingNote));
        final back = tester.getRect(find.byType(RoomBack));
        expect(card.top, greaterThan(back.bottom));
        expect(card.bottom, lessThanOrEqualTo(size.height));
        await tester.drag(
          find.descendant(of: page, matching: find.byType(Scrollable)).first,
          const Offset(0, -5000),
        );
        await tester.pumpAndSettle();
        final last = tester.getRect(tiles.last);
        expect(last.bottom, lessThanOrEqualTo(card.top));
      });
    }

    testWidgets('a refused play says so on the page, which stays while the '
        'catalogue is read again', (tester) async {
      final h = await room(
        tester,
        play: (_) => problem(403, 'video_not_allowed'),
      );

      await tester.tap(tiles.at(1));
      await tester.pumpAndSettle();
      expect(plays(h), ['v2']);
      expect(h.location(tester), '/crianca/tema/bichos');
      expect(find.byType(KidErrorNote), findsOne);
      expect(reads(h), 2);
    });

    testWidgets('leaving the page while a play is on its way says nothing '
        'when the play comes back, and asks for it once', (tester) async {
      final answer = Completer<http.Response>();
      final h = await room(tester, play: (_) => answer.future);

      await tester.tap(tiles.at(1));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');

      answer.complete(
        json(201, {
          'play_id': 'p-v2',
          'youtube_id': 'yt-v2',
          'remaining_seconds': 600,
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(KidErrorNote), findsNothing);
      expect(plays(h), ['v2']);
      expect(reads(h), 1);
      expect(h.location(tester), '/crianca');
    });

    testWidgets('a day that runs out on a play sends the child to the '
        'sleeping home', (tester) async {
      var asleep = false;
      final h = await room(
        tester,
        catalog: () => asleep
            ? {
                ...themed,
                'time': {'state': 'time_up', 'reason': 'daily'},
              }
            : themed,
        play: (_) {
          asleep = true;
          return problem(403, 'time_up');
        },
      );

      await tester.tap(tiles.at(1));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');
      expect(find.byType(RoomScreen), findsNothing);
      expect(find.byType(KidMosaic), findsNothing);
    });

    testWidgets('a day that runs out while the player plays ends on the '
        'sleeping home, not the page', (tester) async {
      var asleep = false;
      final h = await room(
        tester,
        catalog: () => asleep
            ? {
                ...themed,
                'time': {'state': 'time_up', 'reason': 'daily'},
              }
            : themed,
      );
      await tester.tap(tiles.first);
      await tester.pumpAndSettle();

      asleep = true;
      h.player.current!.emit(const PlayerEnded());
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');
      expect(find.byType(KidMosaic), findsNothing);
    });

    for (final (name, path) in [
      ('opened cold', '/crianca/tema/bichos'),
      ('of an unknown theme', '/crianca/tema/dinossauros'),
    ]) {
      testWidgets('a page $name returns to the home', (tester) async {
        final h = themedKid();
        await h.pump(tester, initial: '/crianca');
        GoRouter.of(tester.element(find.byType(KidHomeScreen))).go(path);
        await tester.pumpAndSettle();
        expect(h.location(tester), '/crianca');
        expect(find.byType(RoomScreen), findsNothing);
      });
    }

    testWidgets('a page whose theme has left the catalogue returns to the '
        'home', (tester) async {
      var gone = false;
      final h = await room(
        tester,
        catalog: () => gone
            ? {
                'themes': [(themed['themes']! as List)[1]],
              }
            : themed,
        play: (_) {
          gone = true;
          return problem(403, 'video_not_allowed');
        },
      );
      await tester.tap(tiles.at(1));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');
      // The home says why the video did not open.
      expect(find.byType(KidErrorNote), findsOne);
    });

    testWidgets('the first video wears the play disc, ringed on a light '
        'ground; the rest stand in two columns; the mascot does not stand '
        'on sun', (tester) async {
      await room(tester);

      final lead = tester.widget<VideoTile>(tiles.first);
      expect(lead.playDisc, isTrue);
      expect(lead.radius, FieldSizes.heroCorner);
      expect(
        tester.widget<PlayDisc>(find.byType(PlayDisc)).ring,
        ColourWorlds.discRing,
      );
      expect(tester.getRect(tiles.first).left, 20);
      expect(tester.getSize(tiles.at(1)), const Size(169, 169 * 9 / 16));
      expect(
        tester.getRect(tiles.at(2)).left - tester.getRect(tiles.at(1)).right,
        12,
      );
      expect(
        tester.getRect(tiles.at(1)).top - tester.getRect(tiles.first).bottom,
        12,
      );
      expect(
        find.descendant(of: page, matching: find.byType(Tevi)),
        findsNothing,
      );
    });

    testWidgets('on Noite the mascot stands on the first video in its night '
        'colours, and the disc has no ring', (tester) async {
      await room(tester, theme: VideoTheme.aprender);

      final scaffold = tester.widget<Scaffold>(
        find.descendant(of: page, matching: find.byType(Scaffold)),
      );
      expect(scaffold.backgroundColor, BrandColors.dark);
      final figure = find.descendant(of: page, matching: find.byType(Tevi));
      expect(figure, findsOneWidget);
      expect(tester.widget<Tevi>(figure).night, isTrue);
      final lead = tester.getRect(tiles.first);
      final tevi = tester.getRect(figure);
      expect(tevi.top, lessThan(lead.top));
      expect(tevi.bottom, greaterThan(lead.top));
      expect(tester.widget<PlayDisc>(find.byType(PlayDisc)).ring, isNull);
    });

    testWidgets('nine videos stand on a phone without scrolling; twelve '
        'scroll', (tester) async {
      await room(tester, catalog: () => many(9));
      expect(tiles, findsNWidgets(9));
      expect(roomScroll(tester), 0);
      await tester.pumpWidget(const SizedBox());

      await room(tester, catalog: () => many(12));
      expect(roomScroll(tester), greaterThan(0));
    });

    testWidgets('from 840 px the first video takes the start, the rest a grid '
        'beside and beneath it', (tester) async {
      await room(tester, size: const Size(1280, 800));

      final lead = tester.getRect(tiles.first);
      final beside = tester.getRect(tiles.at(1));
      expect(lead.left, 48);
      expect(beside.left, greaterThan(lead.right));
      expect(beside.top, lead.top);
      expect(tester.getRect(tiles.at(3)).top, greaterThan(beside.bottom));
      expect(tester.getRect(tiles.at(3)).left, greaterThan(lead.right));
    });

    testWidgets('a touch just after the page appears is ignored', (
      tester,
    ) async {
      final h = await room(tester, settle: false);
      await tester.tap(tiles.at(1), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(plays(h), isEmpty);
    });

    testWidgets('the tapped block grows into the page and shrinks back', (
      tester,
    ) async {
      await home(tester);
      final block = tester.getRect(blockOf(VideoTheme.bichos));
      await tester.tap(blockOf(VideoTheme.bichos));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final early = clipOf(tester);
      expect(early, isNotNull);
      expect(early!.width, lessThan(390));
      expect(early.width, greaterThanOrEqualTo(block.width));
      await tester.pumpAndSettle();
      expect(clipOf(tester), isNull);

      await tester.pump(TapGuard.window);
      await tester.tap(find.bySemanticsLabel(PlayerScreen.back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final late = clipOf(tester);
      expect(late, isNotNull);
      expect(late!.width, lessThan(390));
      await tester.pumpAndSettle();
      expect(find.byType(RoomScreen), findsNothing);
    });

    testWidgets('with animations off, the page simply replaces the home', (
      tester,
    ) async {
      await home(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      await tester.tap(blockOf(VideoTheme.bichos));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(clipOf(tester), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(RoomScreen), findsOneWidget);
    });
  });
}

/// Six themes; animals hold five videos, the third longer than the time
/// left; learning holds two.
final Map<String, Object?> themed = {
  'themes': [
    {
      'theme': 'bichos',
      'videos': [
        video('v1', 'O cachorro'),
        video('v2', 'O gato'),
        {...video('v3', 'O pato'), 'fits': false},
        video('v4', 'A tartaruga'),
        video('v5', 'O peixe'),
      ],
    },
    {
      'theme': 'musica',
      'videos': [video('m1')],
    },
    {
      'theme': 'historias',
      'videos': [video('h1')],
    },
    {
      'theme': 'aprender',
      'videos': [video('a1', 'Os números'), video('a2', 'As formas')],
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
};

/// [themed] with [n] videos of animals.
Map<String, Object?> many(int n) => {
  'themes': [
    {
      'theme': 'bichos',
      'videos': [for (var i = 1; i <= n; i++) video('v$i', 'Bicho $i')],
    },
    ...(themed['themes']! as List).skip(1),
  ],
};

/// A shared kid whose catalogue answers [catalog] ([themed] by default)
/// and whose plays answer [play], or open.
Harness themedKid({
  Map<String, Object?> Function()? catalog,
  FutureOr<http.Response> Function(String videoId)? play,
}) => Harness(
  signedIn: true,
  api: (req) {
    final path = req.url.path;
    if (path == '/v1/child/profile') return json(200, profileJson);
    if (path == '/v1/child/catalog') {
      return json(200, catalog?.call() ?? themed);
    }
    if (path.startsWith('/v1/child/thumbs/')) {
      return http.Response.bytes(pixel, 200);
    }
    if (path.endsWith('/beat')) {
      return json(200, {'state': 'ok', 'remaining_seconds': 600});
    }
    if (path == '/v1/child/plays') {
      final id =
          (jsonDecode(req.body) as Map<String, dynamic>)['video_id'] as String;
      return (play ??
          (id) => json(201, {
            'play_id': 'p-$id',
            'youtube_id': 'yt-$id',
            'remaining_seconds': 600,
          }))(id);
    }
    return http.Response('', 204);
  },
)..kidMode = {'minor_id': 'm1'};

/// The child home at [size].
Future<Harness> home(
  WidgetTester tester, {
  Map<String, Object?> Function()? catalog,
  FutureOr<http.Response> Function(String videoId)? play,
  Size size = const Size(390, 844),
}) async {
  final h = themedKid(catalog: catalog, play: play);
  await h.pump(tester, initial: '/crianca', size: size);
  return h;
}

/// The child home, then [theme]'s page opened from its block; [settle]
/// lets its transition and the moment after it appears pass.
Future<Harness> room(
  WidgetTester tester, {
  VideoTheme theme = VideoTheme.bichos,
  Map<String, Object?> Function()? catalog,
  FutureOr<http.Response> Function(String videoId)? play,
  Size size = const Size(390, 844),
  bool settle = true,
}) async {
  final h = await home(tester, catalog: catalog, play: play, size: size);
  await tester.ensureVisible(blockOf(theme));
  await tester.pumpAndSettle();
  await tester.tap(blockOf(theme));
  await tester.pump();
  if (!settle) {
    // Mid-way in, inside the moment after the page appears.
    await tester.pump(const Duration(milliseconds: 150));
    return h;
  }
  await tester.pumpAndSettle();
  await tester.pump(TapGuard.window);
  return h;
}

Finder get page => find.byType(RoomScreen);

/// The page's pictures, the first large.
Finder get tiles => find.descendant(of: page, matching: find.byType(VideoTile));

int reads(Harness h) =>
    h.actions.where((a) => a == 'GET /v1/child/catalog').length;

List<String> plays(Harness h) => [
  for (final c in h.actions)
    if (c.startsWith('POST /v1/child/plays {'))
      c.split('"video_id":"')[1].split('"').first,
];

double roomScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: page, matching: find.byType(Scrollable)),
    )
    .position
    .maxScrollExtent;

/// The growing ground's bounds while the page moves; null at rest.
Rect? clipOf(WidgetTester tester) {
  final clip = find.descendant(
    of: find.byType(RoomTransition),
    matching: find.byWidgetPredicate(
      (w) => w is ClipPath && w.clipper is RoomClipper,
    ),
  );
  if (clip.evaluate().isEmpty) return null;
  return (tester.widget<ClipPath>(clip).clipper! as RoomClipper)
      .rrect
      .outerRect;
}
