import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';

import '../access/harness.dart';
import 'kid_mosaic_test.dart';
import 'shelf_picture.dart';

/// Today's home where the highlight `v1` and the second picture `v4` are
/// longer than the time left; the first picture `v3` fits.
final Map<String, Object?> notAll = {
  'themes': [
    {
      'theme': 'bichos',
      'videos': [
        {...video('v1', 'A baleia azul'), 'fits': false},
        video('v2'),
      ],
    },
    {
      'theme': 'musica',
      'videos': [video('v3', 'O cachorro e a bola')],
    },
    {
      'theme': 'historias',
      'videos': [
        {...video('v4', 'A lua dorminhoca'), 'fits': false},
      ],
    },
  ],
};

/// [notAll] led by a pacotinho whose videos together do not fit.
final Map<String, Object?> packRests = {
  ...notAll,
  'packs': [
    {
      'id': 'k1',
      'title': 'Bichos do mar',
      'cover_video_id': 'v2',
      'videos': [video('v2'), video('v3')],
      'fits': false,
    },
  ],
};

/// Every theme, the third's first video too long for today: the
/// second picture rests, and the home scrolls on a small phone.
final Map<String, Object?> sixThemesResting = {
  'themes': [
    for (final (i, t) in [
      'bichos',
      'musica',
      'historias',
      'aprender',
      'brincar',
      'natureza',
    ].indexed)
      {
        'theme': t,
        'videos': [
          {...video('x$i', 'Vídeo $t'), 'fits': i != 2},
        ],
      },
  ],
};

int playsAsked(Harness h) =>
    h.actions.where((a) => a.startsWith('POST /v1/child/plays {')).length;

VideoTile tileIn(WidgetTester tester, Finder f) => tester.widget<VideoTile>(
  find.descendant(of: f, matching: find.byType(VideoTile)),
);

void main() {
  testWidgets('a highlight or a picture that does not fit stays in its '
      'place, resting, read as not for today', (tester) async {
    final semantics = tester.ensureSemantics();
    await mosaic(tester, catalog: () => json(200, notAll));

    expect(tileIn(tester, highlight).video.id, 'v1');
    expect(tileIn(tester, highlight).resting, isTrue);
    expect(tileIn(tester, pictures.first).resting, isFalse);
    expect(tileIn(tester, pictures.at(1)).video.id, 'v4');
    expect(tileIn(tester, pictures.at(1)).resting, isTrue);
    expect(find.bySemanticsLabel('A baleia azul, não cabe hoje'), findsOne);
    expect(find.bySemanticsLabel('A lua dorminhoca, não cabe hoje'), findsOne);
    expect(find.bySemanticsLabel('O cachorro e a bola'), findsOne);
    semantics.dispose();
  });

  for (final (name, target) in [
    ('the highlight', () => highlight),
    ('a picture', () => pictures.at(1)),
  ]) {
    testWidgets('a tap on $name resting asks for no play and says why on the '
        'home', (tester) async {
      final h = await mosaic(tester, catalog: () => json(200, notAll));

      await tester.tap(target());
      await tester.pumpAndSettle();

      expect(playsAsked(h), 0);
      expect(h.location(tester), '/crianca');
      expect(find.byType(KidErrorNote), findsOne);
      expect(find.text(PlayerScreen.doesNotFit), findsOne);
    });
  }

  testWidgets('the note for a video that does not fit is the sleepy '
      'telinha, calm, not the error tone', (tester) async {
    await mosaic(tester, catalog: () => json(200, notAll));

    await tester.tap(highlight);
    await tester.pumpAndSettle();

    final note = tester.widget<KidErrorNote>(find.byType(KidErrorNote));
    expect(note.asleep, isTrue);
    // Asleep, as on the day without time: "not now". Large in the
    // floating card's night.
    expectNoteFigure(tester, find.byType(KidErrorNote), TeviLook.asleep);
    final line = tester.widget<Text>(find.text(PlayerScreen.doesNotFit));
    expect(line.style?.color, isNot(Palette.kid.error));
  });

  testWidgets('a pacotinho that does not fit rests, is read so, and a tap '
      'opens nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await mosaic(tester, catalog: () => json(200, packRests));

    final pack = tester.widget<PackTile>(find.byType(PackTile));
    expect(pack.pack.fits, isFalse);
    expect(
      find.bySemanticsLabel(
        'Bichos do mar, pacotinho de 2 vídeos, não cabe hoje',
      ),
      findsOne,
    );

    await tester.tap(highlight);
    await tester.pumpAndSettle();

    expect(playsAsked(h), 0);
    expect(find.text(PlayerScreen.packDoesNotFit), findsOne);
    semantics.dispose();
  });

  testWidgets('a resting pacotinho\'s play disc rests with its picture: '
      'quieted under the same filter, still in its corner', (tester) async {
    await mosaic(tester, catalog: () => json(200, packRests));

    final quieted = find.descendant(
      of: highlight,
      matching: find.byType(ColorFiltered),
    );
    expect(quieted, findsOne);
    expect(
      find.descendant(of: quieted, matching: find.byType(PlayDisc)),
      findsOne,
    );
  });

  testWidgets('a picture that fits still plays', (tester) async {
    final h = await mosaic(tester, catalog: () => json(200, notAll));

    await tester.tap(pictures.first);
    await tester.pump();

    expect(playsAsked(h), 1);
  });

  testWidgets('the resting picture is quieted and outlined, with nothing '
      'written on it', (tester) async {
    await mosaic(tester, catalog: () => json(200, notAll));

    final resting = pictures.at(1);
    expect(
      find.descendant(of: resting, matching: find.byType(ColorFiltered)),
      findsOne,
    );
    expect(
      find.descendant(of: resting, matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(of: pictures.first, matching: find.byType(ColorFiltered)),
      findsNothing,
    );
  });

  testWidgets('a resting picture tapped with the home scrolled shows the '
      'note floating at the foot, the home where the child left it', (
    tester,
  ) async {
    final h = await mosaic(
      tester,
      catalog: () => json(200, sixThemesResting),
      size: const Size(360, 640),
    );

    final home = find.byType(Scrollable).first;
    ScrollPosition position() => tester.state<ScrollableState>(home).position;
    await tester.drag(home, const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrolled = position().pixels;
    expect(scrolled, greaterThan(0));
    await tester.tap(pictures.at(1));
    await tester.pumpAndSettle();

    expect(position().pixels, scrolled);
    expect(playsAsked(h), 0);
    final note = tester.getRect(find.byType(FloatingNote));
    expect(note.top, greaterThanOrEqualTo(KidLayout.stripHeight));
    expect(note.bottom, closeTo(640 - Space.md, .5));
  });
}
