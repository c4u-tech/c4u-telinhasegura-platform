import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/display_title.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/shell/list_detail.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/answer_choice.dart';
import 'package:telinha_segura/curation/approve_screen.dart';
import 'package:telinha_segura/curation/words.dart' show differenceReminder;
import 'package:telinha_segura/family/family.dart' show AgeBand;
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/family/profile_fields.dart'
    show ChoiceTarget, SelectableRow, underTwoAdvice;
import 'package:telinha_segura/legal/legal_links.dart';
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../kid/fake_player.dart';
import 'appoint_screen_test.dart' show tapOn;
import 'queue_screen_test.dart' show goTo;
import 'fixtures.dart';

const themes = ['Bichos', 'Música', 'Histórias', 'Aprender', 'Brincar'];
const allThemes = [...themes, 'Natureza'];
const bands = ['2 a 4 anos', '5 a 8 anos', '9 a 12 anos'];

/// The fixture's questions.
const tie = 'Você tem vínculo com este canal?';
const paid = 'Aparece promoção paga?';
const hits = 'Alguém bate de propósito?';
const sad = 'Algum personagem fica triste?';
const fast = 'Tem ritmo agitado?';
const dating = 'Tem namoro entre os personagens?';
const others = 'O canal tem outros vídeos que você recusaria?';

/// Every question of the fixture answered "Não".
const allNos = {
  'c25': 'ok',
  'c03': 'ok',
  'c04': 'ok',
  'c07': 'ok',
  'c08': 'ok',
  'c15': 'ok',
  'c12': 'ok',
  'c22': 'ok',
  'c35': 'ok',
  'c23': 'ok',
  'c24': 'ok',
};

Future<Harness> approving(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? review,
  FutureOr<http.Response> Function()? checklist,
  FutureOr<http.Response> Function(String id)? video,
  FutureOr<http.Response> Function()? draft,
  FutureOr<http.Response> Function()? ended,
  String initial = '/curadoria/v1/aprovar',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h =
      Harness(
          signedIn: true,
          api: curatorApi(
            review: review,
            checklist: checklist,
            video: video,
            // Unless a test says otherwise, the video already played to its
            // end, so "Aprovar" does not wait.
            draft: draft ?? () => kept(draftJson(ended: true)),
            ended: ended,
          ),
        )
        ..family = ownerFamily
        ..roles = ['curator'];
  await h.pump(tester, initial: initial, size: size, textScale: textScale);
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

/// The [word] key ("Não", "Sim", "Não sei") of [question].
Finder key(String question, String word) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is AnswerChoice && w.question == question,
  ),
  matching: find.widgetWithText(ChoiceTarget, word),
);

bool picked(WidgetTester tester, String question, String word) =>
    tester.widget<ChoiceTarget>(key(question, word)).selected;

Future<void> answer(WidgetTester tester, String question, String word) =>
    tapOn(tester, key(question, word));

Future<void> noneOfThis(WidgetTester tester) =>
    tapOn(tester, find.widgetWithText(OutlinedButton, noneHappens));

/// The review's "mudar" of [title].
Finder change(String title) => find.byWidgetPredicate(
  (w) => w is QuietAction && w.semanticsLabel == '$changeLabel: $title',
);

/// "Antes de começar" answered "Não" to both, then on to the first step.
Future<void> start(WidgetTester tester) async {
  await answer(tester, tie, 'Não');
  await answer(tester, paid, 'Não');
  await tapPrimary(tester);
}

/// Steps [from] to [to] answered by "Nada disso acontece no vídeo", each
/// followed by its primary.
Future<void> clearSteps(WidgetTester tester, {int from = 1, int to = 5}) async {
  for (var i = from; i <= to; i++) {
    await noneOfThis(tester);
    await tapPrimary(tester);
  }
}

/// From the start to the theme and band, every answer "Não".
Future<void> toTopic(WidgetTester tester) async {
  await start(tester);
  await clearSteps(tester);
}

/// From the start to the review of an approval of "Música" for "5 a 8
/// anos", every answer "Não".
Future<void> toReview(WidgetTester tester) async {
  await toTopic(tester);
  await choose(tester, 'Música');
  await choose(tester, '5 a 8 anos');
  await tapPrimary(tester);
}

/// From the start to the review with "Não sei" on [sad]: the team decides.
Future<void> toTeam(WidgetTester tester) async {
  await start(tester);
  await answer(tester, hits, 'Não');
  await answer(tester, sad, 'Não sei');
  await tapPrimary(tester);
  await clearSteps(tester, from: 2);
}

/// Answers the whole list with "Não", chooses "Música" and "5 a 8 anos"
/// and approves; with [settle] false it leaves the request running.
Future<void> approve(WidgetTester tester, {bool settle = true}) async {
  await toReview(tester);
  await tapPrimary(tester, settle: settle);
}

List<String> posts(Harness h) =>
    h.actions.where((c) => c.startsWith('POST ')).toList();

/// The draft's saves, each with what it sent.
List<String> draftSaves(Harness h) =>
    h.actions.where((c) => c.startsWith('PUT ')).toList();

/// A draft read's answer: [draft] kept from before.
http.Response kept(Map<String, Object?> draft) => json(200, {'draft': draft});

Map<String, dynamic> sent(Harness h) =>
    jsonDecode(posts(h).single.split(' ').skip(2).join(' '))
        as Map<String, dynamic>;

/// The reads of the video itself, not of its draft.
int videoReads(Harness h) => h.actions
    .where(
      (a) => a.startsWith('GET /v1/curation/videos/') && !a.endsWith('/draft'),
    )
    .length;

/// The review's door into the flow.
const reviewDoor = 'Revisar vídeo';

/// The flow's player.
Finder window() => find.byKey(FakePlayback.viewKey);

/// The line under the window.
Finder endLine(String words) => find.text(words);

/// No page title and no video name: the window stands for the video.
void expectUntitled(WidgetTester tester) {
  expect(find.byType(DisplayTitle), findsNothing);
  expect(find.text('Baby Shark'), findsNothing);
  expect(find.text(nb('Canal Baby Shark · 4 min')), findsNothing);
}

/// Drags the page's content [dy] up.
Future<void> scrollContent(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(Scrollable).last, Offset(0, -dy));
  await tester.pumpAndSettle();
}

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

double scrolled(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

void main() {
  test('the length line names the 60-minute bar of the youngest band', () {
    expect(
      tooLongForYoungestLine,
      'Vídeos com mais de 60 minutos não vão para a faixa de 2 a 4 anos.',
    );
  });

  group('Antes de começar', () {
    testWidgets('says what the app checked, asks the tie with Não and Sim '
        'only, and waits on "Começar as perguntas" until both are '
        'answered', (tester) async {
      await approving(tester);

      expect(find.text('Antes de começar'), findsOneWidget);
      expect(find.text(checkedByApp), findsOneWidget);
      expect(key(tie, 'Não sei'), findsNothing);
      expect(key(paid, 'Não sei'), findsOneWidget);
      expect(primary(tester).label, startQuestions);
      expect(startQuestions, 'Começar as perguntas');
      expect(primary(tester).onPressed, isNull);
      expect(find.text(stepHint), findsOneWidget);
      await answer(tester, tie, 'Não');
      expect(primary(tester).onPressed, isNull);
      await answer(tester, paid, 'Não');
      expect(primary(tester).onPressed, isNotNull);
      await tapPrimary(tester);

      expect(find.text('Etapa 1 de 5'), findsOneWidget);
    });

    testWidgets('a tie to the channel says so and goes back to the queue, '
        'sending nothing', (tester) async {
      final h = await approving(tester);

      await answer(tester, tie, 'Sim');
      expect(find.text(conflictLine), findsOneWidget);
      expect(primary(tester).label, 'Voltar para a fila');
      await tapPrimary(tester);

      expect(h.location(tester), '/curadoria');
      expect(posts(h), isEmpty);
    });

    testWidgets('shows no page title and no video name: the window is what '
        'the flow is about, through to the done state', (tester) async {
      await approving(tester);

      expectUntitled(tester);
      await start(tester);
      expectUntitled(tester);
      await clearSteps(tester);
      await choose(tester, 'Música');
      await choose(tester, '5 a 8 anos');
      await tapPrimary(tester);
      expectUntitled(tester);
      await tapPrimary(tester);
      expect(find.text(approved), findsOneWidget);
      expectUntitled(tester);
    });

    testWidgets('opened from the review, it does not read the video again', (
      tester,
    ) async {
      final h = await approving(tester, initial: '/curadoria/v1');

      await tapOn(tester, find.text(reviewDoor));

      expect(h.location(tester), '/curadoria/v1/aprovar');
      expect(window(), findsOneWidget);
      expect(videoReads(h), 1);
    });
  });

  group('the video', () {
    /// Opens the flow from the review, whose own player stays beneath:
    /// the flow's player is the one opened after it.
    Future<Harness> fromReview(WidgetTester tester) async {
      final h = await approving(tester, initial: '/curadoria/v1');
      expect(h.adultPlayer.opened, hasLength(1));
      await tapOn(tester, find.text(reviewDoor));
      return h;
    }

    testWidgets('plays at the top of "Antes de começar" and of each step, '
        'its line under it, without playing on its own', (tester) async {
      final h = await fromReview(tester);

      expect(h.adultPlayer.opened, hasLength(2));
      final flow = h.adultPlayer.opened.last;
      expect(flow.youtubeId, 'yt-v1');
      expect(flow.calls, isEmpty, reason: 'no autoplay');
      expect(window(), findsOneWidget);
      final below = [
        window(),
        endLine(playedToEnd),
        find.text('Antes de começar'),
      ];
      final tops = [for (final f in below) tester.getTopLeft(f).dy];
      expect(tops, [...tops]..sort());
      final size = tester.getSize(window());
      expect(size.height, closeTo(size.width * 9 / 16, .01));

      await start(tester);
      expect(find.text('Etapa 1 de 5'), findsOneWidget);
      expect(window(), findsOneWidget);
      expect(
        tester.getTopLeft(window()).dy,
        lessThan(tester.getTopLeft(find.text('Etapa 1 de 5')).dy),
      );
    });

    testWidgets('one playback for the whole flow: moving between steps '
        'neither opens another nor rebuilds its view', (tester) async {
      final h = await fromReview(tester);
      final flow = h.adultPlayer.opened.last;
      final view = tester.element(window());

      await start(tester);
      expect(tester.element(window()), same(view));
      await clearSteps(tester, to: 4);
      expect(find.text('Etapa 5 de 5'), findsOneWidget);
      expect(tester.element(window()), same(view));
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(QuietAction),
          matching: find.text('Voltar'),
        ),
      );
      expect(find.text('Etapa 4 de 5'), findsOneWidget);
      expect(tester.element(window()), same(view));

      expect(h.adultPlayer.opened, hasLength(2));
      expect(h.adultPlayer.opened.last, same(flow));
      expect(flow.closed, isFalse);
    });

    testWidgets('the theme and band and the review keep the same player', (
      tester,
    ) async {
      final h = await fromReview(tester);
      final view = tester.element(window());
      await toTopic(tester);

      expect(find.text('Tema'), findsOneWidget);
      expect(tester.element(window()), same(view));
      await choose(tester, 'Música');
      await choose(tester, '5 a 8 anos');
      await tapPrimary(tester);
      expect(find.text(reviewTitle), findsOneWidget);
      expect(tester.element(window()), same(view));
      expect(h.adultPlayer.opened, hasLength(2));
    });

    testWidgets('leaving the flow lets its player go; the review\'s stays', (
      tester,
    ) async {
      final h = await fromReview(tester);
      final review = h.adultPlayer.opened.first;
      final flow = h.adultPlayer.opened.last;

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(h.location(tester), '/curadoria/v1');
      expect(flow.closed, isTrue);
      expect(review.closed, isFalse);
    });

    testWidgets('opened directly, the player loads once the video is read', (
      tester,
    ) async {
      final h = await approving(tester);

      expect(window(), findsOneWidget);
      expect(h.adultPlayer.opened.last.youtubeId, 'yt-v1');
    });

    testWidgets('the player\'s end in the flow is reported to the draft', (
      tester,
    ) async {
      final h = await fromReview(tester);
      final flow = h.adultPlayer.opened.last;
      final before = posts(h).length;

      flow.emit(const PlayerEnded());
      await tester.pumpAndSettle();

      expect(posts(h).skip(before), [
        'POST /v1/curation/videos/v1/draft/ended',
      ]);
      expect(flow.closed, isFalse);
      expect(window(), findsOneWidget);
    });
  });

  group('the window stays', () {
    /// Where the window's top stands, and whether the whole of it is on
    /// screen.
    double top(WidgetTester tester) => tester.getTopLeft(window()).dy;

    testWidgets('on a phone it stays under the band while the page scrolls '
        'beneath it, on every page of the flow', (tester) async {
      await approving(tester);

      Future<void> expectPinned() async {
        final before = top(tester);
        await scrollContent(tester, 300);
        expect(top(tester), before, reason: 'the window did not move');
        // Nothing of the page is drawn over the window: what lies at its
        // centre is the window.
        final centre = tester.getCenter(window());
        expect(
          tester
              .hitTestOnBinding(centre)
              .path
              .any((e) => e.target == tester.renderObject(window())),
          isTrue,
        );
        await scrollContent(tester, -300);
      }

      await expectPinned();
      await start(tester);
      await expectPinned();
      await clearSteps(tester);
      expect(find.text('Tema'), findsOneWidget);
      await expectPinned();
      await choose(tester, 'Música');
      await choose(tester, '5 a 8 anos');
      await tapPrimary(tester);
      expect(find.text(reviewTitle), findsOneWidget);
      await expectPinned();
    });

    testWidgets('at 360 × 640 and 200 % text it scrolls with the page, '
        'since it would leave less than half the height', (tester) async {
      await approving(tester, size: const Size(360, 640), textScale: 2);
      final before = top(tester);

      await scrollContent(tester, 200);

      expect(top(tester), lessThan(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 1280 × 800 it has its own pane, the list steps aside, '
        'and the questions scroll beside it', (tester) async {
      await approving(tester, size: const Size(1280, 800));

      expect(find.byKey(ListDetail.listKey), findsNothing);
      final question = find.text(tie);
      final windowBox = tester.getRect(window());
      expect(windowBox.right, lessThan(tester.getTopLeft(question).dx));
      expect(
        tester.getTopLeft(endLine(playedToEnd)).dy,
        greaterThan(windowBox.bottom),
      );
      final divider = tester.getRect(find.byType(VerticalDivider));
      expect(divider.left, greaterThan(windowBox.right));
      expect(divider.right, lessThan(tester.getTopLeft(question).dx));

      await start(tester);
      final before = top(tester);
      await scrollContent(tester, 300);
      expect(top(tester), before);
      expect(tester.takeException(), isNull);
    });
  });

  group('the video\'s end', () {
    /// The review's primary, "Aprovar" once every answer is "Não".
    Future<Harness> unwatched(WidgetTester tester, {Size? size}) => approving(
      tester,
      draft: () => kept(draftJson()),
      size: size ?? const Size(390, 844),
    );

    testWidgets('the line says the video has not played to its end, muted, '
        'until the player reports the end, then says it has, with the '
        'check', (tester) async {
      final h = await unwatched(tester);

      expect(notPlayedToEnd, 'Ainda não tocou até o fim');
      expect(playedToEnd, 'Tocou até o fim');
      expect(endLine(notPlayedToEnd), findsOneWidget);
      expect(endLine(playedToEnd), findsNothing);
      final palette = tester.element(endLine(notPlayedToEnd)).palette;
      expect(
        tester.widget<Text>(endLine(notPlayedToEnd)).style?.color,
        palette.muted,
      );
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await start(tester);
      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();

      expect(find.text('Etapa 1 de 5'), findsOneWidget, reason: 'same page');
      expect(endLine(notPlayedToEnd), findsNothing);
      expect(endLine(playedToEnd), findsOneWidget);
      expect(
        tester.widget<Text>(endLine(playedToEnd)).style?.color,
        palette.text,
      );
      final check = find.byIcon(Icons.check_rounded);
      expect(check, findsOneWidget);
      expect(
        tester.getCenter(check).dy,
        closeTo(tester.getCenter(endLine(playedToEnd)).dy, 2),
      );
    });

    testWidgets('the line is one label, announced as a live region', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await unwatched(tester);

      expect(
        tester.getSemantics(endLine(notPlayedToEnd)),
        isSemantics(label: notPlayedToEnd, isLiveRegion: true),
      );
      semantics.dispose();
    });

    testWidgets('a draft whose end was already recorded says so from the '
        'start', (tester) async {
      await approving(tester, draft: () => kept(draftJson(ended: true)));

      expect(endLine(playedToEnd), findsOneWidget);
      expect(endLine(notPlayedToEnd), findsNothing);
    });

    testWidgets('an end the review\'s player saw but failed to report says '
        'so too', (tester) async {
      final h = await approving(
        tester,
        initial: '/curadoria/v1',
        draft: () => kept(draftJson()),
        ended: () => problem(503, 'unavailable'),
      );
      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();

      await tapOn(tester, find.text(reviewDoor));

      expect(endLine(playedToEnd), findsOneWidget);
    });

    testWidgets('"Aprovar" waits, with its hint, until the video plays to its '
        'end; then it sends', (tester) async {
      final h = await unwatched(tester);
      await toReview(tester);

      expect(primary(tester).label, approveLabel);
      expect(primary(tester).onPressed, isNull);
      expect(watchHint, 'Para aprovar, deixe o vídeo tocar até o fim.');
      expect(
        tester.widget<SubmitHint>(find.byType(SubmitHint)).visible,
        isTrue,
      );
      expect(find.text(watchHint), findsOneWidget);

      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();

      expect(primary(tester).onPressed, isNotNull);
      expect(
        tester.widget<SubmitHint>(find.byType(SubmitHint)).visible,
        isFalse,
      );
      await tapPrimary(tester);
      expect(find.text(approved), findsOneWidget);
    });

    testWidgets('a doubt is sent without waiting for the end', (tester) async {
      final h = await unwatched(tester);
      await toTeam(tester);

      expect(primary(tester).label, teamLabel);
      expect(primary(tester).onPressed, isNotNull);
      expect(find.text(watchHint), findsNothing);
      await tapPrimary(tester);
      expect(posts(h), hasLength(1));
    });

    testWidgets('a refusal does not wait for the end', (tester) async {
      await unwatched(tester);
      await start(tester);
      await answer(tester, hits, 'Sim');
      await answer(tester, sad, 'Não');
      await tapPrimary(tester);
      await clearSteps(tester, from: 2);

      expect(primary(tester).label, refuseLabel);
      expect(primary(tester).onPressed, isNotNull);
      expect(find.text(watchHint), findsNothing);
    });
  });

  group('the title', () {
    void expectTitle(WidgetTester tester) => expectUntitled(tester);

    testWidgets('no page shows a title, whatever the answers lead to', (
      tester,
    ) async {
      final h = await approving(
        tester,
        review: (_) => json(201, {'video_state': 'held'}),
      );

      expectTitle(tester);
      await start(tester);
      expectTitle(tester);
      await answer(tester, hits, 'Não');
      await answer(tester, sad, 'Não sei');
      await tapPrimary(tester);
      await clearSteps(tester, from: 2);
      expect(find.text(reviewTitle), findsOneWidget);
      expect(primary(tester).label, teamLabel);
      expectTitle(tester);
      await tapPrimary(tester);
      expect(posts(h), hasLength(1));
      expectTitle(tester);
    });

    testWidgets('the theme and band page names "Tema" as a header, and the '
        'review\'s title is a header announced on arrival', (tester) async {
      final semantics = tester.ensureSemantics();
      await approving(tester);
      await toTopic(tester);

      expect(
        tester.getSemantics(find.text('Tema')),
        isSemantics(isHeader: true),
      );
      await choose(tester, 'Música');
      await choose(tester, '5 a 8 anos');
      await tapPrimary(tester);
      expect(
        tester.getSemantics(find.text(reviewTitle)),
        isSemantics(isHeader: true, isLiveRegion: true),
      );
      semantics.dispose();
    });
  });

  group('the steps', () {
    testWidgets('a step says "Etapa n de 5" and its group, offers the '
        'shortcut over "ou responda uma a uma", and goes on only once '
        'every question is answered', (tester) async {
      await approving(tester);
      await start(tester);

      expect(find.text('Etapa 1 de 5'), findsOneWidget);
      expect(find.text('Violência e medo'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, noneHappens), findsOneWidget);
      final shortcut = tester.getTopLeft(find.text(noneHappens)).dy;
      final line = tester.getTopLeft(find.text(orOneByOne)).dy;
      final question = tester.getTopLeft(find.text(hits)).dy;
      expect(shortcut < line && line < question, isTrue);
      expect(primary(tester).label, nextStep);
      expect(primary(tester).onPressed, isNull);
      await answer(tester, hits, 'Não');
      expect(primary(tester).onPressed, isNull);
      await answer(tester, sad, 'Não');
      expect(primary(tester).onPressed, isNotNull);
      await tapPrimary(tester);

      expect(find.text('Etapa 2 de 5'), findsOneWidget);
      expect(find.text('Linguagem e respeito'), findsOneWidget);
    });

    testWidgets('"Nada disso acontece no vídeo" answers Não to every '
        'question, each still open to change', (tester) async {
      await approving(tester);
      await start(tester);

      await noneOfThis(tester);
      expect(picked(tester, hits, 'Não'), isTrue);
      expect(picked(tester, sad, 'Não'), isTrue);
      expect(primary(tester).onPressed, isNotNull);
      await answer(tester, hits, 'Sim');

      expect(picked(tester, hits, 'Sim'), isTrue);
      expect(picked(tester, hits, 'Não'), isFalse);
    });

    testWidgets('each question is a group named by the question, each answer '
        'a radio with a check once chosen, and each step is announced', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await approving(tester);
      await start(tester);

      expect(
        tester
            .getSemantics(find.bySemanticsLabel(hits))
            .getSemanticsData()
            .role,
        SemanticsRole.radioGroup,
      );
      expect(
        tester.getSemantics(key(hits, 'Não')),
        isSemantics(
          label: 'Não',
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: false,
        ),
      );
      await answer(tester, hits, 'Não');
      expect(
        tester.getSemantics(key(hits, 'Não')),
        isSemantics(isChecked: true),
      );
      expect(
        find.descendant(
          of: key(hits, 'Não'),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Etapa 1 de 5, Violência e medo'),
        ),
        isSemantics(isHeader: true, isLiveRegion: true),
      );
      semantics.dispose();
    });

    testWidgets('the last step leads to the theme and band only when the '
        'video can be approved', (tester) async {
      await approving(tester);
      await start(tester);
      await clearSteps(tester, to: 4);

      expect(find.text('Etapa 5 de 5'), findsOneWidget);
      await noneOfThis(tester);
      expect(primary(tester).label, chooseTopic);
      // Leading to the summary, not to another step.
      await answer(tester, 'Falta começo, meio ou fim?', 'Sim');
      expect(primary(tester).label, seeSummary);
      await answer(tester, 'Falta começo, meio ou fim?', 'Não');
      await answer(tester, others, 'Sim');
      expect(primary(tester).label, seeSummary);
      await tapPrimary(tester);

      expect(find.text(reviewTitle), findsOneWidget);
      expect(row('Música'), findsNothing);
      expect(primary(tester).label, teamLabel);
    });

    testWidgets('the next page opens at its top', (tester) async {
      // Short enough that a step scrolls.
      await approving(tester, size: const Size(360, 480));
      await start(tester);
      await noneOfThis(tester);
      await tester.ensureVisible(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(scrolled(tester), greaterThan(0));

      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();

      expect(find.text('Etapa 2 de 5'), findsOneWidget);
      expect(scrolled(tester), 0);
    });

    testWidgets('"Voltar" and the system back go one page back with the '
        'answers kept; on "Antes de começar" they leave for the video', (
      tester,
    ) async {
      final h = await approving(tester);
      await start(tester);
      await clearSteps(tester, to: 1);

      expect(find.text('Etapa 2 de 5'), findsOneWidget);
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(QuietAction),
          matching: find.text('Voltar'),
        ),
      );
      expect(find.text('Etapa 1 de 5'), findsOneWidget);
      expect(picked(tester, hits, 'Não'), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(checkedByApp), findsOneWidget);
      expect(picked(tester, tie, 'Não'), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(h.location(tester), '/curadoria/v1');
    });

    testWidgets('coming back to a video restores the answers, theme, band '
        'and note', (tester) async {
      await approving(
        tester,
        draft: () => kept(
          draftJson(
            answers: {'c25': 'ok', 'c03': 'ok'},
            theme: 'musica',
            band: '5-8',
          ),
        ),
      );

      expect(picked(tester, tie, 'Não'), isTrue);
      expect(picked(tester, paid, 'Não'), isTrue);
      expect(primary(tester).onPressed, isNotNull);
      await tapPrimary(tester);
      await clearSteps(tester);

      expect(chosen(tester, 'Música'), isTrue);
      expect(chosen(tester, '5 a 8 anos'), isTrue);
    });

    testWidgets('coming back to a doubt restores its note', (tester) async {
      final h = await approving(
        tester,
        draft: () => kept(
          draftJson(
            answers: {'c25': 'ok', 'c03': 'ok', 'c04': 'ok', 'c07': 'doubt'},
            note: 'A tristeza pesa.',
          ),
        ),
      );

      expect(draftSaves(h), isEmpty, reason: 'restoring is not a change');
      await tapPrimary(tester);
      await tapPrimary(tester);
      await clearSteps(tester, from: 2);

      expect(primary(tester).label, teamLabel);
      expect(find.text('A tristeza pesa.'), findsOneWidget);
    });

    testWidgets('a draft that failed to read is read again before the first '
        'write, which keeps what it held', (tester) async {
      var fail = true;
      final h = await approving(
        tester,
        draft: () => fail
            ? problem(503, 'unavailable')
            : kept(draftJson(answers: {'c04': 'ok', 'c07': 'ok'})),
      );
      int reads() => h.actions
          .where((c) => c == 'GET /v1/curation/videos/v1/draft')
          .length;
      final before = reads();

      await answer(tester, tie, 'Não');
      expect(reads(), before + 1);
      expect(draftSaves(h), isEmpty, reason: 'the kept draft is still unread');

      fail = false;
      await answer(tester, paid, 'Não');
      expect(reads(), before + 2);
      expect(draftSaves(h), [
        'PUT /v1/curation/videos/v1/draft '
            '{"checklist_version":"2026-11-11",'
            '"answers":{"c25":"ok","c03":"ok","c04":"ok","c07":"ok"}}',
      ]);
      expect(picked(tester, tie, 'Não'), isTrue);
      expect(picked(tester, paid, 'Não'), isTrue);
    });

    testWidgets('a late draft read with the same note leaves the cursor '
        'where it was', (tester) async {
      Completer<http.Response>? held;
      await approving(
        tester,
        draft: () => held?.future ?? Future.value(problem(503, 'unavailable')),
      );
      await start(tester);
      await noneOfThis(tester);
      await answer(tester, sad, 'Não sei');
      await tapPrimary(tester);
      await clearSteps(tester, from: 2);

      held = Completer<http.Response>();
      final field = find.widgetWithText(TextField, doubtNoteLabel);
      await tester.enterText(field, 'Pesa?');
      await tester.pump();
      final note = tester.widget<TextField>(field).controller!;
      note.selection = const TextSelection.collapsed(offset: 2);
      held.complete(kept(draftJson(answers: {'c25': 'ok'}, note: 'Pesa?')));
      await tester.pumpAndSettle();

      expect(note.text, 'Pesa?');
      expect(note.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('each answer is written to the draft', (tester) async {
      final h = await approving(tester);

      await answer(tester, tie, 'Não');
      await answer(tester, paid, 'Sim');

      expect(
        draftSaves(h),
        contains(
          'PUT /v1/curation/videos/v1/draft '
          '{"checklist_version":"2026-11-11",'
          '"answers":{"c25":"ok","c03":"appears"}}',
        ),
      );
    });

    testWidgets('the shortcut, the theme, the band and the note are written '
        'to the draft', (tester) async {
      final h = await approving(tester);
      await start(tester);
      await noneOfThis(tester);
      expect(draftSaves(h).last, contains('"c04":"ok","c07":"ok"'));
      await answer(tester, sad, 'Não sei');
      await tapPrimary(tester);
      await clearSteps(tester, from: 2);
      await tester.enterText(
        find.widgetWithText(TextField, doubtNoteLabel),
        'Pesa?',
      );
      await tester.pumpAndSettle();
      expect(draftSaves(h).last, endsWith('"note":"Pesa?"}'));

      await tapOn(tester, change('Violência e medo'));
      await answer(tester, sad, 'Não');
      await tapPrimary(tester);
      await choose(tester, 'Música');
      expect(draftSaves(h).last, contains('"theme":"musica"'));
      await choose(tester, '9 a 12 anos');
      expect(
        draftSaves(h).last,
        contains('"theme":"musica","min_age_band":"9-12"'),
      );
    });
  });

  group('the theme and band', () {
    testWidgets('offer the six themes and the three bands, none chosen; the '
        'primary waits with its hint', (tester) async {
      await approving(tester);
      await toTopic(tester);

      expect(find.text('Tema'), findsOneWidget);
      expect(find.text('A partir de'), findsOneWidget);
      for (final label in [...allThemes, ...bands]) {
        expect(row(label), findsOneWidget, reason: label);
        expect(chosen(tester, label), isFalse, reason: label);
      }
      // Not a step: it leads to the summary.
      expect(primary(tester).label, seeSummary);
      expect(seeSummary, 'Ver resumo');
      expect(primary(tester).onPressed, isNull);
      expect(find.text(approveHint), findsOneWidget);
      await choose(tester, 'Bichos');
      await choose(tester, 'Música');
      expect(chosen(tester, 'Bichos'), isFalse);
      expect(chosen(tester, 'Música'), isTrue);
      expect(primary(tester).onPressed, isNull);
      await choose(tester, '9 a 12 anos');
      expect(primary(tester).onPressed, isNotNull);
    });

    testWidgets('every choice is a radio', (tester) async {
      final semantics = tester.ensureSemantics();
      await approving(tester);
      await toTopic(tester);

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

    testWidgets('say every video must be Livre and open the criteria of '
        'each band on the site', (tester) async {
      final h = await approving(tester);
      await toTopic(tester);

      expect(find.text(curationRule), findsOneWidget);
      await tapOn(tester, find.text(curationCriteriaLink));

      expect(h.links.opened, [kCurationUrl]);
      expect(h.location(tester), '/curadoria/v1/aprovar');
    });

    testWidgets('the criteria line reads as a link', (tester) async {
      final semantics = tester.ensureSemantics();
      await approving(tester);
      await toTopic(tester);
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
      await toTopic(tester);
      await choose(tester, '2 a 4 anos');

      expect(find.text(underTwoAdvice), findsNothing);
    });

    testWidgets('a Sim that allows from 9 a 12 keeps the younger bands out '
        'and says why; answered again from the review, it takes back a band '
        'chosen', (tester) async {
      await approving(tester);
      await start(tester);
      await clearSteps(tester, to: 4);
      await noneOfThis(tester);
      await answer(tester, dating, 'Sim');
      await tapPrimary(tester);

      expect(tester.widget<SelectableRow>(row('2 a 4 anos')).onTap, isNull);
      expect(tester.widget<SelectableRow>(row('5 a 8 anos')).onTap, isNull);
      expect(find.text(answersBandLine(AgeBand.from9To12)), findsOneWidget);
      expect(
        answersBandLine(AgeBand.from9To12),
        'Pelas respostas, este vídeo serve a partir de 9 a 12 anos.',
      );
      await choose(tester, 'Música');
      await choose(tester, '9 a 12 anos');
      await tapPrimary(tester);
      expect(primary(tester).label, approveLabel);

      await tapOn(tester, change('Ritmo e canal'));
      await answer(tester, dating, 'Não');
      await tapPrimary(tester);
      expect(find.text(reviewTitle), findsOneWidget);
      await tapOn(tester, change(topicTitle));
      expect(find.textContaining('Pelas respostas'), findsNothing);
      await choose(tester, '2 a 4 anos');
      await tapPrimary(tester);
      expect(find.text(reviewTitle), findsOneWidget);

      await tapOn(tester, change('Ritmo e canal'));
      await answer(tester, fast, 'Sim');
      await tapPrimary(tester);
      expect(row('Música'), findsOneWidget, reason: 'the band is asked again');
      expect(chosen(tester, '2 a 4 anos'), isFalse);
      expect(find.text(answersBandLine(AgeBand.from5To8)), findsOneWidget);
      expect(primary(tester).onPressed, isNull);
    });
  });

  group('a long video', () {
    /// The flow over "Baby Shark" running [minutes] minutes, opened
    /// directly.
    Future<Harness> longApproving(WidgetTester tester, int minutes) =>
        approving(
          tester,
          video: (id) => detailOf(
            queuedJson(
              id,
              'Baby Shark',
              channel: 'Canal Baby Shark',
              seconds: minutes * 60,
            ),
          ),
        );

    testWidgets('past 20 minutes adds the "Vídeo longo" step and sends its '
        'answers', (tester) async {
      final h = await longApproving(tester, 25);
      await start(tester);
      expect(find.text('Etapa 1 de 6'), findsOneWidget);
      await clearSteps(tester, to: 5);
      expect(find.text('Etapa 6 de 6'), findsOneWidget);
      expect(find.text('Vídeo longo'), findsOneWidget);
      await noneOfThis(tester);
      await answer(tester, 'Aparecem anúncios no meio do vídeo?', 'Sim');
      await tapPrimary(tester);
      await choose(tester, 'Música');
      await choose(tester, '2 a 4 anos');
      await tapPrimary(tester);
      expect(primary(tester).label, approveLabel, reason: 'ads only noted');
      await tapPrimary(tester);

      expect(sent(h)['answers'], {
        ...allNos,
        'c26': 'ok',
        'c27': 'ok',
        'c28': 'appears',
      });
    });

    testWidgets('a video that fails to read offers to try again: its length '
        'decides the questions', (tester) async {
      var fail = true;
      await approving(
        tester,
        video: (id) => fail
            ? http.Response('', 500)
            : detailOf(queuedJson(id, 'Baby Shark', seconds: 25 * 60)),
      );
      expect(find.text(tie), findsNothing);
      expect(find.text(Copy.genericRetry), findsOneWidget);

      fail = false;
      await tapPrimary(tester);
      expect(find.text(tie), findsOneWidget);
      await start(tester);
      expect(find.text('Etapa 1 de 6'), findsOneWidget);
    });

    testWidgets('past 60 minutes disables "2 a 4 anos" and says why', (
      tester,
    ) async {
      await longApproving(tester, 61);
      await start(tester);
      await clearSteps(tester, to: 6);

      expect(find.text(tooLongForYoungestLine), findsOneWidget);
      expect(find.textContaining('Pelas respostas'), findsNothing);
      expect(tester.widget<SelectableRow>(row('2 a 4 anos')).onTap, isNull);
    });

    testWidgets('past 60 minutes with a fast pace says both', (tester) async {
      await longApproving(tester, 61);
      await start(tester);
      await clearSteps(tester, to: 4);
      await noneOfThis(tester);
      await answer(tester, fast, 'Sim');
      await tapPrimary(tester);
      await clearSteps(tester, from: 6, to: 6);

      expect(find.text(tooLongForYoungestLine), findsOneWidget);
      expect(find.text(answersBandLine(AgeBand.from5To8)), findsOneWidget);
      expect(tester.widget<SelectableRow>(row('2 a 4 anos')).onTap, isNull);
    });
  });

  group('the review', () {
    testWidgets('sums up each step, "tudo Não" or its Sim and Não sei, each '
        'with "mudar", and the reminder', (tester) async {
      await approving(tester);
      await start(tester);
      await answer(tester, hits, 'Não');
      await answer(tester, sad, 'Não sei');
      await tapPrimary(tester);
      await clearSteps(tester, from: 2, to: 4);
      await noneOfThis(tester);
      await answer(tester, others, 'Sim');
      await tapPrimary(tester);

      expect(find.text(reviewTitle), findsOneWidget);
      expect(find.text('Não sei: $sad'), findsOneWidget);
      expect(find.text('Sim: $others'), findsOneWidget);
      expect(find.text(allNo), findsNWidgets(4));
      for (final title in [
        'Antes de começar',
        'Violência e medo',
        'Linguagem e respeito',
        'Consumo e publicidade',
        'Saúde e segurança',
        'Ritmo e canal',
      ]) {
        expect(change(title), findsOneWidget, reason: title);
      }
      expect(change(topicTitle), findsNothing, reason: 'nothing approved');
      expect(find.text(differenceReminder), findsOneWidget);
      expect(primary(tester).label, teamLabel);
    });

    testWidgets('"mudar" goes back to its step and on to the review; an '
        'answer that now approves asks the theme and band first', (
      tester,
    ) async {
      await approving(tester);
      await start(tester);
      await answer(tester, hits, 'Não');
      await answer(tester, sad, 'Sim');
      await tapPrimary(tester);
      await clearSteps(tester, from: 2);
      expect(primary(tester).label, teamLabel);

      await tapOn(tester, change('Linguagem e respeito'));
      expect(find.text('Etapa 2 de 5'), findsOneWidget);
      expect(primary(tester).label, seeSummary);
      await tapPrimary(tester);
      expect(find.text(reviewTitle), findsOneWidget);

      await tapOn(tester, change('Violência e medo'));
      await answer(tester, sad, 'Não');
      await tapPrimary(tester);
      expect(row('Música'), findsOneWidget);
      await choose(tester, 'Música');
      await choose(tester, '5 a 8 anos');
      await tapPrimary(tester);

      expect(find.text(reviewTitle), findsOneWidget);
      expect(find.text(nb('Música · 5 a 8 anos')), findsOneWidget);
      expect(change(topicTitle), findsOneWidget);
      expect(primary(tester).label, approveLabel);
    });

    testWidgets('back on "Antes de começar" opened by "mudar" returns to the '
        'review, not to the video', (tester) async {
      final h = await approving(tester);
      await toReview(tester);

      await tapOn(tester, change('Antes de começar'));
      expect(find.text(checkedByApp), findsOneWidget);
      expect(primary(tester).label, seeSummary);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(reviewTitle), findsOneWidget);
      expect(h.location(tester), '/curadoria/v1/aprovar');
    });

    testWidgets('a tie marked from the review ends there: back leaves for '
        'the video, never the review, and nothing is sent', (tester) async {
      final h = await approving(tester);
      await toReview(tester);

      await tapOn(tester, change('Antes de começar'));
      await answer(tester, tie, 'Sim');
      expect(find.text(conflictLine), findsOneWidget);
      expect(primary(tester).label, 'Voltar para a fila');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(reviewTitle), findsNothing);
      expect(h.location(tester), '/curadoria/v1');
      expect(posts(h), isEmpty);
    });

    testWidgets('"Aprovar" sends the approval once with every answer, then '
        'the done state back to the queue', (tester) async {
      final reply = Completer<http.Response>();
      final h = await approving(tester, review: (_) => reply.future);

      await approve(tester, settle: false);
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      reply.complete(json(201, {'video_state': 'pending'}));
      await tester.pumpAndSettle();

      expect(posts(h), hasLength(1));
      expect(
        posts(h).single,
        startsWith('POST /v1/curation/videos/v1/reviews'),
      );
      expect(sent(h), {
        'decision': 'approve',
        'theme': 'musica',
        'min_age_band': '5-8',
        'checklist_version': '2026-11-11',
        'answers': allNos,
      });
      expect(find.widgetWithText(Notice, approved), findsOneWidget);
      await tapOn(tester, find.text('Voltar para a fila'));
      expect(h.location(tester), '/curadoria');
    });

    testWidgets('"Enviar para a equipe" sends the answers and the note, with '
        'no theme or band, and says the team decides', (tester) async {
      final h = await approving(
        tester,
        review: (_) => json(201, {'video_state': 'held'}),
      );

      await toTeam(tester);
      expect(find.text(doubtLine), findsOneWidget);
      expect(find.text(doubtRevisitLine), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, doubtNoteLabel),
        '  A tristeza é o tema.  ',
      );
      await tester.pump();
      expect(primary(tester).label, teamLabel);
      await tapPrimary(tester);

      expect(sent(h), {
        'decision': 'approve',
        'checklist_version': '2026-11-11',
        'answers': {...allNos, 'c07': 'doubt'},
        'note': 'A tristeza é o tema.',
      });
      expect(find.widgetWithText(Notice, doubtSent), findsOneWidget);
      expect(doubtSent, 'Enviamos o vídeo para a equipe da Coding4u decidir.');
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

      await toTeam(tester);

      expect(find.text(doubtRevisitLine), findsOneWidget);
      expect(find.text(doubtLine), findsNothing);
    });

    testWidgets('a note written for the team is not sent once the answers '
        'approve', (tester) async {
      final h = await approving(
        tester,
        review: (_) => json(201, {'video_state': 'pending'}),
      );

      await toTeam(tester);
      await tester.enterText(
        find.widgetWithText(TextField, doubtNoteLabel),
        'Pensei melhor.',
      );
      await tester.pump();
      await tapOn(tester, change('Violência e medo'));
      await answer(tester, sad, 'Não');
      await tapPrimary(tester);
      await choose(tester, 'Música');
      await choose(tester, '5 a 8 anos');
      await tapPrimary(tester);
      await tapPrimary(tester);

      expect(sent(h).containsKey('note'), isFalse);
      expect(find.widgetWithText(Notice, approved), findsOneWidget);
    });

    testWidgets('"Recusar" opens the refusal with the questions that refuse '
        'ticked, sending nothing', (tester) async {
      final h = await approving(tester);

      await answer(tester, tie, 'Não');
      await answer(tester, paid, 'Sim');
      await tapPrimary(tester);
      await answer(tester, hits, 'Sim');
      await answer(tester, sad, 'Não');
      await tapPrimary(tester);
      await clearSteps(tester, from: 2);
      expect(primary(tester).label, refuseLabel);
      await tapPrimary(tester);

      final at = Uri.parse(h.location(tester));
      expect(at.path, '/curadoria/v1/recusar');
      expect(Routes.refuseItems(at.queryParameters['itens']), ['c03', 'c04']);
      expect(posts(h), isEmpty);
    });
  });

  group('answers from the server', () {
    testWidgets('a network failure keeps everything, and the primary tries '
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
      expect(find.text(reviewTitle), findsOneWidget);
      fail = false;
      await tapPrimary(tester);
      expect(posts(h), hasLength(2));
      expect(find.text(approved), findsOneWidget);
    });

    testWidgets('validation goes back to the theme and band, cleared, and '
        'on to the review again', (tester) async {
      var refuse = true;
      final h = await approving(
        tester,
        review: (_) => refuse
            ? problem(422, 'validation')
            : json(201, {'video_state': 'pending'}),
      );

      await approve(tester);

      expect(find.text(approvalRefused), findsOneWidget);
      expect(find.byType(ErrorNote), findsNothing);
      expect(chosen(tester, 'Música'), isFalse);
      expect(chosen(tester, '5 a 8 anos'), isFalse);
      expect(primary(tester).onPressed, isNull);
      await choose(tester, 'Bichos');
      expect(find.text(approvalRefused), findsNothing);
      await choose(tester, '5 a 8 anos');
      await tapPrimary(tester);
      expect(find.text(reviewTitle), findsOneWidget);
      refuse = false;
      await tapPrimary(tester);
      expect(posts(h), hasLength(2));
      expect(find.text(approved), findsOneWidget);
    });

    testWidgets('checklist_band says why and goes back to the band, '
        'cleared', (tester) async {
      await approving(tester, review: (_) => problem(422, 'checklist_band'));

      await approve(tester);

      expect(
        find.widgetWithText(
          ErrorNote,
          Copy.forError(const ApiError(status: 422, code: 'checklist_band')),
        ),
        findsOneWidget,
      );
      expect(chosen(tester, 'Música'), isTrue);
      expect(chosen(tester, '5 a 8 anos'), isFalse);
    });

    testWidgets('checklist_refuses opens the refusal', (tester) async {
      final h = await approving(
        tester,
        review: (_) => problem(422, 'checklist_refuses'),
      );

      await approve(tester);

      expect(Uri.parse(h.location(tester)).path, '/curadoria/v1/recusar');
    });

    testWidgets('checklist_outdated reads the list and the draft again and '
        'keeps the unchanged answers, saying why', (tester) async {
      var outdated = false;
      var readsAfter = 0;
      final h = await approving(
        tester,
        review: (_) {
          outdated = true;
          return problem(409, 'checklist_outdated');
        },
        // The server keeps only the answers to questions left unchanged.
        draft: () => outdated && ++readsAfter > 0
            ? kept(draftJson(answers: {'c25': 'ok', 'c03': 'ok'}, ended: true))
            : kept(draftJson(ended: true)),
      );

      await approve(tester);

      expect(
        find.widgetWithText(
          ErrorNote,
          Copy.forError(
            const ApiError(status: 409, code: 'checklist_outdated'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        h.actions.where((a) => a == 'GET /v1/curation/checklist'),
        hasLength(2),
      );
      expect(readsAfter, 1);
      expect(find.text(checkedByApp), findsOneWidget);
      expect(picked(tester, tie, 'Não'), isTrue);
      expect(picked(tester, paid, 'Não'), isTrue);
      await tapPrimary(tester);
      expect(
        picked(tester, hits, 'Não'),
        isFalse,
        reason: 'a changed question unanswered',
      );
      expect(primary(tester).onPressed, isNull);
    });

    testWidgets('not_watched says the video must play to its end and keeps '
        'the answers', (tester) async {
      var refuse = true;
      final h = await approving(
        tester,
        review: (_) => refuse
            ? problem(409, 'not_watched')
            : json(201, {'video_state': 'pending'}),
      );

      await approve(tester);

      expect(
        find.widgetWithText(
          ErrorNote,
          Copy.forError(const ApiError(status: 409, code: 'not_watched')),
        ),
        findsOneWidget,
      );
      expect(find.text(reviewTitle), findsOneWidget);
      expect(find.text(nb('Música · 5 a 8 anos')), findsOneWidget);
      refuse = false;
      await tapPrimary(tester);
      expect(posts(h), hasLength(2));
      expect(
        jsonDecode(posts(h).last.split(' ').skip(2).join(' '))['answers'],
        allNos,
      );
    });

    testWidgets('an end report that failed is sent again before approving', (
      tester,
    ) async {
      var fail = true;
      final h = await approving(
        tester,
        ended: () => fail
            ? problem(503, 'unavailable')
            : json(200, {'draft': draftJson(ended: true)}),
      );
      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();
      expect(posts(h), ['POST /v1/curation/videos/v1/draft/ended']);
      fail = false;

      await approve(tester);

      expect(
        [for (final p in posts(h)) p.split(' ').take(2).join(' ')],
        [
          'POST /v1/curation/videos/v1/draft/ended',
          'POST /v1/curation/videos/v1/draft/ended',
          'POST /v1/curation/videos/v1/reviews',
        ],
      );
      expect(find.text(approved), findsOneWidget);
    });

    testWidgets('an end reported is not sent again', (tester) async {
      final h = await approving(tester);
      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();

      await approve(tester);

      expect(
        [for (final p in posts(h)) p.split(' ').take(2).join(' ')],
        [
          'POST /v1/curation/videos/v1/draft/ended',
          'POST /v1/curation/videos/v1/reviews',
        ],
      );
    });

    testWidgets('an end the video screen failed to report is sent again '
        'before approving', (tester) async {
      var fail = true;
      final h = await approving(
        tester,
        initial: '/curadoria/v1',
        ended: () => fail
            ? problem(503, 'unavailable')
            : json(200, {'draft': draftJson(ended: true)}),
      );
      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();
      expect(posts(h), ['POST /v1/curation/videos/v1/draft/ended']);
      fail = false;

      await tapOn(tester, find.text('Revisar vídeo'));
      await approve(tester);

      expect(
        [for (final p in posts(h)) p.split(' ').take(2).join(' ')],
        [
          'POST /v1/curation/videos/v1/draft/ended',
          'POST /v1/curation/videos/v1/draft/ended',
          'POST /v1/curation/videos/v1/reviews',
        ],
      );
      expect(find.text(approved), findsOneWidget);
    });

    testWidgets('an end another account saw is never sent for the next '
        'one', (tester) async {
      final h = await approving(
        tester,
        initial: '/curadoria/v1',
        ended: () => problem(503, 'unavailable'),
      );
      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();
      expect(posts(h), ['POST /v1/curation/videos/v1/draft/ended']);

      await h.services.client.forgetSession();
      await tester.pumpAndSettle();
      h.email = 'bia@example.com';
      h.services.client.rememberSession(csrfToken: 'csrf-b');
      await tester.pumpAndSettle();
      goTo(tester, '/curadoria/v1/aprovar');
      await tester.pumpAndSettle();
      await approve(tester);

      expect(
        [for (final p in posts(h)) p.split(' ').take(2).join(' ')],
        [
          'POST /v1/curation/videos/v1/draft/ended',
          'POST /v1/curation/videos/v1/reviews',
        ],
      );
    });

    testWidgets('an end the video screen reported is not sent again', (
      tester,
    ) async {
      final h = await approving(tester, initial: '/curadoria/v1');
      h.adultPlayer.opened.last.emit(const PlayerEnded());
      await tester.pumpAndSettle();

      await tapOn(tester, find.text('Revisar vídeo'));
      await approve(tester);

      expect(
        [for (final p in posts(h)) p.split(' ').take(2).join(' ')],
        [
          'POST /v1/curation/videos/v1/draft/ended',
          'POST /v1/curation/videos/v1/reviews',
        ],
      );
    });

    testWidgets('checklist_outdated whose new list fails to read offers to '
        'try again, never the old list', (tester) async {
      var reads = 0;
      final h = await approving(
        tester,
        checklist: () => ++reads == 2
            ? problem(503, 'unavailable')
            : json(200, checklistJson),
        review: (_) => problem(409, 'checklist_outdated'),
      );

      await approve(tester);

      expect(find.byType(AnswerChoice), findsNothing);
      expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
      await tapPrimary(tester);

      expect(reads, 3);
      expect(posts(h), hasLength(1));
      expect(find.text(checkedByApp), findsOneWidget);
      expect(primary(tester).onPressed, isNull);
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
      (
        'conflict_of_interest',
        409,
        'Você tem vínculo com este canal, então a revisão dele fica com '
            'outros curadores.',
      ),
    ]) {
      testWidgets('$code goes back to the queue with a notice', (tester) async {
        final h = await approving(tester, review: (_) => problem(status, code));

        await approve(tester);

        expect(h.location(tester), '/curadoria');
        expect(find.text(notice), findsOneWidget);
      });
    }

    testWidgets('not_curator goes home with a notice', (tester) async {
      final h = await approving(
        tester,
        review: (_) => problem(403, 'not_curator'),
      );

      await approve(tester);

      expect(h.location(tester), '/');
      expect(
        find.text('Você não faz mais parte da curadoria.'),
        findsOneWidget,
      );
    });

    testWidgets('back from the first page returns to the review', (
      tester,
    ) async {
      final h = await approving(tester);

      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/curadoria/v1');
    });
  });
}
