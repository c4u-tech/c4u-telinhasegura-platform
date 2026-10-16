import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/new_suggestion_screen.dart';
import 'package:telinha_segura/curation/words.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'curation_api_test.dart' show pendingJson, videoJson;
import 'fixtures.dart';

const link = 'https://youtu.be/dQw4w9WgXcQ';

Future<Harness> form(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? suggest,
  String initial = '/sugestoes/nova',
}) async {
  final h = Harness(signedIn: true, api: suggestionApi(suggest: suggest))
    ..family = ownerFamily;
  await h.pump(tester, initial: initial);
  return h;
}

Finder get field => find.widgetWithText(TextField, 'Link do YouTube');

PrimaryButton primary(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton));

Future<void> send(WidgetTester tester, [String url = link]) async {
  await tester.enterText(field, url);
  await tester.pump();
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
}

List<String> posts(Harness h) =>
    h.actions.where((c) => c.startsWith('POST /v1/suggestions')).toList();

String? fieldError(WidgetTester tester) =>
    tester.widget<TextField>(field).decoration?.errorText;

http.Response refused(String reason) =>
    problem(422, 'video_refused', extra: {'reason': reason});

void main() {
  testWidgets('one link field for a URL, without autocorrect, and the '
      'primary waits with its hint while it is empty', (tester) async {
    await form(tester);

    expect(find.text('Sugerir um vídeo'), findsOneWidget);
    final input = tester.widget<TextField>(field);
    expect(input.keyboardType, TextInputType.url);
    expect((input.autocorrect, input.enableSuggestions), (false, false));
    expect(primary(tester).label, 'Enviar sugestão');
    expect(primary(tester).onPressed, isNull);
    expect(find.text(linkHint), findsOneWidget);

    await tester.enterText(field, '   ');
    await tester.pump();
    expect(primary(tester).onPressed, isNull, reason: 'blank is empty');

    await tester.enterText(field, link);
    await tester.pump();
    expect(primary(tester).onPressed, isNotNull);
    final hint = tester.widget<SubmitHint>(find.byType(SubmitHint));
    expect((hint.visible, hint.reserve), (false, true));
  });

  testWidgets('sends once, busy meanwhile, and a new video ends on "Recebemos '
      'sua sugestão."', (tester) async {
    final answer = Completer<http.Response>();
    final h = await form(tester, suggest: (_) => answer.future);

    await tester.enterText(field, '  $link ');
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    expect(primary(tester).busy, isTrue);
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    answer.complete(json(201, pendingJson));
    await tester.pumpAndSettle();

    expect(posts(h), ['POST /v1/suggestions {"url":"$link"}']);
    expect(find.widgetWithText(Notice, 'Recebemos sua sugestão.'), findsOne);
    expect(field, findsNothing, reason: 'the form is gone');
    expect(find.byType(PrimaryButton), findsOneWidget);
    expect(primary(tester).label, 'Voltar para sugestões');
  });

  testWidgets('a video already there ends on "Esse vídeo já está com a '
      'curadoria."', (tester) async {
    await form(tester, suggest: (_) => json(200, videoJson));

    await send(tester);

    expect(find.text('Esse vídeo já está com a curadoria.'), findsOneWidget);
    expect(find.text('Recebemos sua sugestão.'), findsNothing);
  });

  testWidgets('"Voltar para sugestões" goes back to the list, which reads '
      'again', (tester) async {
    final h = await form(tester, initial: '/sugestoes');
    await tester.tap(find.text('Sugerir um vídeo'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/sugestoes/nova');

    await send(tester);
    await tester.tap(find.text('Voltar para sugestões'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/sugestoes');
    expect(h.actions.where((c) => c == 'GET /v1/suggestions'), hasLength(2));
  });

  testWidgets('opened directly, back goes to the list, which reads then', (
    tester,
  ) async {
    final h = await form(tester);
    expect(h.actions.where((c) => c == 'GET /v1/suggestions'), isEmpty);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/sugestoes');
    expect(h.actions.where((c) => c == 'GET /v1/suggestions'), hasLength(1));
  });

  for (final reason in RefusalReason.values) {
    testWidgets('video_refused (${reason.name}) is worded on the field, the '
        'link kept', (tester) async {
      await form(tester, suggest: (_) => refused(reason.wire));

      await send(tester);

      expect(fieldError(tester), reason.message);
      expect(find.byType(ErrorNote), findsNothing);
      expect(tester.widget<TextField>(field).controller!.text, link);
    });
  }

  testWidgets('invalid_link is worded on the field, and editing clears it', (
    tester,
  ) async {
    await form(tester, suggest: (_) => problem(422, 'invalid_link'));

    await send(tester, 'https://example.com/x');

    expect(fieldError(tester), invalidLink);
    await tester.enterText(field, link);
    await tester.pump();
    expect(fieldError(tester), isNull);
  });

  testWidgets('rate_limited counts down with the primary waiting', (
    tester,
  ) async {
    await form(
      tester,
      suggest: (_) => problem(429, 'rate_limited', retryAfterBody: 3),
    );

    await send(tester);

    expect(
      find.widgetWithText(ErrorNote, Copy.retryIn(const Duration(seconds: 3))),
      findsOneWidget,
    );
    expect(primary(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(primary(tester).onPressed, isNotNull);
    expect(fieldError(tester), isNull);
  });

  for (final (name, answer) in [
    (
      'video_source_unavailable',
      () => problem(503, 'video_source_unavailable'),
    ),
    ('a dropped call', () => throw http.ClientException('offline')),
  ]) {
    testWidgets('$name shows the error note, and "Tentar de novo" sends the '
        'link again', (tester) async {
      var fail = true;
      final h = await form(
        tester,
        suggest: (_) => fail ? answer() : json(201, pendingJson),
      );

      await send(tester);

      expect(find.byType(ErrorNote), findsOneWidget);
      expect(fieldError(tester), isNull);
      expect(primary(tester).label, 'Tentar de novo');
      fail = false;
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();

      expect(posts(h), hasLength(2));
      expect(find.text('Recebemos sua sugestão.'), findsOneWidget);
    });
  }

  testWidgets('video_source_unavailable says YouTube could not be reached', (
    tester,
  ) async {
    await form(
      tester,
      suggest: (_) => problem(503, 'video_source_unavailable'),
    );

    await send(tester);

    expect(find.widgetWithText(ErrorNote, sourceUnavailable), findsOneWidget);
  });
}
