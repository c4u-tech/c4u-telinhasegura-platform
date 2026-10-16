import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';

/// `/familia/excluir` as the owner of [family], over an API that deletes
/// it (after a re-authentication when [reauth]), unless [answer] answers.
Future<Harness> deleting(
  WidgetTester tester, {
  Map<String, Object?> family = ownerFamily,
  FutureOr<http.Response> Function(http.Request)? answer,
  bool reauth = false,
}) async {
  late final Harness h;
  var confirmed = !reauth;
  h = Harness(
    signedIn: true,
    api: (req) {
      if (req.url.path == '/v1/session/reauth') {
        confirmed = true;
        return http.Response('', 204);
      }
      if (answer != null) return answer(req);
      if (req.method == 'DELETE' && req.url.path == '/v1/family') {
        if (!confirmed) return problem(403, 'reauth_required');
        h.family = null;
        return http.Response('', 204);
      }
      return http.Response('', 204);
    },
  )..family = family;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/familia/excluir');
  return h;
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get deleteButton =>
    find.widgetWithText(PrimaryButton, 'Excluir família');

VoidCallback? deleteOf(WidgetTester tester) =>
    tester.widget<PrimaryButton>(deleteButton).onPressed;

String words(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' ');

void main() {
  testWidgets('states what is erased: each child by nickname, the pending '
      'invitations, and that the other adults lose access and get an email', (
    tester,
  ) async {
    await deleting(
      tester,
      family: {
        ...familyWith([minorJson('m1', 'Lia'), minorJson('m2', 'Téo')]),
      },
    );

    final said = words(tester);
    expect(find.text('Excluir família'), findsWidgets);
    expect(said, contains('Lia e Téo'));
    expect(said, contains('convite esperando resposta'));
    expect(said, contains('bia@example.com'));
    expect(said, contains('perde o acesso'));
    expect(said, contains('e-\u2060mail'));
  });

  testWidgets('a family with nothing else names only what it has', (
    tester,
  ) async {
    await deleting(
      tester,
      family: {
        ...familyWith([]),
        'members': [(ownerFamily['members']! as List).first],
        'pending_invitations': 0,
        'invitations': <Object>[],
      },
    );

    final said = words(tester);
    expect(said, isNot(contains('perfil')));
    expect(said, isNot(contains('convite')));
    expect(said, isNot(contains('perde o acesso')));
  });

  testWidgets('Excluir família waits for the declaration', (tester) async {
    await deleting(tester);

    expect(deleteOf(tester), isNull);
    expect(find.text(declarationHint), findsOneWidget);

    await tapOn(tester, find.byType(DeclarationRow));

    expect(deleteOf(tester), isNotNull);
    expect(find.text(declarationHint), findsNothing);
  });

  testWidgets('confirming asks to confirm it is you, deletes the family, '
      'and shows the first use', (tester) async {
    final h = await deleting(tester, reauth: true);

    await tapOn(tester, find.byType(DeclarationRow));
    await tapOn(tester, deleteButton);
    expect(find.byType(ReauthPrompt), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'uma senha longa');
    await tester.pumpAndSettle();
    await tapOn(tester, find.text('Confirmar'));

    expect(h.actions, [
      'DELETE /v1/family',
      'POST /v1/session/reauth {"password":"uma senha longa"}',
      'DELETE /v1/family',
    ]);
    expect(h.location(tester), '/');
    expect(find.text('Começar minha família'), findsOneWidget);
    expect(find.text('Você não faz mais parte desta família.'), findsNothing);
  });

  testWidgets('cancelling the prompt deletes nothing and stays', (
    tester,
  ) async {
    final h = await deleting(tester, reauth: true);

    await tapOn(tester, find.byType(DeclarationRow));
    await tapOn(tester, deleteButton);
    await tapOn(tester, find.text('Cancelar'));

    expect(h.actions, ['DELETE /v1/family']);
    expect(h.location(tester), '/familia/excluir');
    expect(deleteOf(tester), isNotNull);
  });

  testWidgets('a dropped connection says so and keeps the declaration', (
    tester,
  ) async {
    final h = await deleting(
      tester,
      answer: (_) => throw http.ClientException('down'),
    );

    await tapOn(tester, find.byType(DeclarationRow));
    await tapOn(tester, deleteButton);

    expect(find.text(Copy.genericRetry), findsOneWidget);
    expect(
      tester.widget<DeclarationRow>(find.byType(DeclarationRow)).value,
      isTrue,
    );
    expect(h.location(tester), '/familia/excluir');
  });

  testWidgets('not_owner (ownership passed elsewhere) returns home, which '
      'says only the owner can', (tester) async {
    late Harness h;
    h = await deleting(
      tester,
      answer: (_) {
        h.family = {...ownerFamily, 'role': 'guardian', 'invitations': null};
        return problem(403, 'not_owner');
      },
    );

    await tapOn(tester, find.byType(DeclarationRow));
    await tapOn(tester, deleteButton);

    expect(h.location(tester), '/');
    expect(
      find.text('Só a pessoa titular da família pode fazer isso.'),
      findsOneWidget,
    );
    expect(find.text('Sair da família'), findsOneWidget, reason: 'guardian');
  });

  testWidgets('back returns to the family home', (tester) async {
    final h = await deleting(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/');
  });
}
