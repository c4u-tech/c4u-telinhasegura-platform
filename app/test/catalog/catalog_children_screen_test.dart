import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

Future<Harness> children(
  WidgetTester tester, {
  Map<String, Object?>? family,
  String initial = '/familia/videos',
}) async {
  final h = Harness(signedIn: true, api: catalogApi())
    ..family = family ?? threeChildren;
  await h.pump(tester, initial: initial);
  return h;
}

void main() {
  testWidgets('one row per child with avatar, nickname and band in words', (
    tester,
  ) async {
    final h = await children(tester);

    expect(find.text('Vídeos'), findsOneWidget);
    for (final (name, words) in [
      ('Lia', 'Vídeos de 5 a 8 anos'),
      ('Téo', 'Vídeos de até 4 anos'),
      ('Nina', 'Vídeos de 9 a 12 anos'),
    ]) {
      final row = find.widgetWithText(DoorRow, name);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(words)),
        findsOneWidget,
      );
    }
    final discs = tester.widgetList<AvatarDisc>(find.byType(AvatarDisc));
    expect(discs.map((d) => (d.avatar, d.size)), [
      (Avatar.fox, 56.0),
      (Avatar.owl, 56.0),
      (Avatar.cat, 56.0),
    ]);
    expect(h.actions, isEmpty, reason: 'the family read says it all');
  });

  testWidgets('each row is one button read by nickname and band', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await children(tester);

    expect(find.bySemanticsLabel('Lia, Vídeos de 5 a 8 anos'), findsOne);
    semantics.dispose();
  });

  testWidgets('a row opens the child\'s catalogue', (tester) async {
    final h = await children(tester);

    await tester.tap(find.widgetWithText(DoorRow, 'Téo'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos/m2');
  });

  testWidgets('back returns to the family home', (tester) async {
    final h = await children(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/');
  });

  testWidgets('with no children, it says to add one first', (tester) async {
    await children(tester, family: familyWith([]));

    expect(find.byType(DoorRow), findsNothing);
    expect(find.text('Cadastre uma criança primeiro.'), findsOneWidget);
  });

  testWidgets('a catalogue for a child the family does not hold goes back '
      'to the list with a notice', (tester) async {
    final h = await children(tester, initial: '/familia/videos/m9');

    expect(h.location(tester), '/familia/videos');
    expect(find.byType(Notice), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Lia'), findsOneWidget);
  });
}
