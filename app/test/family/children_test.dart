import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/reconsent_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';

Future<Harness> children(
  WidgetTester tester, {
  Map<String, Object?> family = ownerFamily,
}) async {
  final h = Harness(signedIn: true)..family = family;
  await h.pump(tester, initial: '/familia/criancas');
  return h;
}

void main() {
  test('the full family\'s words name the real limit', () {
    expect(Copy.childrenFull, contains('$kMaxMinors crianças'));
  });

  testWidgets('lists each child with avatar, nickname and age band', (
    tester,
  ) async {
    await children(
      tester,
      family: familyWith([
        minorJson('m1', 'Lia'),
        minorJson('m2', 'Téo', avatar: 'owl', ageBand: 'ate-4'),
      ]),
    );

    expect(find.text('Crianças'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Lia'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Téo'), findsOneWidget);
    expect(find.text('5 a 8 anos'), findsOneWidget);
    expect(find.text('Até 4 anos'), findsOneWidget);
    final discs = tester.widgetList<AvatarDisc>(find.byType(AvatarDisc));
    expect(discs.map((d) => (d.avatar, d.size)), [
      (Avatar.fox, 56.0),
      (Avatar.owl, 56.0),
    ]);
    expect(find.text('2 de 10 crianças'), findsOneWidget);
  });

  testWidgets('each row is one button named by the child', (tester) async {
    final semantics = tester.ensureSemantics();
    await children(tester);

    expect(find.bySemanticsLabel('Lia, 5 a 8 anos'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a row opens the child', (tester) async {
    final h = await children(tester);

    await tester.tap(find.widgetWithText(DoorRow, 'Lia'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/criancas/m1');
  });

  testWidgets('Cadastrar criança opens the two steps', (tester) async {
    final h = await children(tester);

    await tester.ensureVisible(find.text('Cadastrar criança'));
    await tester.tap(find.text('Cadastrar criança'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/criancas/nova');
  });

  testWidgets('back returns to the family home', (tester) async {
    final h = await children(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/');
  });

  testWidgets('with no children, it says what a profile holds, what the '
      'child watches included, and for how long', (tester) async {
    await children(tester, family: familyWith([]));

    expect(find.byType(DoorRow), findsNothing);
    final teaching = find.textContaining('apelido');
    expect(teaching, findsOneWidget);
    final text = tester.widget<Text>(teaching).data!;
    expect(text, contains('avatar'));
    expect(text, contains('faixa de idade'));
    expect(text, contains('o que a criança assiste'));
    expect(text, contains('30 dias'));
    expect(text, contains('tempo de tela'));
    expect(text, contains('90'));
    expect(text, isNot(contains('Nada mais')));
    expect(text, isNot(contains('três coisas')));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a full family disables Cadastrar criança and says why', (
    tester,
  ) async {
    await children(
      tester,
      family: familyWith([
        for (var i = 0; i < kMaxMinors; i++) minorJson('m$i', 'Criança $i'),
      ]),
    );

    final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    expect(button.onPressed, isNull);
    expect(find.text(Copy.childrenFull), findsOneWidget);
    expect(find.text('10 de 10 crianças'), findsOneWidget);
  });

  testWidgets('a paused child says it needs a new authorization, read with '
      'the row', (tester) async {
    final semantics = tester.ensureSemantics();
    await children(
      tester,
      family: familyWith([
        pausedMinorJson('m1', 'Lia'),
        minorJson('m2', 'Téo'),
      ]),
    );

    expect(find.text(needsConsent), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(DoorRow, 'Lia'),
        matching: find.text(needsConsent),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Lia, 5 a 8 anos, $needsConsent'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Téo, 5 a 8 anos'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a paused child\'s row opens the new authorization', (
    tester,
  ) async {
    final h = await children(
      tester,
      family: familyWith([pausedMinorJson('m1', 'Lia')]),
    );

    await tester.tap(find.widgetWithText(DoorRow, 'Lia'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/criancas/m1/autorizar');
  });
}
