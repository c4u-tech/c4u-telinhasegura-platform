import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/kid_catalog.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/shelves.dart';

import 'kid_mosaic_test.dart' show pixel;

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
}
