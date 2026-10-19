import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/display_title.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

final liaFamily = familyWith([
  minorJson('m1', 'Lia'),
  minorJson('m2', 'Téo', avatar: 'owl', ageBand: 'ate-4'),
]);

Future<Harness> hub(
  WidgetTester tester, {
  Map<String, Object?>? family,
  FutureOr<http.Response> Function()? rules,
  FutureOr<http.Response> Function()? usage,
  String id = 'm1',
}) async {
  final h = Harness(
    signedIn: true,
    api: screenTimeApi(rules: {id: ?rules}, usage: usage),
  )..family = family ?? liaFamily;
  await h.pump(tester, initial: '/familia/tempo/$id');
  return h;
}

Finder door(String title) => find.widgetWithText(DoorRow, title);

const weekRows = [
  'Hoje · 45 min',
  'Ontem · 1 h 10 min',
  'Sáb · 0 min',
  'Sex · 0 min',
  'Qui · 0 min',
  'Qua · 0 min',
  'Ter · 0 min',
];

void main() {
  testWidgets('titled by the nickname: today, the two doors, then the last '
      'seven days, in order', (tester) async {
    final h = await hub(tester);

    expect(find.widgetWithText(DisplayTitle, 'Lia'), findsOneWidget);
    final order = [
      find.text('Assistiu 40 min de 90.'),
      door('Mais tempo hoje'),
      door('Limite e horário'),
      find.text('Últimos 7 dias'),
      find.text('Hoje · 45 min'),
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    for (var i = 1; i < order.length; i++) {
      expect(
        tester.getTopLeft(order[i - 1]).dy,
        lessThan(tester.getTopLeft(order[i]).dy),
      );
    }
    expect(h.actions, [
      'GET /v1/screentime/minors/m1',
      'GET /v1/screentime/minors/m1/usage',
    ]);
  });

  testWidgets('today reads the watched minutes of the day\'s limit, and the '
      'extension on its own line', (tester) async {
    await hub(
      tester,
      rules: () =>
          json(200, rulesJson(usedSeconds: 40 * 60 + 50, extension: 30)),
    );

    expect(find.text('Assistiu 40 min de 120.'), findsOneWidget);
    expect(find.text('Mais 30 min dados hoje.'), findsOneWidget);
  });

  testWidgets('under a minute, not yet; no extension, no second line', (
    tester,
  ) async {
    await hub(tester, rules: () => json(200, rulesJson(usedSeconds: 59)));

    expect(find.text('Ainda não assistiu hoje.'), findsOneWidget);
    expect(find.textContaining('dados hoje'), findsNothing);
  });

  testWidgets('Limite e horário states the limit and the hours, and the '
      'band\'s defaults while they hold', (tester) async {
    final semantics = tester.ensureSemantics();
    await hub(tester, rules: () => json(200, rulesJson(isDefault: true)));

    final limits = door('Limite e horário');
    for (final line in [
      '90 min por dia · das 08:00 às 19:30',
      'Padrão da faixa 5 a 8 anos',
    ]) {
      expect(
        find.descendant(of: limits, matching: find.text(line)),
        findsOneWidget,
      );
    }
    expect(
      find.bySemanticsLabel(
        'Limite e horário, 90 min por dia · das 08:00 às 19:30, Padrão da '
        'faixa 5 a 8 anos',
      ),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('saved rules say nothing of the band', (tester) async {
    await hub(tester);

    expect(find.textContaining('Padrão da faixa'), findsNothing);
  });

  testWidgets('the youngest band reads as its label', (tester) async {
    await hub(
      tester,
      id: 'm2',
      rules: () => json(200, rulesJson(isDefault: true)),
    );

    expect(find.text('Padrão da faixa 2 a 4 anos'), findsOneWidget);
  });

  testWidgets('seven rows, today first, in words, none a target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await hub(tester);

    var above = 0.0;
    for (final row in weekRows) {
      final f = find.text(row);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      expect(f, findsOneWidget);
      expect(
        find.ancestor(of: f, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        tester.getSemantics(f),
        isSemantics(isButton: false, hasTapAction: false),
      );
      final top = tester.getTopLeft(f).dy;
      expect(top, greaterThan(above));
      above = top;
    }
    semantics.dispose();
  });

  for (final (title, path) in [
    ('Mais tempo hoje', '/familia/tempo/m1/mais'),
    ('Limite e horário', '/familia/tempo/m1/limite'),
  ]) {
    testWidgets('$title opens $path, and coming back reads the rules and the '
        'usage again', (tester) async {
      var used = 40;
      final h = Harness(
        signedIn: true,
        api: screenTimeApi(
          rules: {'m1': () => json(200, rulesJson(usedSeconds: used * 60))},
        ),
      )..family = liaFamily;
      await h.pump(tester, initial: '/familia/tempo/m1');

      await tester.tap(door(title));
      await tester.pumpAndSettle();
      expect(h.location(tester), path);

      used = 55;
      h.calls.clear();
      GoRouter.of(tester.element(find.byType(Scaffold).last))
          .go('/familia/tempo/m1');
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/tempo/m1');
      expect(h.actions, [
        'GET /v1/screentime/minors/m1',
        'GET /v1/screentime/minors/m1/usage',
      ]);
      expect(find.text('Assistiu 55 min de 90.'), findsOneWidget);
    });
  }

  testWidgets('a child that no longer exists goes back to the list with a '
      'notice', (tester) async {
    final h = await hub(tester, rules: () => problem(404, 'not_found'));

    expect(h.location(tester), '/familia/tempo');
    expect(find.text(Copy.childGone), findsOneWidget);
  });

  testWidgets('a child the family does not hold goes back the same way', (
    tester,
  ) async {
    final h = await hub(tester, id: 'gone');

    expect(h.location(tester), '/familia/tempo');
    expect(find.text(Copy.childGone), findsOneWidget);
  });

  testWidgets('the loading placeholder while the hub reads', (tester) async {
    final answer = Completer<http.Response>();
    await hub(tester, rules: () => answer.future);

    expect(find.byKey(const Key('family-placeholder')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    answer.complete(json(200, rulesJson()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('family-placeholder')), findsNothing);
  });

  testWidgets('a failed read says so, and Tentar de novo reads again', (
    tester,
  ) async {
    var fail = true;
    final h = await hub(
      tester,
      rules: () => fail ? problem(503, 'unavailable') : json(200, rulesJson()),
    );

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorNote), findsNothing);
    expect(find.text('Assistiu 40 min de 90.'), findsOneWidget);
    expect(h.location(tester), '/familia/tempo/m1');
  });

  testWidgets('rate_limited counts down before Tentar de novo waits no more', (
    tester,
  ) async {
    await hub(
      tester,
      rules: () => problem(429, 'rate_limited', retryAfterBody: 5),
    );

    expect(find.text(Copy.retryIn(const Duration(seconds: 5))), findsOne);
    final retry = find.widgetWithText(PrimaryButton, 'Tentar de novo');
    expect(tester.widget<PrimaryButton>(retry).onPressed, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<PrimaryButton>(retry).onPressed, isNotNull);
  });

  testWidgets('back returns to the list', (tester) async {
    final h = await hub(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/tempo');
  });
}
