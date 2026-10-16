import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

final threeChildren = familyWith([
  minorJson('m1', 'Lia'),
  minorJson('m2', 'Téo', avatar: 'owl', ageBand: 'ate-4'),
  minorJson('m3', 'Nina', avatar: 'cat', ageBand: '9-12'),
]);

Future<Harness> list(
  WidgetTester tester, {
  Map<String, Object?>? family,
  Map<String, FutureOr<http.Response> Function()> rules = const {},
}) async {
  final h = Harness(signedIn: true, api: screenTimeApi(rules: rules))
    ..family = family ?? threeChildren;
  await h.pump(tester, initial: '/familia/tempo');
  return h;
}

void main() {
  testWidgets('one row per child with avatar, nickname and today in words', (
    tester,
  ) async {
    final h = await list(
      tester,
      rules: {
        'm1': () => json(200, rulesJson(usedSeconds: 40 * 60 + 59)),
        'm2': () => json(200, rulesJson(state: 'time_up', extension: 15)),
        'm3': () => json(200, rulesJson(state: 'outside_window')),
      },
    );

    expect(find.text('Tempo de tela'), findsOneWidget);
    for (final (name, words) in [
      ('Lia', '40 de 90 min hoje'),
      ('Téo', 'Acabou por hoje'),
      ('Nina', 'Fora do horário'),
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
    expect(h.actions, [
      'GET /v1/screentime/minors/m1',
      'GET /v1/screentime/minors/m2',
      'GET /v1/screentime/minors/m3',
    ]);
  });

  testWidgets('the limit counts today\'s extension', (tester) async {
    await list(
      tester,
      family: familyWith([minorJson('m1', 'Lia')]),
      rules: {'m1': () => json(200, rulesJson(usedSeconds: 0, extension: 30))},
    );

    expect(find.text('0 de 120 min hoje'), findsOneWidget);
  });

  testWidgets('each row is one button read by nickname and today', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await list(tester, family: familyWith([minorJson('m1', 'Lia')]));

    expect(find.bySemanticsLabel('Lia, 40 de 90 min hoje'), findsOne);
    semantics.dispose();
  });

  testWidgets('a row opens the child\'s hub', (tester) async {
    final h = await list(tester);

    await tester.tap(find.widgetWithText(DoorRow, 'Téo'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/tempo/m2');
  });

  testWidgets('a row whose read failed says so and still opens the hub', (
    tester,
  ) async {
    final h = await list(
      tester,
      rules: {'m2': () => problem(503, 'unavailable')},
    );

    final row = find.widgetWithText(DoorRow, 'Téo');
    expect(
      find.descendant(of: row, matching: find.text('Não deu para carregar')),
      findsOneWidget,
    );
    expect(find.text('40 de 90 min hoje'), findsNWidgets(2));

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(h.location(tester), '/familia/tempo/m2');
  });

  testWidgets('the loading placeholder, announced, while the rows load', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    await list(tester, rules: {'m1': () => answer.future});

    expect(find.byKey(const Key('family-placeholder')), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando o tempo de tela'), findsOne);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(DoorRow), findsNothing);

    answer.complete(json(200, rulesJson()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('family-placeholder')), findsNothing);
    expect(find.byType(DoorRow), findsNWidgets(3));
    semantics.dispose();
  });

  testWidgets('coming back from a hub reads the rows again', (tester) async {
    var used = 40;
    final h = Harness(
      signedIn: true,
      api: screenTimeApi(
        rules: {'m1': () => json(200, rulesJson(usedSeconds: used * 60))},
      ),
    )..family = familyWith([minorJson('m1', 'Lia')]);
    await h.pump(tester, initial: '/familia/tempo');
    await tester.tap(find.widgetWithText(DoorRow, 'Lia'));
    await tester.pumpAndSettle();

    used = 55;
    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/tempo');
    expect(find.text('55 de 90 min hoje'), findsOneWidget);
  });

  testWidgets('beneath a hub opened directly, the rows wait to be shown', (
    tester,
  ) async {
    final h = Harness(signedIn: true, api: screenTimeApi())
      ..family = threeChildren;
    await h.pump(tester, initial: '/familia/tempo/m1');

    expect(h.actions, [
      'GET /v1/screentime/minors/m1',
      'GET /v1/screentime/minors/m1/usage',
    ]);
    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();
    expect(find.byType(DoorRow), findsNWidgets(3));
  });

  testWidgets('back returns to the family home', (tester) async {
    final h = await list(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/');
  });

  testWidgets('with no children, it says to add one first', (tester) async {
    final h = await list(tester, family: familyWith([]));

    expect(find.byType(DoorRow), findsNothing);
    expect(find.text('Cadastre uma criança primeiro.'), findsOneWidget);
    expect(h.actions, isEmpty);
  });
}
