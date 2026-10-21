import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/review_screen.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid/kid_player.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../kid/fake_player.dart';
import 'curation_api_test.dart' show rejectionJson, reviewJson;
import 'fixtures.dart';
import 'queue_screen_test.dart' show goTo;

final babyShark = queuedJson(
  'v1',
  'Baby Shark',
  channel: 'Canal Baby Shark',
  seconds: 300,
);

Future<Harness> review(
  WidgetTester tester, {
  FutureOr<http.Response> Function(String id)? video,
  FutureOr<http.Response> Function(http.Request)? queue,
  String initial = '/curadoria/v1',
}) async {
  final h =
      Harness(
          signedIn: true,
          api: curatorApi(
            video: video ?? (_) => detailOf(babyShark),
            queue: queue,
          ),
        )
        ..family = ownerFamily
        ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

FakePlayback? player(Harness h) => h.adultPlayer.current;

Finder get window => find.byKey(FakePlayback.viewKey);

/// The failed window keeps its place: the 16:9 box at [width], its edge
/// drawn square in a 1.5 px outline stroke, [message]'s error note
/// centred inside with 16 px around it.
void expectFailedWindow(
  WidgetTester tester,
  String message, {
  required double width,
}) {
  final note = find.widgetWithText(ErrorNote, message);
  expect(note, findsOneWidget);
  final frame = find
      .ancestor(
        of: note,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border != null,
        ),
      )
      .first;
  final edge = tester.widget<DecoratedBox>(frame).decoration as BoxDecoration;
  final outline = tester.element(note).palette.outline;
  expect(edge.border, Border.all(color: outline, width: 1.5));
  expect(edge.borderRadius, isNull, reason: 'the window\'s square edge');
  final box = tester.getRect(frame);
  expect(box.width, width);
  expect(box.height, closeTo(width * 9 / 16, .01));
  final inside = tester.getRect(note);
  expect(inside.left - box.left, greaterThanOrEqualTo(16));
  expect(box.right - inside.right, greaterThanOrEqualTo(16));
  expect(inside.center.dx, closeTo(box.center.dx, .5));
  expect(inside.center.dy, closeTo(box.center.dy, .5));
}

void main() {
  testWidgets('reads in order: the title, the channel, length and round, '
      'this round\'s reviews by role, the player, then the two doors', (
    tester,
  ) async {
    await review(
      tester,
      video: (_) => detailOf(
        {...babyShark, 'round': 2},
        reviews: [reviewJson, rejectionJson],
      ),
    );

    expect(find.text('Revisar'), findsOneWidget);
    final order = [
      find.text('Baby Shark'),
      find.text(nb('Canal Baby Shark · 5 min · Rodada 2')),
      find.text(nb('Pedagogo(a) aprovou · Bichos · 5 a 8 anos')),
      find.text('Cuidador(a) recusou'),
      find.text('Tem propaganda.'),
      window,
      find.widgetWithText(DoorRow, 'Aprovar'),
      find.widgetWithText(DoorRow, 'Recusar'),
    ];
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    expect(find.text('Responder às perguntas'), findsOneWidget);
    expect(find.text('Marcar o que aparece'), findsOneWidget);
    expect(find.text('Revisita', findRichText: true), findsNothing);
  });

  testWidgets('the reviews are read, never targets', (tester) async {
    await review(
      tester,
      video: (_) => detailOf(babyShark, reviews: [rejectionJson]),
    );

    expect(
      find.ancestor(
        of: find.text('Cuidador(a) recusou'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('a doubt shows its note under its line, as a refusal does', (
    tester,
  ) async {
    await review(
      tester,
      video: (_) => detailOf(babyShark, reviews: [doubtJson]),
    );

    expect(find.text('Não sei se a tristeza pesa.'), findsOneWidget);
  });

  testWidgets('with no reviews yet, it says so', (tester) async {
    await review(tester);

    expect(find.text(noReviews), findsOneWidget);
  });

  testWidgets('a revisit says since when the video is in the catalogue', (
    tester,
  ) async {
    final year = clock.now().year;
    await review(
      tester,
      video: (_) => detailOf({
        ...queuedJson('v1', 'Baby Shark', revisit: true),
        'last_reviewed_at': '$year-03-03T12:00:00Z',
      }),
    );

    expect(find.text('Revisita: no catálogo desde 3 de março'), findsOne);
  });

  testWidgets('the player loads the video without playing it, square-'
      'edged 16:9 at the column\'s width', (tester) async {
    final h = await review(tester);

    expect(player(h)?.youtubeId, 'yt-v1');
    expect(player(h)!.calls, isEmpty, reason: 'no autoplay');
    final size = tester.getSize(window);
    final column = tester.getSize(find.widgetWithText(DoorRow, 'Aprovar'));
    expect(size.width, column.width);
    expect(size.height, closeTo(size.width * 9 / 16, .01));
    for (final cover in [ClipRRect, ClipPath, GestureDetector, InkWell]) {
      expect(
        find.ancestor(of: window, matching: find.byType(cover)),
        findsNothing,
        reason: '$cover on the window',
      );
    }
  });

  testWidgets('a link out of the player opens in the browser, the video '
      'staying', (tester) async {
    final h = await review(tester);
    final url = Uri.parse('https://www.youtube.com/watch?v=yt-v1');

    player(h)!.emit(PlayerLeaving(url));
    await tester.pumpAndSettle();

    expect(h.links.opened, [url]);
    expect(player(h)!.closed, isFalse);
    expect(window, findsOneWidget);
  });

  testWidgets('another video playing in place stops it, and the video '
      'under review loads again, not playing', (tester) async {
    final h = await review(tester);
    final first = player(h)!;

    first.emit(const PlayerStrayed());
    await tester.pumpAndSettle();

    expect(first.closed, isTrue);
    expect(h.adultPlayer.opened, hasLength(2));
    expect(player(h)!.youtubeId, 'yt-v1');
    expect(player(h)!.calls, isEmpty);
    expect(window, findsOneWidget);
  });

  testWidgets('a player that fails keeps the window\'s place, framed, with the '
      'error note inside; the doors still there', (tester) async {
    final h = await review(tester);

    player(h)!.emit(const PlayerFailed());
    await tester.pumpAndSettle();

    expect(player(h)!.closed, isTrue);
    expect(window, findsNothing);
    expectFailedWindow(
      tester,
      playerFailed,
      width: tester.getSize(find.widgetWithText(DoorRow, 'Aprovar')).width,
    );
    expect(find.widgetWithText(DoorRow, 'Aprovar'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Recusar'), findsOneWidget);
  });

  testWidgets('the doors open approving and refusing; the player pauses '
      'beneath them', (tester) async {
    final h = await review(tester);

    await tester.ensureVisible(find.text('Aprovar'));
    await tester.tap(find.text('Aprovar'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/curadoria/v1/aprovar');
    // The approval opens its own player; the review's waits beneath.
    expect(h.adultPlayer.opened.first.calls, ['pause']);

    goTo(tester, '/curadoria/v1');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Recusar'));
    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/curadoria/v1/recusar');
  });

  testWidgets('leaving the review lets the player go', (tester) async {
    final h = await review(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria');
    expect(player(h)!.closed, isTrue);
  });

  testWidgets('at 390 × 844, the window starts above the lower third and '
      'the doors are one scroll away at most (FIRST VIEWPORT)', (tester) async {
    await review(
      tester,
      video: (_) => detailOf(
        {...babyShark, 'round': 2},
        reviews: [reviewJson, rejectionJson],
      ),
    );

    expect(tester.getTopLeft(window).dy, lessThan(844 * 2 / 3));
    expect(
      tester.getBottomLeft(find.widgetWithText(DoorRow, 'Recusar')).dy,
      lessThan(844 * 1.5),
    );
  });

  testWidgets('while it loads, the placeholder says what is loading; a '
      'failed read offers "Tentar de novo"', (tester) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    var fail = true;
    final h = await review(
      tester,
      video: (_) => answer.isCompleted
          ? (fail ? problem(503, 'unavailable') : detailOf(babyShark))
          : answer.future,
    );

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando o vídeo'), findsOneWidget);
    expect(h.adultPlayer.opened, isEmpty);
    answer.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Baby Shark'), findsOneWidget);
    expect(window, findsOneWidget);
    semantics.dispose();
  });

  for (final (code, status, notice) in [
    ('not_found', 404, 'Esse vídeo não está mais na curadoria.'),
    ('already_reviewed', 409, 'Esse vídeo já saiu da fila.'),
  ]) {
    testWidgets('$code goes back to the queue, read again, with a notice', (
      tester,
    ) async {
      final h = await review(tester, video: (_) => problem(status, code));

      expect(h.location(tester), '/curadoria');
      expect(find.text(notice), findsOneWidget);
      expect(
        h.actions.where((c) => c.startsWith('GET /v1/curation/queue')),
        hasLength(1),
      );
    });
  }

  testWidgets('not_curator goes home with a notice', (tester) async {
    final h = await review(tester, video: (_) => problem(403, 'not_curator'));

    expect(h.location(tester), '/');
    expect(find.text('Você não faz mais parte da curadoria.'), findsOneWidget);
  });
}
