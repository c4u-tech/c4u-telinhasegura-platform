import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/profile_picker_screen.dart';

import '../auth/fakes.dart' show json;
import '../design/pump.dart';
import 'kid_mosaic_test.dart' show mosaic, sixThemes;
import 'profile_picker_screen_test.dart' show linkedExit, toPicker;

/// Whether each mascot below [within] blinks as its screen arrives.
List<bool> blinking(WidgetTester tester, [Finder? within]) => [
  for (final t in tester.widgetList<Tevi>(
    within == null
        ? find.byType(Tevi)
        : find.descendant(of: within, matching: find.byType(Tevi)),
  ))
    t.blinks,
];

void main() {
  testWidgets('the home\'s mascot blinks as the home arrives', (tester) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));
    expect(blinking(tester, find.byType(KidMosaic)), [true]);
  });

  testWidgets('the picker\'s mascot blinks as the picker arrives', (
    tester,
  ) async {
    await linkedExit(tester);
    await toPicker(tester);
    expect(blinking(tester, find.byType(ProfilePickerScreen)), [true]);
  });

  testWidgets('a resting picture\'s mascot blinks as its screen arrives', (
    tester,
  ) async {
    await pumpOn(
      tester,
      const ShelfPicture(look: TeviLook.watching),
      ground: Ground.kid,
    );
    expect(blinking(tester), [true]);
  });

  testWidgets('the loading home\'s mascot does not: its gaze is what moves', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeOf(Ground.kid),
        home: const Scaffold(body: MosaicLoading()),
      ),
    );
    expect(blinking(tester), [false]);
  });

  for (final beside in [false, true]) {
    testWidgets('an error note\'s mascot does not: it answers a problem, '
        '${beside ? 'beside' : 'above'} its line', (tester) async {
      await pumpOn(
        tester,
        KidErrorNote('Não deu certo agora.', beside: beside),
        ground: Ground.kid,
      );
      expect(blinking(tester), [false]);
    });
  }
}
