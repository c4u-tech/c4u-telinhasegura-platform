import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/refuse_screen.dart';
import 'package:telinha_segura/curation/words.dart' show differenceReminder;

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'approve_screen_test.dart'
    show expectNamed, posts, primary, tapPrimary, videoReads;
import 'fixtures.dart';

Future<Harness> refusing(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? review,
  FutureOr<http.Response> Function()? checklist,
  String initial = '/curadoria/v1/recusar',
}) async {
  final h =
      Harness(
          signedIn: true,
          api: curatorApi(review: review, checklist: checklist),
        )
        ..family = ownerFamily
        ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

Finder get field => find.widgetWithText(TextField, refuseNoteLabel);

Finder item(String text) => find.widgetWithText(DeclarationRow, text);

bool ticked(WidgetTester tester, String text) =>
    tester.widget<DeclarationRow>(item(text)).value;

String? fieldError(WidgetTester tester) =>
    tester.widget<TextField>(field).decoration?.errorText;

Future<void> type(WidgetTester tester, String note) async {
  await tester.enterText(field, note);
  await tester.pump();
}

Future<void> tick(WidgetTester tester, String text) async {
  await tester.ensureVisible(item(text));
  await tester.pumpAndSettle();
  await tester.tap(item(text));
  await tester.pumpAndSettle();
}

/// Ticks "Alguém bate de propósito?", writes [reason] as the note and
/// sends; with [settle] false it leaves the request running.
Future<void> refuse(
  WidgetTester tester, {
  String reason = 'Tem um susto no fim.',
  bool settle = true,
}) async {
  await tick(tester, 'Alguém bate de propósito?');
  await type(tester, reason);
  await tapPrimary(tester, settle: settle);
}

void main() {
  testWidgets('names the video it refuses under the title, as the review '
      'does, through to the done state', (tester) async {
    await refusing(tester);

    expectNamed(tester, find.text(refuseLead));
    await refuse(tester);
    expectNamed(tester, find.text(refused));
  });

  testWidgets('opened from the review, it names the video without reading '
      'it again', (tester) async {
    final h = await refusing(tester, initial: '/curadoria/v1');

    await tester.ensureVisible(find.text('Marcar o que acontece'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar o que acontece'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria/v1/recusar');
    expectNamed(tester, find.text(refuseLead));
    expect(videoReads(h), 1);
  });

  testWidgets('lists only the questions that refuse, none ticked; the '
      'primary waits with its hint', (tester) async {
    await refusing(tester);

    expect(find.text(refuseItemsLead), findsOneWidget);
    expect(refuseItemsLead, startsWith('Marque o que acontece no vídeo.'));
    expect(find.text(differenceReminder), findsOneWidget);
    expect(item('Alguém bate de propósito?'), findsOneWidget);
    expect(item('Aparece promoção paga?'), findsOneWidget);
    expect(item('Falta começo, meio ou fim?'), findsOneWidget);
    for (final other in [
      'Algum personagem fica triste?',
      'Você tem vínculo com este canal?',
      'Tem ritmo agitado?',
      'O canal tem outros vídeos que você recusaria?',
    ]) {
      expect(find.textContaining(other), findsNothing, reason: other);
    }
    expect(ticked(tester, 'Alguém bate de propósito?'), isFalse);
    expect(primary(tester).label, 'Recusar');
    expect(primary(tester).onPressed, isNull);
    expect(find.text(refuseHint), findsOneWidget);
    expect(refuseHint, 'Marque acima pelo menos uma coisa que acontece.');

    await tick(tester, 'Alguém bate de propósito?');
    expect(primary(tester).onPressed, isNotNull);
  });

  testWidgets('arriving from an approval, its questions are ticked', (
    tester,
  ) async {
    await refusing(tester, initial: '/curadoria/v1/recusar?itens=c04');

    expect(ticked(tester, 'Alguém bate de propósito?'), isTrue);
    expect(primary(tester).onPressed, isNotNull);
  });

  testWidgets('the note is optional, multi-line, and counts only near the '
      'bound', (tester) async {
    await refusing(tester);

    final input = tester.widget<TextField>(field);
    expect(input.keyboardType, TextInputType.multiline);
    expect(input.maxLines, isNull);
    expect(input.maxLength, 500);
    expect(input.maxLengthEnforcement, MaxLengthEnforcement.enforced);
    await type(tester, 'a' * 399);
    expect(find.textContaining('de 500'), findsNothing);
    await type(tester, 'a' * 450);
    expect(find.text('450 de 500'), findsOneWidget);
  });

  testWidgets('sends the refusal once, the questions in the list\'s order '
      'and the note trimmed, then the done state back to the queue', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    final h = await refusing(tester, review: (_) => answer.future);

    await refuse(tester, reason: '  Tem um susto no fim. ', settle: false);
    await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
    await tester.pump();
    answer.complete(json(201, {'video_state': 'held'}));
    await tester.pumpAndSettle();

    expect(posts(h), hasLength(1));
    expect(jsonDecode(posts(h).single.split(' ').skip(2).join(' ')), {
      'decision': 'reject',
      'checklist_version': '2026-10-21',
      'failed_items': ['c04'],
      'note': 'Tem um susto no fim.',
    });
    expect(find.widgetWithText(Notice, refused), findsOneWidget);
    expect(field, findsNothing, reason: 'the form is gone');

    await tester.tap(find.text('Voltar para a fila'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/curadoria');
  });

  testWidgets('without a note, none is sent', (tester) async {
    final h = await refusing(tester);

    await tick(tester, 'Aparece promoção paga?');
    await tick(tester, 'Alguém bate de propósito?');
    await tapPrimary(tester);

    expect(jsonDecode(posts(h).single.split(' ').skip(2).join(' ')), {
      'decision': 'reject',
      'checklist_version': '2026-10-21',
      'failed_items': ['c03', 'c04'],
    });
  });

  testWidgets('a network failure keeps the questions and the note, and the '
      'primary tries again', (tester) async {
    var fail = true;
    final h = await refusing(
      tester,
      review: (_) => fail
          ? problem(503, 'unavailable')
          : json(201, {'video_state': 'held'}),
    );

    await refuse(tester);

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(ticked(tester, 'Alguém bate de propósito?'), isTrue);
    expect(find.text('Tem um susto no fim.'), findsOneWidget);
    fail = false;
    await tapPrimary(tester);
    expect(posts(h), hasLength(2));
    expect(find.text(refused), findsOneWidget);
  });

  testWidgets('validation marks the note', (tester) async {
    await refusing(tester, review: (_) => problem(422, 'validation'));

    await refuse(tester);

    expect(fieldError(tester), noteInvalid);
    expect(find.byType(ErrorNote), findsNothing);
    await type(tester, 'Outro motivo.');
    expect(fieldError(tester), isNull);
  });

  testWidgets('already_reviewed goes back to the queue with a notice', (
    tester,
  ) async {
    final h = await refusing(
      tester,
      review: (_) => problem(409, 'already_reviewed'),
    );

    await refuse(tester);

    expect(h.location(tester), '/curadoria');
    expect(find.text('Esse vídeo já saiu da fila.'), findsOneWidget);
  });

  testWidgets('checklist_outdated reads the list again and says why', (
    tester,
  ) async {
    final h = await refusing(
      tester,
      review: (_) => problem(409, 'checklist_outdated'),
    );

    await refuse(tester);

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
    expect(item('Alguém bate de propósito?'), findsOneWidget);
  });

  testWidgets('checklist_outdated whose new list fails to read offers to '
      'try again, never the old list', (tester) async {
    var reads = 0;
    final h = await refusing(
      tester,
      checklist: () =>
          ++reads == 2 ? problem(503, 'unavailable') : json(200, checklistJson),
      review: (_) => problem(409, 'checklist_outdated'),
    );

    await refuse(tester);

    expect(find.byType(DeclarationRow), findsNothing);
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(primary(tester).label, 'Tentar de novo');
    await tapPrimary(tester);

    expect(reads, 3);
    expect(posts(h), hasLength(1));
    expect(item('Alguém bate de propósito?'), findsOneWidget);
    expect(primary(tester).label, 'Recusar');
  });

  testWidgets('back returns to the review', (tester) async {
    final h = await refusing(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria/v1');
  });
}
