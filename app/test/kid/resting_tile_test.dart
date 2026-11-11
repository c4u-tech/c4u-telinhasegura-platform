import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';

import '../access/harness.dart';
import 'kid_shelves_test.dart';

/// Today's shelves where `v2` is longer than the time left, and one
/// pacotinho whose videos together do not fit.
final Map<String, Object?> notAll = {
  'themes': [
    {
      'theme': 'bichos',
      'videos': [
        video('v1', 'O cachorro e a bola'),
        {...video('v2', 'A baleia azul'), 'fits': false},
        video('v3'),
      ],
    },
  ],
  'packs': [
    {
      'id': 'k1',
      'title': 'Bichos do mar',
      'cover_video_id': 'v1',
      'videos': [video('v1'), video('v3')],
      'fits': false,
    },
  ],
};

int playsAsked(Harness h) =>
    h.actions.where((a) => a.startsWith('POST /v1/child/plays {')).length;

void main() {
  testWidgets('a video that does not fit stays in its place, resting, '
      'read as not for today', (tester) async {
    await shelves(tester, catalog: () => json(200, notAll));

    final tiles = tilesIn(shelfOf(VideoTheme.bichos));
    // The third tile waits past the screen's edge; the row is lazy.
    expect(tiles, findsAtLeast(2));
    final second = tester.widget<VideoTile>(tiles.at(1));
    expect(second.video.id, 'v2');
    expect(second.resting, isTrue);
    expect(tester.widget<VideoTile>(tiles.at(0)).resting, isFalse);
    expect(find.bySemanticsLabel('A baleia azul, não cabe hoje'), findsOne);
    expect(find.bySemanticsLabel('O cachorro e a bola'), findsOne);
  });

  testWidgets('a tap on a resting video asks for no play and says why on '
      'the shelves', (tester) async {
    final h = await shelves(tester, catalog: () => json(200, notAll));

    await tester.tap(tilesIn(shelfOf(VideoTheme.bichos)).at(1));
    await tester.pumpAndSettle();

    expect(playsAsked(h), 0);
    expect(h.location(tester), '/crianca');
    expect(find.byType(KidErrorNote), findsOne);
    expect(find.text(PlayerScreen.doesNotFit), findsOne);
  });

  testWidgets('a pacotinho that does not fit rests, is read so, and a tap '
      'opens nothing', (tester) async {
    final h = await shelves(tester, catalog: () => json(200, notAll));

    final pack = tester.widget<PackTile>(find.byType(PackTile));
    expect(pack.pack.fits, isFalse);
    expect(
      find.bySemanticsLabel(
        'Bichos do mar, pacotinho de 2 vídeos, não cabe hoje',
      ),
      findsOne,
    );

    await tester.tap(find.byType(PackTile));
    await tester.pumpAndSettle();

    expect(playsAsked(h), 0);
    expect(find.text(PlayerScreen.packDoesNotFit), findsOne);
  });

  testWidgets('a tile that fits still plays', (tester) async {
    final h = await shelves(tester, catalog: () => json(200, notAll));

    await tester.tap(tilesIn(shelfOf(VideoTheme.bichos)).first);
    await tester.pump();

    expect(playsAsked(h), 1);
  });

  testWidgets('the resting picture is quieted and outlined, with nothing '
      'written on it', (tester) async {
    await shelves(tester, catalog: () => json(200, notAll));

    final resting = tilesIn(shelfOf(VideoTheme.bichos)).at(1);
    expect(
      find.descendant(of: resting, matching: find.byType(ColorFiltered)),
      findsOne,
    );
    expect(
      find.descendant(of: resting, matching: find.byType(Text)),
      findsNothing,
    );
    final awake = tilesIn(shelfOf(VideoTheme.bichos)).first;
    expect(
      find.descendant(of: awake, matching: find.byType(ColorFiltered)),
      findsNothing,
    );
  });

  testWidgets('a resting tile tapped on a lower shelf brings the note into '
      'view', (tester) async {
    const themes = [
      'bichos',
      'musica',
      'historias',
      'aprender',
      'brincar',
      'natureza',
    ];
    final six = {
      'themes': [
        for (final (i, t) in themes.indexed)
          {
            'theme': t,
            'videos': [
              {...video('x$i', 'Vídeo $t'), 'fits': i != themes.length - 1},
            ],
          },
      ],
    };
    final h = await shelves(
      tester,
      catalog: () => json(200, six),
      size: const Size(360, 640),
    );

    final last = tilesIn(shelfOf(VideoTheme.natureza));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();

    expect(playsAsked(h), 0);
    final note = tester.getRect(find.byType(KidErrorNote));
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      screen.contains(note.topLeft) && screen.contains(note.bottomRight),
      isTrue,
      reason: 'the note at $note is outside the screen $screen',
    );
  });
}
