import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/approve_screen.dart'
    show notPlayedToEnd, playedToEnd, tooLongForYoungestLine;
import 'package:telinha_segura/curation/audit_video_screen.dart'
    show marksFailed;
import 'package:telinha_segura/curation/held_video_screen.dart';
import 'package:telinha_segura/curation/publish_doubt_screen.dart';
import 'package:telinha_segura/curation/curation.dart' show VideoTheme;
import 'package:telinha_segura/curation/words.dart' show VideoThemeLabel;
import 'package:telinha_segura/family/family.dart' show AgeBand;
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;
import 'package:telinha_segura/kid/kid_player.dart' show PlayerEnded;

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../kid/fake_player.dart';
import 'appoint_screen_test.dart' show tapOn;
import 'fixtures.dart';
import 'held_video_screen_test.dart' show confirming, writes;
import 'queue_screen_test.dart' show goTo;

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
  Map<String, Object?>? held,
}) async {
  final h =
      Harness(
          signedIn: true,
          api: adminApi(
            held: () => heldList([held ?? doubted]),
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

const endedPath = 'POST /v1/moderation/videos/v1/ended';

/// The writes by method and path, without their bodies.
List<String> writePaths(Harness h) => [
  for (final w in writes(h)) w.split(' ').take(2).join(' '),
];

/// From the held screen, "Publicar" with the curator's theme and band and
/// a reason.
Future<void> publishFromHeld(WidgetTester tester) async {
  await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));
  await tester.enterText(
    find.widgetWithText(TextField, 'Motivo'),
    'Sem risco no vídeo.',
  );
  await tester.pump();
  await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));
}

/// A scripted end report: [fail] answers 503 while it returns true; every
/// other moderation write answers 204.
FutureOr<http.Response> Function(http.Request) endedThen(
  bool Function() fail,
) =>
    (req) => req.url.path.endsWith('/ended') && fail()
    ? problem(503, 'unavailable')
    : http.Response('', 204);

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
      'Sim: Algum personagem fica triste?',
      'Não sei: Tem ritmo agitado?',
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
    expect(find.text('Sim: Algum personagem fica triste?'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Publicar'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(QuietAction, 'Tentar de novo'));

    expect(reads, 2);
    expect(find.text(marksFailed), findsNothing);
    expect(find.text('Sim: Algum personagem fica triste?'), findsOneWidget);
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
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).selected,
      isTrue,
    );
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
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).selected,
      isTrue,
    );
  });

  testWidgets('"Publicar" asks a theme, a band and a reason, publishes once '
      'and goes back to the list', (tester) async {
    final h = await doubtHeld(tester);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));
    expect(h.location(tester), '/moderacao/retidos/v1/publicar');
    expect(find.text(publishLead), findsOneWidget);
    await tapOn(tester, row('Natureza'));
    await tapOn(tester, row('2\u00A0a\u00A04\u00A0anos'));
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

  testWidgets('"Publicar" keeps "2 a 4 anos" from a video past 60 minutes '
      'and says why', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      held: heldOf(
        queuedJson('v1', 'Baby Shark', seconds: 61 * 60),
        reason: 'doubt',
        doubts: [
          {...doubtJson, 'min_age_band': 'ate-4'},
        ],
      ),
    );

    expect(
      tester.widget<SelectableRow>(row('2\u00A0a\u00A04\u00A0anos')).onTap,
      isNull,
    );
    expect(
      tester.widget<SelectableRow>(row('2\u00A0a\u00A04\u00A0anos')).selected,
      isFalse,
      reason: 'the curator\'s choice is not kept',
    );
    expect(find.text(tooLongForYoungestLine), findsOneWidget);
    expect(find.textContaining('Pelas respostas'), findsNothing);
  });

  testWidgets('"Publicar" keeps out the bands younger than the answers '
      'allow and says why', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      held: heldOf(
        queuedJson('v1', 'Baby Shark'),
        reason: 'doubt',
        doubts: [doubtJson],
        computedBand: '9-12',
      ),
    );

    expect(
      tester.widget<SelectableRow>(row('2\u00A0a\u00A04\u00A0anos')).onTap,
      isNull,
    );
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).onTap,
      isNull,
    );
    expect(
      tester.widget<SelectableRow>(row('9\u00A0a\u00A012\u00A0anos')).onTap,
      isNotNull,
    );
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).selected,
      isFalse,
      reason: 'the curator\'s choice is not kept',
    );
    expect(find.text(roundBandStatement(AgeBand.from9To12)), findsOneWidget);
    expect(find.text(tooLongForYoungestLine), findsNothing);
  });

  testWidgets('"Publicar" states the band the round\'s answers give and the '
      'answers behind it, by who gave them, above the themes, with no way to '
      'change them', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      held: heldOf(
        queuedJson('v1', 'Baby Shark'),
        reason: 'doubt',
        doubts: [doubtJson],
        computedBand: '9-12',
        bandAnswers: [
          {
            'text': 'Tem ritmo agitado?',
            'answer': 'doubt',
            'display_role': 'mae-pai',
          },
          {
            'text': 'Tem namoro entre os personagens?',
            'answer': 'appears',
            'display_role': 'pedagogo',
          },
        ],
      ),
    );

    expect(
      roundBandStatement(AgeBand.from9To12),
      'Pelas respostas da rodada, este vídeo serve a partir de 9\u00A0a\u00A012\u00A0anos',
    );
    final statement = find.text(roundBandStatement(AgeBand.from9To12));
    expect(statement, findsOneWidget);
    final fast = find.text(
      'Tem ritmo agitado? —\u00A0Não\u00A0sei',
      findRichText: true,
    );
    final dating = find.text(
      'Tem namoro entre os personagens? —\u00A0Sim',
      findRichText: true,
    );
    expect(fast, findsOneWidget);
    expect(dating, findsOneWidget);
    expect(find.text('Mãe ou pai respondeu'), findsOneWidget);
    expect(find.text('Pedagogo(a) respondeu'), findsOneWidget);
    expect(find.text('mudar'), findsNothing);
    final y = tester.getTopLeft;
    expect(y(statement).dy < y(fast).dy, isTrue);
    expect(y(fast).dy < y(dating).dy, isTrue);
    expect(y(dating).dy < y(find.text('Tema')).dy, isTrue);
    expect(
      find.text(
        'Pelas respostas, este vídeo serve a partir de 9\u00A0a\u00A012\u00A0anos.',
      ),
      findsNothing,
    );
  });

  testWidgets('"Publicar" shows each theme with its meaning', (tester) async {
    await doubtHeld(tester, initial: '/moderacao/retidos/v1/publicar');

    for (final t in VideoTheme.values) {
      if (t == VideoTheme.unknown) continue;
      expect(find.text(t.definition!), findsOneWidget, reason: t.label);
    }
  });

  testWidgets('"Publicar" over a long video whose answers bar nothing says '
      'the length does', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      held: heldOf(
        queuedJson('v1', 'Baby Shark', seconds: 61 * 60),
        reason: 'doubt',
        doubts: [doubtJson],
        computedBand: '5-8',
        bandAnswers: const [],
      ),
    );

    expect(find.text(roundBandStatement(AgeBand.from5To8)), findsOneWidget);
    expect(find.text(tooLongForYoungestLine), findsOneWidget);
  });

  testWidgets('"Publicar" over a round whose answers allow every band states '
      'it, with no answer under it', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      held: heldOf(
        queuedJson('v1', 'Baby Shark'),
        reason: 'doubt',
        doubts: [doubtJson],
        computedBand: 'ate-4',
      ),
    );

    expect(
      tester.widget<SelectableRow>(row('2\u00A0a\u00A04\u00A0anos')).onTap,
      isNotNull,
    );
    expect(find.text(roundBandStatement(AgeBand.upTo4)), findsOneWidget);
    expect(find.textContaining('respondeu'), findsNothing);
  });

  testWidgets('checklist_band says why and takes "2 a 4 anos" away', (
    tester,
  ) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      settle: (_) => problem(422, 'checklist_band'),
    );

    await tapOn(tester, row('2\u00A0a\u00A04\u00A0anos'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      'Motivo válido.',
    );
    await tester.pump();
    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(
      find.text(Copy.forError(ApiError(status: 422, code: 'checklist_band'))),
      findsOneWidget,
    );
    expect(
      tester.widget<SelectableRow>(row('2\u00A0a\u00A04\u00A0anos')).selected,
      isFalse,
    );
    expect(
      tester.widget<SelectableRow>(row('2\u00A0a\u00A04\u00A0anos')).onTap,
      isNull,
    );
  });

  testWidgets('checklist_band on "5 a 8 anos" takes it and every younger '
      'band away', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      settle: (_) => problem(422, 'checklist_band'),
    );

    // The doubt's own choice, "5 a 8 anos", starts chosen.
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).selected,
      isTrue,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      'Motivo válido.',
    );
    await tester.pump();
    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).selected,
      isFalse,
    );
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).onTap,
      isNull,
    );
    expect(
      tester.widget<SelectableRow>(row('2\u00A0a\u00A04\u00A0anos')).onTap,
      isNull,
    );
    expect(
      tester.widget<SelectableRow>(row('9\u00A0a\u00A012\u00A0anos')).onTap,
      isNotNull,
    );
  });

  testWidgets('reason_required marks the reason', (tester) async {
    await doubtHeld(
      tester,
      initial: '/moderacao/retidos/v1/publicar',
      settle: (_) => problem(422, 'reason_required'),
    );

    await tapOn(tester, row('Música'));
    await tapOn(tester, row('5\u00A0a\u00A08\u00A0anos'));
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
    await tapOn(tester, row('5\u00A0a\u00A08\u00A0anos'));
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
    await tapOn(tester, row('5\u00A0a\u00A08\u00A0anos'));
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

  testWidgets('a doubt sent without a theme or a band reads without them, '
      'and "Publicar" starts with none chosen', (tester) async {
    final h =
        Harness(
            signedIn: true,
            api: adminApi(
              held: () => heldList([
                heldOf(
                  queuedJson('v1', 'Baby Shark', channel: 'Canal Baby Shark'),
                  reason: 'doubt',
                  doubts: [
                    {...doubtJson, 'theme': null, 'min_age_band': null},
                  ],
                ),
              ]),
            ),
          )
          ..family = ownerFamily
          ..roles = ['admin'];
    await h.pump(tester, initial: '/moderacao/retidos/v1');

    expect(find.text('Mãe ou pai teve dúvida'), findsOneWidget);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Publicar'));

    expect(tester.widget<SelectableRow>(row('Bichos')).selected, isFalse);
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).selected,
      isFalse,
    );
  });

  testWidgets('a video held by a doubt says under the window whether it '
      'played to its end', (tester) async {
    final h = await doubtHeld(tester);
    final line = find.text(notPlayedToEnd);
    expect(line, findsOneWidget);
    expect(
      tester.getTopLeft(line).dy,
      greaterThan(tester.getBottomLeft(find.byKey(FakePlayback.viewKey)).dy),
    );

    h.adultPlayer.opened.last.emit(const PlayerEnded());
    await tester.pumpAndSettle();

    expect(find.text(playedToEnd), findsOneWidget);
    expect(find.text(notPlayedToEnd), findsNothing);
  });

  testWidgets('a video held for another reason has no such line', (
    tester,
  ) async {
    await doubtHeld(
      tester,
      held: heldOf(queuedJson('v1', 'Baby Shark'), reason: 'reports'),
    );

    expect(find.text(notPlayedToEnd), findsNothing);
    expect(find.text(playedToEnd), findsNothing);
  });

  testWidgets('the held screen tells the server when the video played to '
      'its end', (tester) async {
    final h = await doubtHeld(tester);
    expect(writes(h), isEmpty);

    h.adultPlayer.opened.last.emit(const PlayerEnded());
    await tester.pumpAndSettle();

    expect(writes(h), [endedPath]);
  });

  testWidgets('an end report that failed is sent again before publishing', (
    tester,
  ) async {
    var fail = true;
    final h = await doubtHeld(tester, settle: endedThen(() => fail));
    h.adultPlayer.opened.last.emit(const PlayerEnded());
    await tester.pumpAndSettle();
    expect(writes(h), [endedPath]);
    fail = false;

    await publishFromHeld(tester);

    expect(writePaths(h), [
      endedPath,
      endedPath,
      'POST /v1/moderation/videos/v1/decide',
    ]);
    expect(find.text(publishedFromDoubt('Baby Shark')), findsOneWidget);
  });

  testWidgets('an end reported is not sent again before publishing', (
    tester,
  ) async {
    final h = await doubtHeld(tester);
    h.adultPlayer.opened.last.emit(const PlayerEnded());
    await tester.pumpAndSettle();

    await publishFromHeld(tester);

    expect(writePaths(h), [endedPath, 'POST /v1/moderation/videos/v1/decide']);
  });

  testWidgets('an end another account saw is never sent for the next one', (
    tester,
  ) async {
    final h = await doubtHeld(tester, settle: endedThen(() => true));
    h.adultPlayer.opened.last.emit(const PlayerEnded());
    await tester.pumpAndSettle();
    expect(writes(h), [endedPath]);

    await h.services.client.forgetSession();
    await tester.pumpAndSettle();
    h.email = 'bia@example.com';
    h.services.client.rememberSession(csrfToken: 'csrf-b');
    await tester.pumpAndSettle();
    goTo(tester, '/moderacao/retidos/v1');
    await tester.pumpAndSettle();
    await publishFromHeld(tester);

    expect(writePaths(h), [endedPath, 'POST /v1/moderation/videos/v1/decide']);
  });

  testWidgets('a publication refused for a video not watched to the end '
      'says so and keeps what was chosen', (tester) async {
    final h = await doubtHeld(
      tester,
      settle: (req) => req.url.path.endsWith('/decide')
          ? problem(409, 'not_watched')
          : http.Response('', 204),
    );

    await publishFromHeld(tester);

    expect(writePaths(h), ['POST /v1/moderation/videos/v1/decide']);
    expect(h.location(tester), '/moderacao/retidos/v1/publicar');
    expect(find.text(publishNotWatched), findsOneWidget);
    expect(
      publishNotWatched,
      'Para publicar, o vídeo precisa tocar até o fim. Volte, assista até o '
      'fim e publique de novo.',
    );
    expect(
      find.text(
        Copy.forError(const ApiError(status: 409, code: 'not_watched')),
      ),
      findsNothing,
    );
    expect(tester.widget<SelectableRow>(row('Bichos')).selected, isTrue);
    expect(
      tester.widget<SelectableRow>(row('5\u00A0a\u00A08\u00A0anos')).selected,
      isTrue,
    );
    expect(find.text('Sem risco no vídeo.'), findsOneWidget);
  });
}
