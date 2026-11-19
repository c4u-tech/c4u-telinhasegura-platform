import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/player_keys.dart';
import 'package:telinha_segura/kid/press_sink.dart';
import 'package:telinha_segura/kid/profile_picker_screen.dart';
import 'package:telinha_segura/kid/room_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid_mode/hand_over_screen.dart';

import '../auth/fakes.dart' show json;
import '../design/pump.dart';
import 'kid_mosaic_test.dart' show mosaic, sixThemes;
import 'packs_page_test.dart' show packsPage, sixThemesWithPacks;
import 'player_screen_test.dart' show watching;
import 'profile_picker_screen_test.dart' show linkedExit, toPicker;
import 'theme_page_test.dart' show room;

/// Fails unless each of [targets] sinks under a press: a [PressSink]
/// holds it, or it holds one.
void expectEachSinks(Finder targets) {
  final elements = targets.evaluate().toList();
  expect(elements, isNotEmpty, reason: '$targets');
  for (final element in elements) {
    final at = find.byElementPredicate((e) => e == element);
    final around = find.ancestor(of: at, matching: find.byType(PressSink));
    final inside = find.descendant(of: at, matching: find.byType(PressSink));
    expect(
      around.evaluate().length + inside.evaluate().length,
      1,
      reason: '${element.widget.runtimeType} sinks once',
    );
  }
}

void main() {
  testWidgets('on the home: the doors, the pacotinhos\' band, the pictures '
      'and the exit', (tester) async {
    await mosaic(tester, catalog: () => json(200, sixThemesWithPacks));
    expectEachSinks(find.byType(ThemeBlock));
    expectEachSinks(find.byType(PacksDoor));
    expectEachSinks(find.byType(HighlightPicture));
    expectEachSinks(find.byType(HoldToExit));
  });

  testWidgets('on a home with no pacotinho: the one-tap pictures', (
    tester,
  ) async {
    await mosaic(tester, catalog: () => json(200, sixThemes));
    expectEachSinks(find.byType(HighlightPicture));
    expectEachSinks(find.byType(OneTapPicture));
  });

  testWidgets('on the pacotinhos\' page: every pacotinho', (tester) async {
    await packsPage(tester);
    expectEachSinks(find.byType(PackTile));
  });

  testWidgets('on a theme\'s page: every picture and the way back', (
    tester,
  ) async {
    await room(tester);
    expectEachSinks(
      find.descendant(
        of: find.byType(RoomScreen),
        matching: find.byType(VideoTile),
      ),
    );
    expectEachSinks(find.byType(RoomBack));
  });

  testWidgets('in the player: its keys', (tester) async {
    await watching(tester);
    expectEachSinks(find.byType(PlayerKey));
  });

  testWidgets('on the picker: every child\'s avatar and the way back', (
    tester,
  ) async {
    await linkedExit(tester);
    await toPicker(tester);
    expectEachSinks(
      find.descendant(
        of: find.byType(ProfilePickerScreen),
        matching: find.byType(ChildChoice),
      ),
    );
    expectEachSinks(find.byType(KidBack));
  });

  testWidgets('when the videos did not come: the key that tries again', (
    tester,
  ) async {
    await pumpOn(tester, ShelvesFailed(onRetry: () {}), ground: Ground.kid);
    expectEachSinks(find.widgetWithText(FilledButton, ShelvesFailed.retry));
  });
}
