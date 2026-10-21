import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/audit_video_screen.dart'
    show marksFailed;
import 'package:telinha_segura/curation/held_video_screen.dart';
import 'package:telinha_segura/curation/publish_doubt_screen.dart';
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'appoint_screen_test.dart' show tapOn;
import 'fixtures.dart';
import 'held_video_screen_test.dart' show confirming, writes;

final doubted = heldOf(
  queuedJson('v1', 'Baby Shark', channel: 'Canal Baby Shark'),
  reason: 'doubt',
  doubts: [doubtJson],
);

Future<Harness> doubtHeld(
  WidgetTester tester, {
  String initial = '/moderacao/retidos/v1',
  FutureOr<http.Response> Function(http.Request)? settle,
  FutureOr<http.Response> Function()? checklist,
}) async {
  final h =
      Harness(
          signedIn: true,
          api: adminApi(
            held: () => heldList([doubted]),
            settle: settle,
            checklist: checklist,
          ),
        )
        ..family = ownerFamily
        ..roles = ['admin'];
  await h.pump(tester, initial: initial);
  return h;
}

Finder row(String label) => find.widgetWithText(SelectableRow, label);

void main() {
  testWidgets('a doubt shows why, who doubted with the note, and what was '
      'marked; the actions are "Publicar" and "Remover de vez"', (
    tester,
  ) async {
    await doubtHeld(tester);

    expect(find.text('Retido por dúvida da curadoria'), findsOneWidget);
    expect(find.text(doubtsHeading), findsOneWidget);
    for (final line in [
      nb('Mãe ou pai teve dúvida · Bichos · 5 a 8 anos'),
      '“Não sei se a tristeza pesa.”',
      'Aparece: Algum personagem fica triste?',
      'Tenho dúvida: Ritmo calmo?',
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(find.widgetWithText(FilledButton, 'Publicar'), findsOneWidget);
    expect(find.widgetWithText(QuietAction, 'Remover de vez'), findsOneWidget);
    expect(find.text('Reabrir para revisão'), findsNothing);
  });

  testWidgets('a failed read of the questions still shows the doubt, says '
      'the answers could not be read and retries them', (tester) async {
    var reads = 0;
    await doubtHeld(
      tester,
      checklist: () =>
          ++reads == 1 ? problem(503, 'unavailable') : json(200, checklistJson),
    );

    expect(find.text('Retido por dúvida da curadoria'), findsOneWidget);
    expect(
      find.text(nb('Mãe ou pai teve dúvida · Bichos · 5 a 8 anos')),
      findsOneWidget,
    );
    expect(find.text(marksFailed), findsOneWidget);
    expect(find.text('Aparece: Algum personagem fica triste?'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Publicar'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(QuietAction, 'Tentar de novo'));

    expect(reads, 2);
    expect(find.text(marksFailed), findsNothing);
    expect(find.text('Aparece: Algum personagem fica triste?'), findsOneWidget);
  });

  testWidgets('"Publicar" shows the doubts and starts from the theme and '
      'band the curator chose', (tester) async {
    await doubtHeld(tester);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(
      find.text(nb('Mãe ou pai teve dúvida · Bichos · 5 a 8 anos')),
      findsOneWidget,
    );
    expect(tester.widget<SelectableRow>(row('Bichos')).selected, isTrue);
    expect(tester.widget<SelectableRow>(row('5 a 8 anos')).selected, isTrue);
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      'Sem risco no vídeo.',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Publicar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('"Publicar" opened directly starts from the curator\'s choice '
      'too', (tester) async {
    await doubtHeld(tester, initial: '/moderacao/retidos/v1/publicar');

    expect(tester.widget<SelectableRow>(row('Bichos')).selected, isTrue);
    expect(tester.widget<SelectableRow>(row('5 a 8 anos')).selected, isTrue);
  });

  testWidgets('"Publicar" asks a theme, a band and a reason, publishes once '
      'and goes back to the list', (tester) async {
    final h = await doubtHeld(tester);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));
    expect(h.location(tester), '/moderacao/retidos/v1/publicar');
    expect(find.text(publishLead), findsOneWidget);
    await tapOn(tester, row('Natureza'));
    await tapOn(tester, row('2 a 4 anos'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      '  Sem risco no vídeo. ',
    );
    await tester.pump();
    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(writes(h), hasLength(1));
    expect(
      writes(h).single,
      startsWith('POST /v1/moderation/videos/v1/decide'),
    );
    expect(jsonDecode(writes(h).single.split(' ').skip(2).join(' ')), {
      'decision': 'approve',
      'theme': 'natureza',
      'min_age_band': 'ate-4',
      'reason': 'Sem risco no vídeo.',
    });
    expect(h.location(tester), '/moderacao/retidos');
    expect(find.text(publishedFromDoubt('Baby Shark')), findsOneWidget);
  });

  testWidgets('reason_required marks the reason', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      settle: (_) => problem(422, 'reason_required'),
    );

    await tapOn(tester, row('Música'));
    await tapOn(tester, row('5 a 8 anos'));
    await tester.enterText(find.widgetWithText(TextField, 'Motivo'), 'ok');
    await tester.pump();
    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Motivo'))
          .decoration
          ?.errorText,
      publishReasonInvalid,
    );
  });

  testWidgets('"Remover de vez" confirms with "Motivo" and removes through '
      'the decision', (tester) async {
    final h = await doubtHeld(tester);

    await tapOn(tester, find.widgetWithText(QuietAction, 'Remover de vez'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      '  Desafio perigoso. ',
    );
    await tester.pump();
    await tapOn(tester, confirming('Remover de vez'));

    expect(writes(h), [
      'POST /v1/moderation/videos/v1/decide {"decision":"reject","reason":"Desafio perigoso."}',
    ]);
    expect(h.location(tester), '/moderacao/retidos');
    expect(find.text(removedForGood('Baby Shark')), findsOneWidget);
  });

  testWidgets('state_conflict goes back to the list', (tester) async {
    final h = await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      settle: (_) => problem(409, 'state_conflict'),
    );

    await tapOn(tester, row('Música'));
    await tapOn(tester, row('5 a 8 anos'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      'Motivo válido.',
    );
    await tester.pump();
    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(h.location(tester), '/moderacao/retidos');
    expect(find.text(heldGone), findsOneWidget);
  });

  testWidgets('own_review keeps the screen usable', (tester) async {
    final h = await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      settle: (_) => problem(409, 'own_review'),
    );

    await tapOn(tester, row('Música'));
    await tapOn(tester, row('5 a 8 anos'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      'Motivo válido.',
    );
    await tester.pump();
    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(h.location(tester), '/moderacao/retidos/v1/publicar');
    expect(
      find.text(Copy.forError(ApiError(status: 409, code: 'own_review'))),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Publicar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a video held by an audit shows its verdict and reason', (
    tester,
  ) async {
    final h =
        Harness(
            signedIn: true,
            api: adminApi(
              held: () => heldList([
                heldOf(
                  queuedJson('v1', 'Baby Shark'),
                  reason: 'audit',
                  audit: auditJson,
                ),
              ]),
            ),
          )
          ..family = ownerFamily
          ..roles = ['admin'];
    await h.pump(tester, initial: '/moderacao/retidos/v1');

    expect(find.text('Retido pela auditoria'), findsOneWidget);
    expect(find.text('Auditoria: discordou \u2014 Tem publi.'), findsOneWidget);
    expect(find.text('Reabrir para revisão'), findsOneWidget);
  });
}
