import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/catalog/family_video_screen.dart';
import 'package:telinha_segura/catalog/words.dart';
import 'package:telinha_segura/kid/kid_player.dart';

import '../access/harness.dart';
import '../curation/fixtures.dart' show nb;
import '../curation/appoint_screen_test.dart' show tapOn;
import '../curation/review_screen_test.dart' show expectFailedWindow;
import '../kid/fake_player.dart';
import 'child_catalog_screen_test.dart' show catalogue, reads, row;
import 'fixtures.dart';

/// The video's screen opened from its row in Lia's catalogue.
Future<Harness> video(
  WidgetTester tester, {
  String title = 'O sapo que pulava alto',
  FutureOr<http.Response> Function(String minorId, int offset)? catalog,
  FutureOr<http.Response> Function(http.Request)? write,
}) async {
  final h = await catalogue(tester, catalog: catalog, write: write);
  await tapOn(tester, row(title));
  return h;
}

Finder get window => find.byKey(FakePlayback.viewKey);
Finder get hide => find.widgetWithText(FilledButton, CatalogWords.hide('Lia'));
Finder get show => find.widgetWithText(FilledButton, CatalogWords.show('Lia'));
Finder get report => find.widgetWithText(QuietAction, 'Denunciar este vídeo');

List<String> writes(Harness h) => h.actions
    .where((a) => a.startsWith('PUT') || a.startsWith('DELETE'))
    .toList();

/// The [Text] whose words, non-breaking spaces made plain, are [words].
Finder plainText(String words) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll('\u00A0', ' ') == words,
);

const provenanceLine =
    'Revisado por 2 mães ou pais e 1 pedagogo(a) · última revisão há 3 dias';

void main() {
  testWidgets('reads in order: the heading, the provenance, the player, '
      'the hide primary, then the quiet report', (tester) async {
    await video(tester);

    expect(find.text('Vídeo'), findsOneWidget);
    final order = [
      find.text('Vídeo'),
      find.text('O sapo que pulava alto'),
      find.text(nb('Ciência Pequena · 6 min')),
      plainText(provenanceLine),
      window,
      hide,
      report,
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    expect(tester.widget<QuietAction>(report).destructive, isTrue);
  });

  testWidgets('without provenance the sentence is left out', (tester) async {
    await video(
      tester,
      catalog: (_, _) =>
          page([familyItem('v1', 'O sapo que pulava alto', approvals: null)]),
    );

    expect(find.textContaining('Revisado por'), findsNothing);
    expect(find.textContaining('última revisão'), findsNothing);
    expect(window, findsOneWidget);
  });

  testWidgets('never says who reviewed it', (tester) async {
    await video(tester);

    expect(find.textContaining('@'), findsNothing);
  });

  testWidgets('the player loads the video without playing it, square-'
      'edged 16:9 at the column\'s width', (tester) async {
    final h = await video(tester);

    expect(h.adultPlayer.current?.youtubeId, 'yt-v1');
    expect(h.adultPlayer.current!.calls, isEmpty, reason: 'no autoplay');
    final size = tester.getSize(window);
    expect(size.width, tester.getSize(hide).width);
    expect(size.height, closeTo(size.width * 9 / 16, .01));
    expect(h.player.current, isNull, reason: 'never the child\'s player');
  });

  testWidgets('a link out of the player opens in the browser', (tester) async {
    final h = await video(tester);
    final url = Uri.parse('https://www.youtube.com/watch?v=yt-v1');

    h.adultPlayer.current!.emit(PlayerLeaving(url));
    await tester.pumpAndSettle();

    expect(h.links.opened, [url]);
  });

  testWidgets('a player that fails keeps its box with the error note '
      'inside; hide and report stay', (tester) async {
    final h = await video(tester);

    h.adultPlayer.current!.emit(const PlayerFailed());
    await tester.pumpAndSettle();

    expect(window, findsNothing);
    expectFailedWindow(
      tester,
      familyPlayerFailed,
      width: tester.getSize(hide).width,
    );
    expect(hide, findsOneWidget);
    expect(report, findsOneWidget);
  });

  testWidgets('"Esconder para Lia" hides it once; the primary flips and a '
      'notice is announced', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await video(tester);

    await tapOn(tester, hide);

    expect(writes(h), ['PUT /v1/family/minors/m1/hidden/v1']);
    expect(show, findsOneWidget);
    expect(hide, findsNothing);
    final notice = find.widgetWithText(Notice, CatalogWords.hidden('Lia'));
    expect(notice, findsOneWidget);
    expect(tester.getTopLeft(notice).dy, lessThan(tester.getTopLeft(show).dy));
    expect(h.location(tester), '/familia/videos/m1/v1');
    semantics.dispose();
  });

  testWidgets('on a hidden video, "Mostrar para Lia de novo" unhides it', (
    tester,
  ) async {
    final h = await video(tester, title: 'Gatinhos no quintal');

    expect(show, findsOneWidget);
    await tapOn(tester, show);

    expect(writes(h), ['DELETE /v1/family/minors/m1/hidden/v2']);
    expect(hide, findsOneWidget);
    expect(
      find.widgetWithText(Notice, CatalogWords.shown('Lia')),
      findsOneWidget,
    );
  });

  testWidgets('while a hide runs, the primary shows its ring and takes no '
      'second tap', (tester) async {
    final answer = Completer<http.Response>();
    final h = await video(tester, write: (_) => answer.future);

    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pump();
    final primary = find.byType(PrimaryButton);
    expect(tester.widget<PrimaryButton>(primary).busy, isTrue);
    await tester.tap(primary, warnIfMissed: false);
    await tester.pump();

    answer.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(writes(h), hasLength(1));
  });

  testWidgets('a failed hide shows the error note and keeps the primary', (
    tester,
  ) async {
    await video(tester, write: (_) => problem(503, 'unavailable'));

    await tapOn(tester, hide);

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(hide, findsOneWidget);
    expect(find.byType(Notice), findsNothing);
  });

  testWidgets('"Denunciar este vídeo" opens the report, the video paused '
      'beneath it', (tester) async {
    final h = await video(tester);

    await tapOn(tester, find.text('Denunciar este vídeo'));

    expect(h.location(tester), '/familia/videos/m1/v1/denunciar');
    expect(h.adultPlayer.current!.calls, contains('pause'));
  });

  testWidgets('back returns to the catalogue', (tester) async {
    final h = await video(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos/m1');
  });

  testWidgets('opened by its address, it reads the pages until it finds '
      'the video', (tester) async {
    final h = Harness(
      signedIn: true,
      api: catalogApi(
        catalog: (_, offset) => offset == 0
            ? page([familyItem('v1', 'O sapo que pulava alto')], more: true)
            : page([familyItem('v7', 'Folhas ao vento', theme: 'natureza')]),
      ),
    )..family = threeChildren;
    await h.pump(tester, initial: '/familia/videos/m1/v7');

    expect(reads(h), [
      'GET /v1/family/minors/m1/catalog?offset=0',
      'GET /v1/family/minors/m1/catalog?offset=1',
    ]);
    expect(find.text('Folhas ao vento'), findsOneWidget);
    expect(h.adultPlayer.current?.youtubeId, 'yt-v7');
  });

  testWidgets('opened by its address for a video not there, it goes back '
      'to the catalogue with a notice', (tester) async {
    final h = Harness(signedIn: true, api: catalogApi())
      ..family = threeChildren;
    await h.pump(tester, initial: '/familia/videos/m1/v9');

    expect(h.location(tester), '/familia/videos/m1');
    expect(find.widgetWithText(Notice, videoGone), findsOneWidget);
  });
}
