import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/search_results.dart';
import 'package:telinha_segura/curation/suggestion_confirmation.dart';
import 'package:telinha_segura/curation/suggestion_words.dart';
import 'package:telinha_segura/curation/words.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid/shelves.dart' show HollowThumbnail;

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'curation_api_test.dart' show pendingJson, videoJson;
import 'fixtures.dart';

const link = 'https://youtu.be/dQw4w9WgXcQ';

Future<Harness> form(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? suggest,
  FutureOr<http.Response> Function(http.Request)? search,
  FutureOr<http.Response> Function(String youtubeId)? thumb,
  String initial = '/sugestoes/nova',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h = Harness(
    signedIn: true,
    api: suggestionApi(suggest: suggest, search: search, thumb: thumb),
  )..family = ownerFamily;
  await h.pump(tester, initial: initial, size: size, textScale: textScale);
  return h;
}

Finder get field =>
    find.widgetWithText(TextField, 'Busque pelo título ou cole o link');

PrimaryButton primary(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton));

Future<void> tapPrimary(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
}

Future<void> send(WidgetTester tester, [String url = link]) async {
  await tester.enterText(field, url);
  await tester.pump();
  await tapPrimary(tester);
}

/// Types [q] and taps "Buscar".
Future<void> search(WidgetTester tester, [String q = 'pintinho']) async {
  await tester.enterText(field, q);
  await tester.pump();
  await tapPrimary(tester);
}

/// The suggestions sent, searches left out.
List<String> posts(Harness h) =>
    h.actions.where((c) => c.startsWith('POST /v1/suggestions {')).toList();

List<String> searches(Harness h) => h.actions
    .where((c) => c.startsWith('POST /v1/suggestions/search'))
    .toList();

String? fieldError(WidgetTester tester) =>
    tester.widget<TextField>(field).decoration?.errorText;

http.Response refused(String reason) =>
    problem(422, 'video_refused', extra: {'reason': reason});

/// Three hits: a fresh video, one refused, one already in the catalogue.
final threeHits = [
  searchJson('aaaaaaaaaaa', 'Pintinho amarelinho', channel: 'Galinha'),
  searchJson(
    'bbbbbbbbbbb',
    'Pintinho ao vivo',
    channel: 'Fazendinha',
    refusal: 'live',
  ),
  searchJson(
    'ccccccccccc',
    'Pintinho dançante',
    channel: 'Música Kids',
    seconds: 3900,
    state: 'approved',
  ),
];

Finder row(String title) => find.widgetWithText(DoorRow, title);

/// Replaces what the clipboard holds for the rest of the test; null is an
/// empty clipboard.
void clipboard(WidgetTester tester, String? text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData'
        ? (text == null ? null : {'text': text})
        : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  group('the link', () {
    testWidgets('a shared link fills the field and waits for the primary', (
      tester,
    ) async {
      final h = await form(
        tester,
        suggest: (_) => json(201, pendingJson),
        initial: '/sugestoes/nova?link=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ',
      );

      expect(tester.widget<TextField>(field).controller?.text, link);
      expect(primary(tester).label, 'Enviar sugestão');
      expect(primary(tester).onPressed, isNotNull);
      expect(posts(h), isEmpty);

      await tapPrimary(tester);
      expect(posts(h), ['POST /v1/suggestions {"url":"$link"}']);
      expect(searches(h), isEmpty);
    });

    testWidgets('a link that is not YouTube leaves the field empty', (
      tester,
    ) async {
      await form(tester, initial: '/sugestoes/nova?link=javascript%3Aalert(1)');

      expect(tester.widget<TextField>(field).controller?.text, isEmpty);
      expect(find.text(emptyHint), findsOneWidget);
    });

    testWidgets('one field without autocorrect, and the primary waits with '
        'its hint while it is empty', (tester) async {
      await form(tester);

      expect(find.text('Sugerir um vídeo'), findsOneWidget);
      final input = tester.widget<TextField>(field);
      expect(input.keyboardType, TextInputType.text);
      expect((input.autocorrect, input.enableSuggestions), (false, false));
      expect(primary(tester).onPressed, isNull);
      expect(find.text(emptyHint), findsOneWidget);

      await tester.enterText(field, '   ');
      await tester.pump();
      expect(primary(tester).onPressed, isNull, reason: 'blank is empty');
      expect(find.text(emptyHint), findsOneWidget);

      await tester.enterText(field, link);
      await tester.pump();
      expect(primary(tester).onPressed, isNotNull);
      final hint = tester.widget<SubmitHint>(find.byType(SubmitHint));
      expect((hint.visible, hint.reserve), (false, true));
    });

    testWidgets('a link reads "Enviar sugestão" with the send key, and other '
        'text "Buscar" with the search key', (tester) async {
      await form(tester);

      await tester.enterText(field, 'olha só $link?si=abc');
      await tester.pump();
      expect(primary(tester).label, 'Enviar sugestão');
      expect(
        tester.widget<TextField>(field).textInputAction,
        TextInputAction.send,
      );

      await tester.enterText(field, 'pintinho amarelinho');
      await tester.pump();
      expect(primary(tester).label, 'Buscar');
      expect(
        tester.widget<TextField>(field).textInputAction,
        TextInputAction.search,
      );
    });

    testWidgets('sends once, busy meanwhile, and a new video ends on '
        '"Recebemos sua sugestão."', (tester) async {
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

    testWidgets('the keyboard action sends a link', (tester) async {
      final h = await form(tester);

      await tester.enterText(field, link);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(posts(h), ['POST /v1/suggestions {"url":"$link"}']);
      expect(searches(h), isEmpty);
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

      await send(tester, 'https://www.youtube.com/@canal');

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
        find.widgetWithText(
          ErrorNote,
          Copy.retryIn(const Duration(seconds: 3)),
        ),
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
      testWidgets('$name shows the error note, and "Tentar de novo" sends '
          'the link again', (tester) async {
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
  });

  group('the search', () {
    testWidgets('2 to 100 characters search once with the trimmed text; '
        'typing alone never searches', (tester) async {
      final h = await form(tester, search: (_) => searchAnswer(threeHits));

      for (final partial in ['p', 'pi', 'pin', 'pintinho']) {
        await tester.enterText(field, partial);
        await tester.pump();
      }
      expect(searches(h), isEmpty);

      await search(tester, '  pintinho amarelinho ');

      expect(searches(h), [
        'POST /v1/suggestions/search {"q":"pintinho amarelinho"}',
      ]);
      expect(posts(h), isEmpty);
    });

    testWidgets('the keyboard action searches too', (tester) async {
      final h = await form(tester, search: (_) => searchAnswer(threeHits));

      await tester.enterText(field, 'pintinho');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(searches(h), hasLength(1));
    });

    testWidgets('under 2 characters or over 100 the primary waits with its '
        'hint', (tester) async {
      final h = await form(tester);

      await tester.enterText(field, ' a ');
      await tester.pump();
      expect(primary(tester).label, 'Buscar');
      expect(primary(tester).onPressed, isNull);
      expect(find.text(shortHint), findsOneWidget);

      await tester.enterText(field, 'a' * 101);
      await tester.pump();
      expect(primary(tester).onPressed, isNull);
      expect(find.text(longHint), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await tester.enterText(field, 'a' * 100);
      await tester.pump();
      expect(primary(tester).onPressed, isNotNull);
      expect(searches(h), isEmpty);
    });

    testWidgets('results list in the order received under "Resultados do '
        'YouTube", each with its picture, words and state', (tester) async {
      final h = await form(tester, search: (_) => searchAnswer(threeHits));

      await search(tester);

      expect(find.text(resultsLabel), findsOneWidget);
      final titles = [
        for (final r in tester.widgetList<DoorRow>(find.byType(DoorRow)))
          r.title,
      ];
      expect(titles, [
        'Pintinho amarelinho',
        'Pintinho ao vivo',
        'Pintinho dançante',
      ]);
      expect(find.text(nb('Galinha · 3 min')), findsOneWidget);
      expect(find.text(nb('Música Kids · 1 h 05 min')), findsOneWidget);
      expect(find.text(RefusalReason.live.message), findsOneWidget);
      expect(find.text(inCatalog), findsOneWidget);
      expect(
        h.actions.where((c) => c.startsWith('GET /v1/suggestions/thumbs/')),
        unorderedEquals([
          'GET /v1/suggestions/thumbs/aaaaaaaaaaa',
          'GET /v1/suggestions/thumbs/bbbbbbbbbbb',
          'GET /v1/suggestions/thumbs/ccccccccccc',
        ]),
      );
      expect(
        find.descendant(
          of: row('Pintinho amarelinho'),
          matching: find.byType(HollowThumbnail),
        ),
        findsOneWidget,
        reason: 'a thumbnail that did not come is hollow',
      );
    });

    testWidgets('the count is announced when results arrive', (tester) async {
      await form(tester, search: (_) => searchAnswer(threeHits));

      await search(tester);

      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('3 vídeos encontrados'),
      );
    });

    testWidgets('one result is announced in the singular', (tester) async {
      await form(tester, search: (_) => searchAnswer(threeHits.sublist(0, 1)));

      await search(tester);

      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('1 vídeo encontrado'),
      );
    });

    testWidgets('the field stays editable while the search runs, over the '
        'loading placeholder', (tester) async {
      final answer = Completer<http.Response>();
      await form(tester, search: (_) => answer.future);

      await tester.enterText(field, 'pintinho');
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(find.byType(FamilyPlaceholder), findsOneWidget);
      expect(primary(tester).busy, isTrue);
      expect(tester.widget<TextField>(field).enabled, isNot(false));

      answer.complete(searchAnswer(threeHits));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyPlaceholder), findsNothing);
    });

    testWidgets('a refused result says why and is no target', (tester) async {
      await form(tester, search: (_) => searchAnswer(threeHits));
      await search(tester);

      final refusedRow = row('Pintinho ao vivo');
      expect(
        find.descendant(of: refusedRow, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        tester.getSemantics(refusedRow),
        isSemantics(
          label:
              'Pintinho ao vivo, Fazendinha, 3 min, '
              '${RefusalReason.live.message}',
        ),
      );
      await tester.ensureVisible(refusedRow);
      await tester.pumpAndSettle();
      await tester.tap(refusedRow, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(SuggestionConfirmation), findsNothing);
    });

    for (final (state, words) in [
      ('approved', inCatalog),
      ('pending', inReview),
      ('held', inReview),
    ]) {
      testWidgets('a stored $state video reads "$words" and can still be '
          'suggested', (tester) async {
        await form(
          tester,
          search: (_) => searchAnswer([
            searchJson('ddddddddddd', 'Bichinhos', state: state),
          ]),
        );
        await search(tester);

        expect(find.text(words), findsOneWidget);
        await tester.ensureVisible(row('Bichinhos'));
        await tester.pumpAndSettle();
        await tester.tap(row('Bichinhos'));
        await tester.pumpAndSettle();
        expect(find.byType(SuggestionConfirmation), findsOneWidget);
      });
    }

    testWidgets('each row is read as one label: title, channel, length, '
        'state', (tester) async {
      await form(tester, search: (_) => searchAnswer(threeHits));
      await search(tester);

      expect(
        tester.getSemantics(row('Pintinho amarelinho')),
        isSemantics(
          label: 'Pintinho amarelinho, Galinha, 3 min',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      expect(
        tester.getSemantics(row('Pintinho dançante')),
        isSemantics(
          label:
              'Pintinho dançante, Música Kids, 1 h 05 min, '
              '$inCatalog',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
    });

    testWidgets('no results says so', (tester) async {
      await form(tester, search: (_) => searchAnswer([]));

      await search(tester);

      expect(find.text(noResults), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing);
    });

    testWidgets('editing the field keeps the list until the next search', (
      tester,
    ) async {
      var answer = threeHits;
      final h = await form(tester, search: (_) => searchAnswer(answer));
      await search(tester);

      await tester.enterText(field, 'outra coisa');
      await tester.pump();
      expect(row('Pintinho amarelinho'), findsOneWidget);

      answer = [searchJson('eeeeeeeeeee', 'Outra coisa')];
      await tapPrimary(tester);
      expect(row('Pintinho amarelinho'), findsNothing);
      expect(row('Outra coisa'), findsOneWidget);
      expect(searches(h), hasLength(2));
    });

    testWidgets('search_unavailable for the day says so, with no countdown', (
      tester,
    ) async {
      await form(
        tester,
        search: (_) =>
            problem(503, 'search_unavailable', headers: {'retry-after': '600'}),
      );

      await search(tester);

      expect(find.widgetWithText(ErrorNote, searchDaily), findsOneWidget);
      expect(find.textContaining('Tente de novo em'), findsNothing);
      expect(primary(tester).label, 'Buscar');
    });

    testWidgets('search_unavailable for now offers "Tentar de novo" while the '
        'text is the same', (tester) async {
      var fail = true;
      final h = await form(
        tester,
        search: (_) =>
            fail ? problem(503, 'search_unavailable') : searchAnswer(threeHits),
      );

      await search(tester);

      expect(find.widgetWithText(ErrorNote, searchNow), findsOneWidget);
      expect(primary(tester).label, 'Tentar de novo');
      fail = false;
      await tapPrimary(tester);

      expect(searches(h), hasLength(2));
      expect(find.byType(ErrorNote), findsNothing);
      expect(row('Pintinho amarelinho'), findsOneWidget);

      fail = true;
      await tapPrimary(tester);
      expect(primary(tester).label, 'Tentar de novo');
      await tester.enterText(field, 'outra coisa');
      await tester.pump();
      expect(primary(tester).label, 'Buscar');
      expect(find.byType(ErrorNote), findsNothing);
    });

    testWidgets('a dropped search shows the error note and tries again', (
      tester,
    ) async {
      await form(tester, search: (_) => throw http.ClientException('offline'));

      await search(tester);

      expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
      expect(primary(tester).label, 'Tentar de novo');
    });

    testWidgets('rate_limited counts the search down, and a link still sends', (
      tester,
    ) async {
      final h = await form(
        tester,
        search: (_) => problem(429, 'rate_limited', retryAfterBody: 30),
      );

      await search(tester);

      expect(
        find.widgetWithText(
          ErrorNote,
          Copy.retryIn(const Duration(seconds: 30)),
        ),
        findsOneWidget,
      );
      expect(primary(tester).onPressed, isNull);

      await send(tester);

      expect(posts(h), ['POST /v1/suggestions {"url":"$link"}']);
      expect(find.text('Recebemos sua sugestão.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    });
  });

  group('the confirmation', () {
    Future<Harness> opened(
      WidgetTester tester, {
      FutureOr<http.Response> Function(http.Request)? suggest,
    }) async {
      final h = await form(
        tester,
        suggest: suggest,
        search: (_) => searchAnswer(threeHits),
      );
      await search(tester);
      await tester.ensureVisible(row('Pintinho dançante'));
      await tester.pumpAndSettle();
      await tester.tap(row('Pintinho dançante'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('a result opens on its picture, title, channel and length', (
      tester,
    ) async {
      await opened(tester);

      expect(find.byType(SuggestionConfirmation), findsOneWidget);
      expect(find.text('Pintinho dançante'), findsOneWidget);
      expect(find.text(nb('Música Kids · 1 h 05 min')), findsOneWidget);
      expect(primary(tester).label, 'Enviar sugestão');
      expect(find.text('Voltar aos resultados'), findsOneWidget);
    });

    testWidgets('sending suggests the watch link and ends in the done state', (
      tester,
    ) async {
      final h = await opened(tester, suggest: (_) => json(200, videoJson));

      await tapPrimary(tester);

      expect(posts(h), [
        'POST /v1/suggestions '
            '${jsonEncode({'url': 'https://www.youtube.com/watch?v=ccccccccccc'})}',
      ]);
      expect(find.byType(SuggestionConfirmation), findsNothing);
      expect(find.text('Esse vídeo já está com a curadoria.'), findsOneWidget);
      expect(primary(tester).label, 'Voltar para sugestões');
    });

    testWidgets('"Voltar aos resultados" shows the same list, without a new '
        'search', (tester) async {
      final h = await opened(tester);

      await tester.tap(find.text('Voltar aos resultados'));
      await tester.pumpAndSettle();

      expect(find.byType(SuggestionConfirmation), findsNothing);
      expect(row('Pintinho amarelinho'), findsOneWidget);
      expect(searches(h), hasLength(1));
      expect(posts(h), isEmpty);
    });

    testWidgets('a refusal on send is a clay note, with the way back', (
      tester,
    ) async {
      await opened(tester, suggest: (_) => refused('not_for_kids'));

      await tapPrimary(tester);

      expect(find.byType(SuggestionConfirmation), findsOneWidget);
      expect(
        find.widgetWithText(ErrorNote, RefusalReason.notForKids.message),
        findsOneWidget,
      );
      expect(find.byType(PrimaryButton), findsNothing);
      await tester.tap(find.text('Voltar aos resultados'));
      await tester.pumpAndSettle();
      expect(row('Pintinho amarelinho'), findsOneWidget);
    });
  });

  group('"Colar link"', () {
    testWidgets('a YouTube link on the clipboard fills the field, sending '
        'nothing', (tester) async {
      clipboard(tester, 'veja $link?si=xyz');
      final h = await form(tester);

      await tester.tap(find.text('Colar link'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(field).controller?.text, link);
      expect(primary(tester).label, 'Enviar sugestão');
      expect(posts(h), isEmpty);
    });

    for (final (name, held) in [
      ('other text', 'pintinho'),
      ('nothing', null),
    ]) {
      testWidgets('$name on the clipboard says there is no link', (
        tester,
      ) async {
        clipboard(tester, held);
        await form(tester);
        await tester.enterText(field, 'pintinho');
        await tester.pump();

        await tester.tap(find.text('Colar link'));
        await tester.pumpAndSettle();

        expect(find.text(noClipboardLink), findsOneWidget);
        expect(tester.widget<TextField>(field).controller?.text, 'pintinho');
      });
    }
  });

  group('at 200 % text on 360 × 640', () {
    testWidgets('the form, the results and the confirmation hold', (
      tester,
    ) async {
      await form(
        tester,
        search: (_) => searchAnswer(threeHits),
        size: const Size(360, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      await search(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(row('Pintinho dançante'));
      await tester.pumpAndSettle();
      await tester.tap(row('Pintinho dançante'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SuggestionConfirmation), findsOneWidget);
    });

    testWidgets('"Colar link" keeps a 48 dp target', (tester) async {
      await form(tester, size: const Size(360, 640), textScale: 2);

      final size = tester.getSize(
        find.ancestor(
          of: find.text('Colar link'),
          matching: find.byType(TextButton),
        ),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });
  });
}
