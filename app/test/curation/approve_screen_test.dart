import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/approve_screen.dart';
import 'package:telinha_segura/legal/legal_links.dart';
import 'package:telinha_segura/family/profile_fields.dart'
    show SelectableRow, underTwoAdvice;

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

const themes = ['Bichos', 'Música', 'Histórias', 'Aprender', 'Brincar'];
const allThemes = [...themes, 'Natureza'];
const bands = ['2 a 4 anos', '5 a 8 anos', '9 a 12 anos'];

Future<Harness> approving(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? review,
  FutureOr<http.Response> Function()? checklist,
  FutureOr<http.Response> Function(String id)? video,
  String initial = '/curadoria/v1/aprovar',
}) async {
  final h =
      Harness(
          signedIn: true,
          api: curatorApi(review: review, checklist: checklist, video: video),
        )
        ..family = ownerFamily
        ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

Finder row(String label) => find.widgetWithText(SelectableRow, label);

bool chosen(WidgetTester tester, String label) =>
    tester.widget<SelectableRow>(row(label)).selected;

PrimaryButton primary(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton));

Future<void> choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(row(label));
  await tester.pumpAndSettle();
  await tester.tap(row(label));
  await tester.pumpAndSettle();
}

Future<void> tapPrimary(WidgetTester tester, {bool settle = true}) async {
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PrimaryButton));
  await (settle ? tester.pumpAndSettle() : tester.pump());
}

Finder markRow(String label) =>
    find.byWidgetPredicate((w) => w is SelectableRow && w.label == label);

Future<void> mark(WidgetTester tester, String label) async {
  await tester.ensureVisible(markRow(label));
  await tester.pumpAndSettle();
  await tester.tap(markRow(label));
  await tester.pumpAndSettle();
}

/// Answers every group of the fixture's list with nothing marked.
Future<void> clearAll(WidgetTester tester) async {
  for (final label in [
    'Tudo certo neste grupo: Antes de assistir',
    'Nada disso aparece: Violência e medo',
    'Nada disso aparece: Linguagem e respeito',
    'Tudo certo neste grupo: Faixa',
  ]) {
    await mark(tester, label);
  }
}

/// Answers the list, chooses "Música" and "5 a 8 anos" and sends; with
/// [settle] false it leaves the request running.
Future<void> approve(WidgetTester tester, {bool settle = true}) async {
  await clearAll(tester);
  await choose(tester, 'Música');
  await choose(tester, '5 a 8 anos');
  await tapPrimary(tester, settle: settle);
}

List<String> posts(Harness h) =>
    h.actions.where((c) => c.startsWith('POST ')).toList();

int videoReads(Harness h) =>
    h.actions.where((a) => a.startsWith('GET /v1/curation/videos/')).length;

/// The video named under the display title as the review names it: its
/// title in title-medium, then "Canal · 4 min" muted, both above [below].
void expectNamed(WidgetTester tester, Finder below) {
  final title = find.text('Baby Shark');
  final meta = find.text(nb('Canal Baby Shark · 4 min'));
  expect(title, findsOneWidget);
  expect(meta, findsOneWidget);
  final context = tester.element(title);
  expect(
    tester.widget<Text>(title).style?.fontSize,
    Theme.of(context).textTheme.titleMedium?.fontSize,
  );
  final tops = [
    for (final f in [title, meta, below]) tester.getTopLeft(f).dy,
  ];
  expect(tops, [...tops]..sort());
}

void main() {
  testWidgets('says every video must be Livre and opens the criteria of '
      'each band on the site', (tester) async {
    final h = await approving(tester);

    expect(find.text(curationRule), findsOneWidget);
    await tester.ensureVisible(find.text(curationCriteriaLink));
    await tester.pumpAndSettle();
    await tester.tap(find.text(curationCriteriaLink));
    await tester.pumpAndSettle();

    expect(h.links.opened, [kCurationUrl]);
    expect(h.location(tester), '/curadoria/v1/aprovar');
  });

  testWidgets('the criteria line reads as a link', (tester) async {
    final semantics = tester.ensureSemantics();
    await approving(tester);
    await tester.ensureVisible(find.text(curationCriteriaLink));
    await tester.pumpAndSettle();

    expect(
      find.semantics.byPredicate(
        (n) => n.label == curationCriteriaLink && n.flagsCollection.isLink,
      ),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('a curator choosing "2 a 4 anos" sees no advice meant for '
      'guardians', (tester) async {
    await approving(tester);
    await choose(tester, '2 a 4 anos');

    expect(find.text(underTwoAdvice), findsNothing);
  });

  testWidgets('names the video it approves under the title, as the review '
      'does, through to the done state', (tester) async {
    await approving(tester);

    expectNamed(tester, find.text(checklistLead));
    await approve(tester);
    expectNamed(tester, find.text(approved));
  });

  testWidgets('opened from the review, it names the video without reading '
      'it again', (tester) async {
    final h = await approving(tester, initial: '/curadoria/v1');

    await tester.ensureVisible(find.text('Responder às perguntas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Responder às perguntas'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria/v1/aprovar');
    expectNamed(tester, find.text(checklistLead));
    expect(videoReads(h), 1);
  });

  testWidgets('offers the six themes and the three bands, none chosen; '
      'the primary waits with its hint', (tester) async {
    await approving(tester);

    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('A partir de'), findsOneWidget);
    for (final label in [...allThemes, ...bands]) {
      expect(row(label), findsOneWidget, reason: label);
      expect(chosen(tester, label), isFalse, reason: label);
    }
    expect(primary(tester).label, 'Aprovar');
    expect(primary(tester).onPressed, isNull);
    expect(find.text(checklistHint), findsOneWidget);
    await clearAll(tester);
    expect(find.text(approveHint), findsOneWidget);
  });

  testWidgets('the primary waits until both are chosen, one of each', (
    tester,
  ) async {
    await approving(tester);
    await clearAll(tester);

    await choose(tester, 'Bichos');
    await choose(tester, 'Música');
    expect(chosen(tester, 'Bichos'), isFalse);
    expect(chosen(tester, 'Música'), isTrue);
    expect(primary(tester).onPressed, isNull);

    await choose(tester, '9 a 12 anos');
    expect(primary(tester).onPressed, isNotNull);
    final hint = tester.widget<Visibility>(
      find.ancestor(
        of: find.text(approveHint),
        matching: find.byType(Visibility),
      ),
    );
    expect(hint.visible, isFalse);
  });

  testWidgets('every choice is a radio', (tester) async {
    final semantics = tester.ensureSemantics();
    await approving(tester);

    expect(
      tester.getSemantics(row('Natureza')),
      isSemantics(
        label: 'Natureza',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a mark on a question is a checkbox, taken back by a second '
      'tap; a group\'s "nothing appears" stays a radio', (tester) async {
    final semantics = tester.ensureSemantics();
    await approving(tester);
    const label = 'Aparece: Alguém bate de propósito?';

    expect(
      tester.getSemantics(markRow(label)),
      isSemantics(
        label: label,
        isInMutuallyExclusiveGroup: false,
        hasCheckedState: true,
        isChecked: false,
      ),
    );
    await mark(tester, label);
    expect(
      tester.getSemantics(markRow(label)),
      isSemantics(
        label: label,
        isInMutuallyExclusiveGroup: false,
        hasCheckedState: true,
        isChecked: true,
      ),
    );
    await mark(tester, label);
    expect(tester.getSemantics(markRow(label)), isSemantics(isChecked: false));
    expect(
      tester.getSemantics(markRow('Nada disso aparece: Violência e medo')),
      isSemantics(
        label: 'Nada disso aparece: Violência e medo',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('sends the approval once and shows the done state, back to '
      'the queue', (tester) async {
    final answer = Completer<http.Response>();
    final h = await approving(tester, review: (_) => answer.future);

    await approve(tester, settle: false);
    await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
    await tester.pump();
    answer.complete(json(201, {'video_state': 'pending'}));
    await tester.pumpAndSettle();

    expect(posts(h), hasLength(1));
    expect(jsonDecode(posts(h).single.split(' ').skip(2).join(' ')), {
      'decision': 'approve',
      'theme': 'musica',
      'min_age_band': '5-8',
      'checklist_version': '2026-10-20',
      'answers': {
        'c01': 'ok',
        'c25': 'ok',
        'c04': 'ok',
        'c07': 'ok',
        'c21': 'ok',
        'c22': 'ok',
      },
    });
    expect(posts(h).single, startsWith('POST /v1/curation/videos/v1/reviews'));
    expect(find.widgetWithText(Notice, approved), findsOneWidget);
    expect(row('Música'), findsNothing, reason: 'the form is gone');

    await tester.tap(find.text('Voltar para a fila'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/curadoria');
  });

  testWidgets('a network failure keeps the choices, and the primary tries '
      'again', (tester) async {
    var fail = true;
    final h = await approving(
      tester,
      review: (_) => fail
          ? problem(503, 'unavailable')
          : json(201, {'video_state': 'approved'}),
    );

    await approve(tester);

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(chosen(tester, 'Música'), isTrue);
    expect(chosen(tester, '5 a 8 anos'), isTrue);
    fail = false;
    await tapPrimary(tester);
    expect(posts(h), hasLength(2));
    expect(find.text(approved), findsOneWidget);
  });

  testWidgets('validation marks the choices, cleared to choose again', (
    tester,
  ) async {
    await approving(tester, review: (_) => problem(422, 'validation'));

    await approve(tester);

    expect(find.text(approvalRefused), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
    expect(chosen(tester, 'Música'), isFalse);
    expect(chosen(tester, '5 a 8 anos'), isFalse);
    expect(primary(tester).onPressed, isNull);

    await choose(tester, 'Bichos');
    expect(find.text(approvalRefused), findsNothing);
  });

  for (final (code, status, notice) in [
    ('already_reviewed', 409, 'Esse vídeo já saiu da fila.'),
    ('not_reviewable', 409, 'Esse vídeo já saiu da fila.'),
    (
      'own_suggestion',
      403,
      'Você sugeriu esse vídeo, então a revisão dele fica com outros '
          'curadores.',
    ),
    ('not_found', 404, 'Esse vídeo não está mais na curadoria.'),
  ]) {
    testWidgets('$code goes back to the queue, read again, with a notice', (
      tester,
    ) async {
      final h = await approving(tester, review: (_) => problem(status, code));

      await approve(tester);

      expect(h.location(tester), '/curadoria');
      expect(find.text(notice), findsOneWidget);
      expect(
        h.actions.where((c) => c.startsWith('GET /v1/curation/queue')),
        hasLength(1),
      );
    });
  }

  testWidgets('not_curator goes home with a notice', (tester) async {
    final h = await approving(
      tester,
      review: (_) => problem(403, 'not_curator'),
    );

    await approve(tester);

    expect(h.location(tester), '/');
    expect(find.text('Você não faz mais parte da curadoria.'), findsOneWidget);
  });

  testWidgets('reads the list group by group, "Nada disso aparece" answering '
      'a group, with "Aparece" and "Tenho dúvida" on each question', (
    tester,
  ) async {
    await approving(tester);

    for (final title in [
      'Antes de assistir',
      'Violência e medo',
      'Linguagem e respeito',
      'Faixa',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(markRow('Aparece: Alguém bate de propósito?'), findsOneWidget);
    expect(markRow('Tenho dúvida: Alguém bate de propósito?'), findsOneWidget);
    expect(
      markRow('Não: Ritmo calmo?'),
      findsOneWidget,
      reason: 'a question asked in the positive is marked "Não"',
    );
    expect(primary(tester).onPressed, isNull);
    await clearAll(tester);
    await choose(tester, 'Bichos');
    await choose(tester, '5 a 8 anos');
    expect(primary(tester).label, 'Aprovar');
    expect(primary(tester).onPressed, isNotNull);
  });

  testWidgets('a question that refuses leads to the refusal with it '
      'marked, and sends nothing', (tester) async {
    final h = await approving(tester);

    await mark(tester, 'Aparece: Alguém bate de propósito?');
    expect(find.text(refusingLine), findsOneWidget);
    expect(primary(tester).label, 'Ir para a recusa');
    await tapPrimary(tester);

    expect(h.location(tester), '/curadoria/v1/recusar?itens=c04');
    expect(posts(h), isEmpty);
  });

  testWidgets('a doubt is sent as one, with its note, and says the team '
      'decides', (tester) async {
    final h = await approving(
      tester,
      review: (_) => json(201, {'video_state': 'held'}),
    );

    await clearAll(tester);
    await mark(tester, 'Tenho dúvida: Algum personagem fica triste?');
    expect(find.text(doubtLine), findsOneWidget);
    expect(find.text(doubtRevisitLine), findsNothing);
    await choose(tester, 'Música');
    await choose(tester, '5 a 8 anos');
    await tester.enterText(
      find.widgetWithText(TextField, doubtNoteLabel),
      '  A tristeza é o tema.  ',
    );
    await tester.pump();
    expect(primary(tester).label, 'Enviar dúvida');
    await tapPrimary(tester);

    final body = jsonDecode(
      posts(h).single.split(' ').skip(2).join(' '),
    ) as Map<String, dynamic>;
    expect((body['answers'] as Map)['c07'], 'doubt');
    expect(body['note'], 'A tristeza é o tema.');
    expect(find.widgetWithText(Notice, doubtSent), findsOneWidget);
  });

  testWidgets('a tie to the channel says so and goes back to the queue, '
      'sending nothing', (tester) async {
    final h = await approving(tester);

    await mark(tester, 'Aparece: Você tem vínculo com este canal?');
    expect(find.text(conflictLine), findsOneWidget);
    expect(primary(tester).label, 'Voltar para a fila');
    await tapPrimary(tester);

    expect(h.location(tester), '/curadoria');
    expect(posts(h), isEmpty);
  });

  testWidgets('an invalid reason waits until it is unmarked', (tester) async {
    await approving(tester);

    await clearAll(tester);
    await mark(tester, 'Aparece: Você recusaria só pela diferença?');
    await choose(tester, 'Música');
    await choose(tester, '5 a 8 anos');
    expect(find.text(invalidReasonLine), findsOneWidget);
    expect(primary(tester).onPressed, isNull);

    await mark(tester, 'Aparece: Você recusaria só pela diferença?');
    expect(find.text(invalidReasonLine), findsNothing);
    await mark(tester, 'Nada disso aparece: Linguagem e respeito');
    expect(primary(tester).label, 'Aprovar');
    expect(primary(tester).onPressed, isNotNull);
  });

  testWidgets('an invalid reason is said with a question that refuses too', (
    tester,
  ) async {
    await approving(tester);

    await mark(tester, 'Aparece: Alguém bate de propósito?');
    await mark(tester, 'Aparece: Você recusaria só pela diferença?');

    expect(find.text(refusingLine), findsOneWidget);
    expect(find.text(invalidReasonLine), findsOneWidget);
  });

  testWidgets('a note written for a doubt taken back is not sent with the '
      'approval', (tester) async {
    final h = await approving(
      tester,
      review: (_) => json(201, {'video_state': 'pending'}),
    );

    await clearAll(tester);
    await mark(tester, 'Tenho dúvida: Algum personagem fica triste?');
    await tester.enterText(
      find.widgetWithText(TextField, doubtNoteLabel),
      'Pensei melhor.',
    );
    await tester.pump();
    await mark(tester, 'Nada disso aparece: Violência e medo');
    await choose(tester, 'Música');
    await choose(tester, '5 a 8 anos');
    expect(primary(tester).label, 'Aprovar');
    await tapPrimary(tester);

    final body = jsonDecode(
      posts(h).single.split(' ').skip(2).join(' '),
    ) as Map<String, dynamic>;
    expect(body.containsKey('note'), isFalse);
    expect(find.widgetWithText(Notice, approved), findsOneWidget);
  });

  testWidgets('a doubt on a revisited video says it leaves the app until '
      'the team decides', (tester) async {
    await approving(
      tester,
      video: (id) => detailOf({
        ...queuedJson(id, 'Baby Shark', channel: 'Canal Baby Shark'),
        'state': 'approved',
        'round': 2,
      }),
    );

    await clearAll(tester);
    await mark(tester, 'Tenho dúvida: Algum personagem fica triste?');

    expect(find.text(doubtRevisitLine), findsOneWidget);
    expect(find.text(doubtLine), findsNothing);
  });

  testWidgets('a fast pace rules out "2 a 4 anos" only', (tester) async {
    await approving(tester);

    await clearAll(tester);
    await mark(tester, 'Não: Ritmo calmo?');
    await choose(tester, 'Música');
    await choose(tester, '2 a 4 anos');
    expect(find.text(bandLine), findsOneWidget);
    expect(primary(tester).onPressed, isNull);

    await choose(tester, '5 a 8 anos');
    expect(find.text(bandLine), findsNothing);
    expect(primary(tester).onPressed, isNotNull);
  });

  testWidgets('checklist_outdated reads the list again and says why', (
    tester,
  ) async {
    final h = await approving(
      tester,
      review: (_) => problem(409, 'checklist_outdated'),
    );

    await approve(tester);

    expect(
      find.widgetWithText(
        ErrorNote,
        Copy.forError(const ApiError(status: 409, code: 'checklist_outdated')),
      ),
      findsOneWidget,
    );
    expect(
      h.actions.where((a) => a == 'GET /v1/curation/checklist'),
      hasLength(2),
    );
  });

  testWidgets('checklist_outdated whose new list fails to read offers to '
      'try again, never the old list', (tester) async {
    var reads = 0;
    final h = await approving(
      tester,
      checklist: () =>
          ++reads == 2 ? problem(503, 'unavailable') : json(200, checklistJson),
      review: (_) => problem(409, 'checklist_outdated'),
    );

    await approve(tester);

    expect(find.byType(SelectableRow), findsNothing);
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    await tapPrimary(tester);

    expect(reads, 3);
    expect(posts(h), hasLength(1));
    expect(find.text(checklistLead), findsOneWidget);
    expect(primary(tester).onPressed, isNull, reason: 'a new list unanswered');
    expect(find.text(checklistHint), findsOneWidget);
  });

  testWidgets('conflict_of_interest goes back to the queue with a notice', (
    tester,
  ) async {
    final h = await approving(
      tester,
      review: (_) => problem(409, 'conflict_of_interest'),
    );

    await approve(tester);

    expect(h.location(tester), '/curadoria');
    expect(
      find.text(
        'Você tem vínculo com este canal, então a revisão dele fica com '
        'outros curadores.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('back returns to the review', (tester) async {
    final h = await approving(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria/v1');
  });
}
