import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/shelves.dart';

import '../access/harness.dart';
import '../design/pump.dart';
import 'kid_mosaic_test.dart' show mosaic;

const _note = 'Esse vídeo não abriu agora.';

/// The look the mascot inside [within] is drawn with now.
TeviLook drawn(WidgetTester tester, Finder within) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.descendant(
                      of: within,
                      matching: find.byType(Tevi),
                    ),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TeviPainter)
        .look;

void main() {
  for (final (name, state, catalog) in [
    ('empty', EmptyShelf, () => json(200, {'themes': []})),
    ('failed', ShelvesFailed, () => problem(503, 'internal')),
  ]) {
    group('a note over the $name home', () {
      testWidgets('carries no mascot: the home\'s own raises its crest, one '
          'mascot on the screen', (tester) async {
        final h = await mosaic(tester, catalog: catalog);
        expect(find.byType(Tevi), findsOneWidget);

        h.services.kidReturn.value = (note: _note, refetch: false);
        await tester.pump();

        final note = find.byType(KidErrorNote);
        expect(note, findsOneWidget);
        expect(find.descendant(of: note, matching: find.text(_note)), findsOne);
        expect(
          find.descendant(of: note, matching: find.byType(Tevi)),
          findsNothing,
        );
        expect(find.byType(Tevi), findsOneWidget);
        await tester.pumpAndSettle();
        expect(drawn(tester, find.byType(state)), TeviLook.crestUp);
        // The note stands above the picture, as before.
        expect(
          tester.getRect(note).bottom,
          lessThan(tester.getRect(find.byType(state)).top),
        );
      });

      testWidgets('under reduced motion the crest is up at once', (
        tester,
      ) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final h = await mosaic(tester, catalog: catalog);

        h.services.kidReturn.value = (note: _note, refetch: false);
        await tester.pump();

        expect(drawn(tester, find.byType(state)), TeviLook.crestUp);
      });
    });
  }

  testWidgets('on the empty home the crest rises over the scale\'s change '
      'and settles back when the note leaves', (tester) async {
    await pumpOn(tester, const EmptyShelf(), ground: Ground.kid);
    final shelf = find.byType(EmptyShelf);
    expect(drawn(tester, shelf), TeviLook.watching);

    await pumpOn(tester, const EmptyShelf(alerted: true), ground: Ground.kid);
    await tester.pump(const Duration(milliseconds: 110));
    expect(drawn(tester, shelf).crest, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(drawn(tester, shelf), TeviLook.crestUp);

    await pumpOn(tester, const EmptyShelf(), ground: Ground.kid);
    await tester.pumpAndSettle();
    expect(drawn(tester, shelf), TeviLook.watching);
  });

  testWidgets('a note without its mascot is the line alone, still announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpOn(
      tester,
      const KidErrorNote(_note, mascot: false),
      ground: Ground.kid,
    );

    expect(find.byType(Tevi), findsNothing);
    expect(find.byType(ShelfPicture), findsNothing);
    expect(find.text(_note), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(KidErrorNote)),
      matchesSemantics(isLiveRegion: true, label: _note),
    );
    semantics.dispose();
  });
}
