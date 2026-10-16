import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/staff/account_search_screen.dart';

import '../access/harness.dart';
import '../curation/fixtures.dart';
import '../family/fixtures.dart';

const intro =
    'A busca é por e-\u2060mail exato ou pelo código da conta. Cada busca '
    'fica na auditoria, com o motivo.';
const why = 'Pedido de suporte.';
const biaId = '0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6f';

Finder get field =>
    find.widgetWithText(TextField, 'E-\u2060mail ou código da conta');
Finder get reason => find.widgetWithText(TextField, 'Motivo');
Finder get search => find.widgetWithText(FilledButton, 'Buscar');

bool waits(WidgetTester tester) =>
    tester.widget<FilledButton>(search).onPressed == null;

String? fieldError(WidgetTester tester) =>
    tester.widget<TextField>(field).decoration?.errorText;

/// The directory's requests among those sent.
List<String> lookups(Harness h) => [
  for (final c in h.actions)
    if (c.startsWith('POST /v1/admin/accounts') ||
        c.startsWith('GET /v1/admin/accounts'))
      c,
];

Future<Harness> searchOf(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? lookup,
  String initial = '/admin/contas',
}) async {
  final h = Harness(signedIn: true, api: adminApi(lookup: lookup))
    ..family = ownerFamily
    ..roles = ['admin'];
  await h.pump(tester, initial: initial);
  return h;
}

Future<void> fill(
  WidgetTester tester, {
  String who = 'bia@example.com',
  String motivo = why,
}) async {
  await tester.enterText(field, who);
  await tester.enterText(reason, motivo);
  await tester.pump();
}

Future<void> press(WidgetTester tester) async {
  await tester.ensureVisible(search);
  await tester.pumpAndSettle();
  await tester.tap(search);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('"Buscar uma conta" reads its line, the field, "Motivo" and '
      '"Buscar", which waits on the field and a reason of 3 to 200 '
      'characters', (tester) async {
    await searchOf(tester);

    expect(find.text('Buscar uma conta'), findsWidgets);
    final order = [find.text(intro), field, reason, search];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    expect(waits(tester), isTrue);

    await tester.enterText(field, '  ');
    await tester.enterText(reason, why);
    await tester.pump();
    expect(waits(tester), isTrue, reason: 'a blank field');

    await tester.enterText(field, 'bia@example.com');
    await tester.enterText(reason, ' ab ');
    await tester.pump();
    expect(waits(tester), isTrue, reason: 'a reason under 3');

    await tester.enterText(reason, 'abc');
    await tester.pump();
    expect(waits(tester), isFalse);

    expect(find.text('159 de 200'), findsNothing);
    await tester.enterText(reason, 'a' * 160);
    await tester.pump();
    expect(find.text('160 de 200'), findsOneWidget);
  });

  for (final (who, body) in [
    (' bia@example.com ', '{"email":"bia@example.com","reason":"$why"}'),
    (' $biaId ', '{"account_id":"$biaId","reason":"$why"}'),
  ]) {
    testWidgets('"Buscar" with "${who.trim()}" sends ${body.split('"')[1]} '
        'and opens the sheet with the answer', (tester) async {
      final h = await searchOf(tester);

      await fill(tester, who: who, motivo: '  $why ');
      await press(tester);

      expect(lookups(h), ['POST /v1/admin/accounts/lookup $body']);
      expect(h.location(tester), '/admin/contas/a2');
      expect(find.text('Conta'), findsWidgets);
    });
  }

  for (final (code, words) in [
    ('account_not_found', 'Nenhuma conta com esse e-\u2060mail ou código.'),
    ('validation', 'Isso não é um e-\u2060mail nem um código de conta.'),
  ]) {
    testWidgets('$code is said on the field, every input kept', (tester) async {
      final h = await searchOf(
        tester,
        lookup: (_) => problem(code == 'validation' ? 400 : 404, code),
      );

      await fill(tester);
      await press(tester);

      expect(h.location(tester), '/admin/contas');
      expect(fieldError(tester), words);
      expect(find.byType(ErrorNote), findsNothing);
      expect(find.text('bia@example.com'), findsOneWidget);
      expect(find.text(why), findsOneWidget);

      await tester.enterText(field, 'caio@example.com');
      await tester.pump();
      expect(fieldError(tester), isNull);
    });
  }

  testWidgets('rate_limited shows the clay note counting down in minutes '
      'from Retry-After, "Buscar" waiting until it ends', (tester) async {
    await searchOf(
      tester,
      lookup: (_) => problem(429, 'rate_limited', retryAfterBody: 690),
    );

    await fill(tester);
    await press(tester);

    String note(int m) =>
        'Você fez muitas buscas nesta hora. Tente de novo em $m\u00A0min.';
    expect(find.widgetWithText(ErrorNote, note(12)), findsOneWidget);
    expect(waits(tester), isTrue);

    await tester.pump(const Duration(seconds: 29));
    expect(find.text(note(12)), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(note(11)), findsOneWidget);
    expect(waits(tester), isTrue);

    await tester.pump(const Duration(minutes: 11));
    expect(find.byType(ErrorNote), findsNothing);
    expect(waits(tester), isFalse);
  });

  testWidgets('a failed request shows the error note, every input kept', (
    tester,
  ) async {
    await searchOf(
      tester,
      lookup: (_) => throw http.ClientException('offline'),
    );

    await fill(tester);
    await press(tester);

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.text('bia@example.com'), findsOneWidget);
    expect(waits(tester), isFalse);
  });

  testWidgets('not_admin goes home with today\'s notice', (tester) async {
    final h = await searchOf(tester, lookup: (_) => problem(403, 'not_admin'));

    await fill(tester);
    await press(tester);

    expect(h.location(tester), '/');
    expect(
      find.text('Você não tem mais acesso à administração.'),
      findsOneWidget,
    );
  });

  testWidgets('back from the sheet finds the field and the reason empty', (
    tester,
  ) async {
    final h = await searchOf(tester);

    await fill(tester);
    await press(tester);
    expect(h.location(tester), '/admin/contas/a2');

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/admin/contas');
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(reason).controller!.text, isEmpty);
    expect(waits(tester), isTrue);
  });

  testWidgets('the sheet opened without one in memory goes to the search '
      'and asks the server nothing', (tester) async {
    final h = await searchOf(tester, initial: '/admin/contas/a2');

    expect(h.location(tester), '/admin/contas');
    expect(find.text(intro), findsOneWidget);
    expect(lookups(h), isEmpty);
  });

  testWidgets('back goes to Administração', (tester) async {
    final h = await searchOf(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/admin');
  });

  test('the field\'s words keep "e-mail" whole', () {
    expect(accountNotFound, contains('e-\u2060mail'));
    expect(notAccountKey, contains('e-\u2060mail'));
  });
}
