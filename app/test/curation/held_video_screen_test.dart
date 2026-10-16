import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/held_video_screen.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid/kid_player.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../kid/fake_player.dart';
import 'fixtures.dart';
import 'held_videos_screen_test.dart' show refused;
import 'appoint_screen_test.dart' show tapOn;
import 'review_screen_test.dart' show expectFailedWindow;

Future<Harness> heldVideo(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? list,
  FutureOr<http.Response> Function(http.Request)? settle,
  List<String> roles = const ['admin'],
}) async {
  final h =
      Harness(
          signedIn: true,
          api: adminApi(
            held: list ?? () => heldList([refused]),
            settle: settle,
          ),
        )
        ..family = ownerFamily
        ..roles = roles;
  await h.pump(tester, initial: '/moderacao/retidos/v1');
  return h;
}

Finder get window => find.byKey(FakePlayback.viewKey);
Finder get reopen => find.widgetWithText(FilledButton, 'Reabrir para revisão');
Finder get removeForGood => find.widgetWithText(QuietAction, 'Remover de vez');

/// The confirmation's own [label] action, apart from the screen's.
Finder confirming(String label) => find.descendant(
  of: find.byType(DestructiveConfirmation),
  matching: find.widgetWithText(FilledButton, label),
);

const why = 'O canal trocou o vídeo.';

/// Opens [action]'s confirmation, gives the reason (padded, to be sent
/// trimmed) and confirms it.
Future<void> settleWith(WidgetTester tester, String action) async {
  final (open, label) = action == 'reopen'
      ? (reopen, 'Reabrir para revisão')
      : (removeForGood, 'Remover de vez');
  await tapOn(tester, open);
  await tester.enterText(find.widgetWithText(TextField, 'Motivo'), '  $why ');
  await tester.pump();
  await tapOn(tester, confirming(label));
}

List<String> writes(Harness h) =>
    h.actions.where((a) => a.startsWith('POST')).toList();

int listReads(Harness h) =>
    h.actions.where((a) => a.startsWith('GET /v1/moderation/videos')).length;

void main() {
  testWidgets('reads in order: the title, why it is held, each refusal by '
      'role with its reason, the reports by reason with their notes, the '
      'player, then the two actions', (tester) async {
    await heldVideo(tester);

    expect(find.text('Vídeo retido'), findsOneWidget);
    final order = [
      find.text('Baby Shark'),
      find.text('Retido por recusa'),
      find.text('Cuidador(a): Tem propaganda.'),
      find.text('Psicólogo(a): Tem susto.'),
      find.text(nb('Assustador · 2 denúncias')),
      find.text(nb('Publicidade · 1 denúncia')),
      find.text(notesHeading),
      find.text('“Minha filha chorou.”'),
      window,
      reopen,
      removeForGood,
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    expect(tester.widget<QuietAction>(removeForGood).destructive, isTrue);
  });

  testWidgets('the families\' notes stand apart from the counts: their own '
      'title-medium heading, each note a quoted read line between '
      'hairlines', (tester) async {
    final semantics = tester.ensureSemantics();
    await heldVideo(tester);

    final text = Theme.of(tester.element(find.text(notesHeading))).textTheme;
    final heading = tester.widget<Text>(find.text(notesHeading));
    expect(heading.style?.fontSize, text.titleMedium?.fontSize);
    expect(
      tester.getSemantics(find.text(notesHeading)),
      isSemantics(label: notesHeading, isHeader: true),
    );
    final note = find.text('“Minha filha chorou.”');
    expect(tester.widget<Text>(note).style?.fontSize, text.bodyLarge?.fontSize);
    expect(find.text('Minha filha chorou.'), findsNothing);
    final counts = find.ancestor(
      of: find.text(nb('Assustador · 2 denúncias')),
      matching: find.byType(Doors),
    );
    expect(
      find.descendant(of: counts, matching: note),
      findsNothing,
      reason: 'a note is not a peer of the counts',
    );
    expect(
      find.ancestor(of: note, matching: find.byType(Doors)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: note, matching: find.byType(InkWell)),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('blank notes are left out, and with none there is no '
      'heading', (tester) async {
    await heldVideo(
      tester,
      list: () => heldList([
        heldOf(
          queuedJson('v1', 'Baby Shark'),
          reports: {'assustador': 1},
          notes: ['  '],
        ),
      ]),
    );

    expect(find.text(nb('Assustador · 1 denúncia')), findsOneWidget);
    expect(find.text(notesHeading), findsNothing);
  });

  testWidgets('never says who refused or reported', (tester) async {
    await heldVideo(tester);

    expect(find.textContaining('@'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('Cuidador(a): Tem propaganda.'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
      reason: 'read, never a target',
    );
  });

  testWidgets('the player loads the video without playing it, square-'
      'edged 16:9 at the column\'s width', (tester) async {
    final h = await heldVideo(tester);

    expect(h.adultPlayer.current?.youtubeId, 'yt-v1');
    expect(h.adultPlayer.current!.calls, isEmpty, reason: 'no autoplay');
    final size = tester.getSize(window);
    expect(size.width, tester.getSize(reopen).width);
    expect(size.height, closeTo(size.width * 9 / 16, .01));
  });

  testWidgets('a link out of the player opens in the browser', (tester) async {
    final h = await heldVideo(tester);
    final url = Uri.parse('https://www.youtube.com/watch?v=yt-v1');

    h.adultPlayer.current!.emit(PlayerLeaving(url));
    await tester.pumpAndSettle();

    expect(h.links.opened, [url]);
  });

  testWidgets('a player that fails shows the error note in its place, the '
      'actions still there', (tester) async {
    final h = await heldVideo(tester);

    h.adultPlayer.current!.emit(const PlayerFailed());
    await tester.pumpAndSettle();

    expect(window, findsNothing);
    expectFailedWindow(
      tester,
      heldPlayerFailed,
      width: tester.getSize(reopen).width,
    );
    expect(reopen, findsOneWidget);
    expect(removeForGood, findsOneWidget);
  });

  testWidgets('"Reabrir para revisão" is confirmed full screen with '
      '"Motivo"; then reopened once with the reason trimmed, no '
      're-authentication, and back to the list, read again, with a notice', (
    tester,
  ) async {
    final h = await heldVideo(tester);

    await tapOn(tester, reopen);

    final confirm = tester.widget<DestructiveConfirmation>(
      find.byType(DestructiveConfirmation),
    );
    expect(confirm.askReason, isTrue);
    expect(confirm.body.join(' '), contains('Baby Shark'));
    expect(h.adultPlayer.current!.calls, ['pause']);
    expect(writes(h), isEmpty);
    await tester.enterText(find.widgetWithText(TextField, 'Motivo'), '  $why ');
    await tester.pump();
    await tapOn(tester, confirming('Reabrir para revisão'));

    expect(writes(h), [
      'POST /v1/moderation/videos/v1/reopen {"reason":"$why"}',
    ]);
    expect(h.location(tester), '/moderacao/retidos');
    expect(find.widgetWithText(Notice, reopened('Baby Shark')), findsOneWidget);
    expect(listReads(h), 2);
    expect(h.adultPlayer.current!.closed, isTrue);
  });

  testWidgets('"Remover de vez" is confirmed full screen with "Motivo", '
      'saying it can no longer be suggested; then removed once with the '
      'reason trimmed, back to the list with a notice', (tester) async {
    final h = await heldVideo(tester);

    await tapOn(tester, removeForGood);

    final confirm = tester.widget<DestructiveConfirmation>(
      find.byType(DestructiveConfirmation),
    );
    expect(confirm.askReason, isTrue);
    expect(confirm.body.join(' '), contains('não pode mais ser sugerido'));
    expect(h.adultPlayer.current!.calls, ['pause']);
    expect(writes(h), isEmpty);
    await tester.enterText(find.widgetWithText(TextField, 'Motivo'), '  $why ');
    await tester.pump();
    await tapOn(tester, confirming('Remover de vez'));

    expect(writes(h), [
      'POST /v1/moderation/videos/v1/remove {"reason":"$why"}',
    ]);
    expect(h.location(tester), '/moderacao/retidos');
    expect(
      find.widgetWithText(Notice, removedForGood('Baby Shark')),
      findsOneWidget,
    );
  });

  testWidgets('a moderator settles a held video the same way', (tester) async {
    final h = await heldVideo(tester, roles: ['moderator']);

    await settleWith(tester, 'remove');

    expect(writes(h), [
      'POST /v1/moderation/videos/v1/remove {"reason":"$why"}',
    ]);
    expect(h.location(tester), '/moderacao/retidos');
  });

  testWidgets('removing asks to confirm it is you on reauth_required, then '
      'retries once', (tester) async {
    var confirmed = false;
    final api = adminApi(
      held: () => heldList([refused]),
      settle: (_) =>
          confirmed ? http.Response('', 204) : problem(403, 'reauth_required'),
    );
    final h =
        Harness(
            signedIn: true,
            api: (req) {
              if (req.url.path == '/v1/session/reauth') {
                confirmed = true;
                return http.Response('', 204);
              }
              return api(req);
            },
          )
          ..family = ownerFamily
          ..roles = ['moderator'];
    await h.pump(tester, initial: '/moderacao/retidos/v1');

    await settleWith(tester, 'remove');
    expect(find.byType(ReauthPrompt), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'uma senha longa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(writes(h).map((a) => a.split(' {').first), [
      'POST /v1/moderation/videos/v1/remove',
      'POST /v1/session/reauth',
      'POST /v1/moderation/videos/v1/remove',
    ]);
    expect(h.location(tester), '/moderacao/retidos');
  });

  for (final action in ['reopen', 'remove']) {
    testWidgets('cancelling the $action confirmation writes nothing', (
      tester,
    ) async {
      final h = await heldVideo(tester);

      await tapOn(tester, action == 'reopen' ? reopen : removeForGood);
      await tapOn(tester, find.text('Cancelar'));

      expect(writes(h), isEmpty);
      expect(h.location(tester), '/moderacao/retidos/v1');
    });
  }

  for (final (code, status) in [('state_conflict', 409), ('not_found', 404)]) {
    for (final action in ['reopen', 'remove']) {
      testWidgets('$code on $action goes back to the list, read again, with '
          'a notice', (tester) async {
        final h = await heldVideo(tester, settle: (_) => problem(status, code));

        await settleWith(tester, action);

        expect(h.location(tester), '/moderacao/retidos');
        expect(find.widgetWithText(Notice, heldGone), findsOneWidget);
        expect(listReads(h), 2);
      });
    }
  }

  testWidgets('a video no longer held goes back to the list with a notice', (
    tester,
  ) async {
    final h = await heldVideo(tester, list: () => heldList([]));

    expect(h.location(tester), '/moderacao/retidos');
    expect(find.widgetWithText(Notice, heldGone), findsOneWidget);
  });

  testWidgets('a failed write keeps the screen with the error note', (
    tester,
  ) async {
    final h = await heldVideo(
      tester,
      settle: (_) => problem(503, 'unavailable'),
    );

    await settleWith(tester, 'reopen');

    expect(h.location(tester), '/moderacao/retidos/v1');
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
  });

  testWidgets('back goes to the held list', (tester) async {
    final h = await heldVideo(tester, roles: ['moderator']);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/moderacao/retidos');
  });

  testWidgets('while it loads, the placeholder says what is loading; a '
      'failed read offers "Tentar de novo"', (tester) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    var fail = true;
    final h = await heldVideo(
      tester,
      list: () => answer.isCompleted
          ? (fail ? problem(503, 'unavailable') : heldList([refused]))
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
    expect(window, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('not_moderator goes home with a notice', (tester) async {
    final h = await heldVideo(
      tester,
      roles: ['moderator'],
      settle: (_) => problem(403, 'not_moderator'),
    );

    await settleWith(tester, 'reopen');

    expect(h.location(tester), '/');
    expect(find.text('Você não tem mais acesso à moderação.'), findsOneWidget);
  });
}
