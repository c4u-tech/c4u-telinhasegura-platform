import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/refuse_screen.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'approve_screen_test.dart'
    show expectNamed, posts, primary, tapPrimary, videoReads;
import 'fixtures.dart';

Future<Harness> refusing(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? review,
  String initial = '/curadoria/v1/recusar',
}) async {
  final h = Harness(signedIn: true, api: curatorApi(review: review))
    ..family = ownerFamily
    ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

Finder get field => find.widgetWithText(TextField, 'Motivo');

String? fieldError(WidgetTester tester) =>
    tester.widget<TextField>(field).decoration?.errorText;

Future<void> type(WidgetTester tester, String reason) async {
  await tester.enterText(field, reason);
  await tester.pump();
}

Future<void> refuse(
  WidgetTester tester, {
  String reason = 'Tem um susto no fim.',
  bool settle = true,
}) async {
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

    await tester.ensureVisible(find.text('Dizer o motivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dizer o motivo'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria/v1/recusar');
    expectNamed(tester, find.text(refuseLead));
    expect(videoReads(h), 1);
  });

  testWidgets('says a refusal takes the video off the shelves at once, '
      'then one multi-line "Motivo" and the ink primary, waiting with its '
      'hint', (tester) async {
    await refusing(tester);

    expect(find.text('Recusar'), findsWidgets);
    expect(find.text(refuseLead), findsOneWidget);
    final input = tester.widget<TextField>(field);
    expect(input.keyboardType, TextInputType.multiline);
    expect(input.maxLines, isNull);
    expect(input.maxLength, 500);
    expect(input.maxLengthEnforcement, MaxLengthEnforcement.enforced);
    expect(primary(tester).label, 'Recusar');
    expect(primary(tester).onPressed, isNull);
    expect(find.text(refuseHint), findsOneWidget);
    final leadTop = tester.getTopLeft(find.text(refuseLead)).dy;
    expect(leadTop, lessThan(tester.getTopLeft(field).dy));
  });

  testWidgets('the primary waits until the reason has a non-blank '
      'character', (tester) async {
    await refusing(tester);

    await type(tester, '   \n ');
    expect(primary(tester).onPressed, isNull);
    await type(tester, ' Tem propaganda. ');
    expect(primary(tester).onPressed, isNotNull);
  });

  testWidgets('the count shows only near the bound', (tester) async {
    await refusing(tester);

    await type(tester, 'a' * 399);
    expect(find.textContaining('de 500'), findsNothing);
    await type(tester, 'a' * 450);
    expect(find.text('450 de 500'), findsOneWidget);
    await type(tester, 'a' * 520);
    expect(find.text('500 de 500'), findsOneWidget);
  });

  testWidgets('sends the refusal once, trimmed, and shows the done state, '
      'back to the queue', (tester) async {
    final answer = Completer<http.Response>();
    final h = await refusing(tester, review: (_) => answer.future);

    await refuse(tester, reason: '  Tem um susto no fim. ', settle: false);
    await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
    await tester.pump();
    answer.complete(json(201, {'video_state': 'held'}));
    await tester.pumpAndSettle();

    expect(posts(h), hasLength(1));
    expect(posts(h).single, startsWith('POST /v1/curation/videos/v1/reviews'));
    expect(jsonDecode(posts(h).single.split(' ').skip(2).join(' ')), {
      'decision': 'reject',
      'reason': 'Tem um susto no fim.',
    });
    expect(find.widgetWithText(Notice, refused), findsOneWidget);
    expect(field, findsNothing, reason: 'the form is gone');

    await tester.tap(find.text('Voltar para a fila'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/curadoria');
  });

  testWidgets('a network failure keeps the reason, and the primary tries '
      'again', (tester) async {
    var fail = true;
    final h = await refusing(
      tester,
      review: (_) => fail
          ? problem(503, 'unavailable')
          : json(201, {'video_state': 'held'}),
    );

    await refuse(tester);

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(find.text('Tem um susto no fim.'), findsOneWidget);
    fail = false;
    await tapPrimary(tester);
    expect(posts(h), hasLength(2));
    expect(find.text(refused), findsOneWidget);
  });

  testWidgets('validation marks the field', (tester) async {
    await refusing(tester, review: (_) => problem(422, 'validation'));

    await refuse(tester);

    expect(fieldError(tester), reasonInvalid);
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

  testWidgets('back returns to the review', (tester) async {
    final h = await refusing(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria/v1');
  });
}
