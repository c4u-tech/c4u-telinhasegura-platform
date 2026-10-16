import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/catalog/pack_rows.dart';
import 'package:telinha_segura/catalog/pack_screen.dart';
import 'package:telinha_segura/catalog/video_row.dart';
import 'package:telinha_segura/catalog/words.dart';
import 'package:telinha_segura/family/family.dart' show AgeBand;
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid/shelves.dart' show HollowThumbnail;
import 'package:telinha_segura/kid_mode/kid_mode_door.dart' show StateLine;

import '../access/harness.dart';
import '../curation/fixtures.dart' show nb;
import '../curation/appoint_screen_test.dart' show tapOn;
import 'fixtures.dart';

Future<Harness> catalogue(
  WidgetTester tester, {
  FutureOr<http.Response> Function(String minorId, int offset)? catalog,
  FutureOr<http.Response> Function(String videoId)? thumb,
  FutureOr<http.Response> Function(http.Request)? write,
  String initial = '/familia/videos/m1',
}) async {
  final h = Harness(
    signedIn: true,
    api: catalogApi(catalog: catalog, thumb: thumb, write: write),
  )..family = threeChildren;
  await h.pump(tester, initial: initial);
  return h;
}

Finder row(String title) => find.widgetWithText(VideoRow, title);

Finder packRow(String title) => find.widgetWithText(PackRow, title);

List<String> reads(Harness h) =>
    h.actions.where((a) => a.contains('/catalog')).toList();

void main() {
  testWidgets('titled by the nickname, it says what the list is, then each '
      'theme under its heading in the app\'s order', (tester) async {
    final h = await catalogue(
      tester,
      catalog: (_, _) => page([
        familyItem('v3', 'A canção das cores', theme: 'musica'),
        familyItem('v9', 'Um tema novo', theme: 'espaco'),
        familyItem('v1', 'O sapo que pulava alto'),
        familyItem('v2', 'Gatinhos no quintal'),
      ]),
    );

    expect(find.text('Lia'), findsOneWidget);
    expect(find.text(CatalogWords.lead('Lia')), findsOneWidget);
    final order = [
      find.text('Lia'),
      find.text(CatalogWords.lead('Lia')),
      find.text('Bichos'),
      row('O sapo que pulava alto'),
      row('Gatinhos no quintal'),
      find.text('Música'),
      row('A canção das cores'),
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    expect(row('Um tema novo'), findsNothing, reason: 'an unknown theme');
    expect(reads(h), ['GET /v1/family/minors/m1/catalog?offset=0']);
  });

  testWidgets('a theme heading is a title-medium header', (tester) async {
    final semantics = tester.ensureSemantics();
    await catalogue(tester);

    final text = Theme.of(tester.element(find.text('Bichos'))).textTheme;
    expect(
      tester.widget<Text>(find.text('Bichos')).style?.fontSize,
      text.titleMedium?.fontSize,
    );
    expect(
      tester.getSemantics(find.text('Bichos')),
      isSemantics(label: 'Bichos', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('a row: the thumbnail at 96 × 54 at the screen-ratio corner, '
      'the title in at most two lines, then "Canal · 6 min"', (tester) async {
    final h = await catalogue(tester);

    final thumb = find.descendant(
      of: row('O sapo que pulava alto'),
      matching: find.byType(VideoThumb),
    );
    expect(tester.getSize(thumb), const Size(96, 54));
    expect(
      find.descendant(of: thumb, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DoorRow>(
            find.ancestor(
              of: find.text('O sapo que pulava alto'),
              matching: find.byType(DoorRow),
            ),
          )
          .titleMaxLines,
      2,
    );
    expect(
      find.descendant(
        of: row('O sapo que pulava alto'),
        matching: find.text(nb('Ciência Pequena · 6 min')),
      ),
      findsOneWidget,
    );
    expect(h.actions, contains('GET /v1/family/thumbs/v1'));
  });

  testWidgets('a hidden video says so with a hollow state module and '
      'words, and in its label (2026-10-06)', (tester) async {
    final semantics = tester.ensureSemantics();
    await catalogue(tester);

    expect(
      find.descendant(
        of: row('Gatinhos no quintal'),
        matching: find.text(nb('Canal X · 4 min')),
      ),
      findsOneWidget,
    );
    final mark = find.descendant(
      of: row('Gatinhos no quintal'),
      matching: find.byType(StateLine),
    );
    expect(mark, findsOneWidget);
    expect(tester.widget<StateLine>(mark).filled, isFalse);
    expect(tester.widget<StateLine>(mark).words, 'Escondido para Lia');
    expect(
      tester.getTopLeft(mark).dy,
      greaterThan(tester.getTopLeft(find.text(nb('Canal X · 4 min'))).dy),
      reason: 'its own line, under the channel and length',
    );
    expect(
      find.descendant(
        of: row('O sapo que pulava alto'),
        matching: find.byType(StateLine),
      ),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(
        nb('Gatinhos no quintal, Canal X · 4 min, escondido para Lia'),
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(
        nb('O sapo que pulava alto, Ciência Pequena · 6 min'),
      ),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('a thumbnail that fails shows the hollow screen, and the row '
      'still opens', (tester) async {
    final h = await catalogue(
      tester,
      thumb: (id) => id == 'v1'
          ? problem(404, 'not_found')
          : http.Response.bytes([0xFF, 0xD8], 200),
    );

    expect(
      find.descendant(
        of: row('O sapo que pulava alto'),
        matching: find.byType(HollowThumbnail),
      ),
      findsOneWidget,
    );
    await tester.tap(row('O sapo que pulava alto'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/familia/videos/m1/v1');
  });

  testWidgets('a thumbnail on its way is the hollow screen too', (
    tester,
  ) async {
    final never = Completer<http.Response>();
    await catalogue(tester, thumb: (_) => never.future);

    expect(find.byType(HollowThumbnail), findsNWidgets(3));
  });

  testWidgets('"Ver mais" appends the next page; a theme carries on under '
      'its heading', (tester) async {
    final h = await catalogue(
      tester,
      catalog: (_, offset) => offset == 0
          ? page([familyItem('v1', 'O sapo que pulava alto')], more: true)
          : page([
              familyItem('v2', 'Gatinhos no quintal'),
              familyItem('v3', 'A canção das cores', theme: 'musica'),
            ]),
    );

    final more = find.widgetWithText(QuietAction, 'Ver mais');
    await tapOn(tester, find.text('Ver mais'));

    expect(reads(h), [
      'GET /v1/family/minors/m1/catalog?offset=0',
      'GET /v1/family/minors/m1/catalog?offset=1',
    ]);
    expect(find.text('Bichos'), findsOneWidget);
    expect(row('Gatinhos no quintal'), findsOneWidget);
    expect(find.text('Música'), findsOneWidget);
    expect(more, findsNothing);
  });

  testWidgets('empty, it says no video is approved for the band yet', (
    tester,
  ) async {
    await catalogue(tester, catalog: (_, _) => page([]));

    expect(find.text(CatalogWords.empty(AgeBand.from5To8)), findsOneWidget);
    expect(find.byType(VideoRow), findsNothing);
  });

  testWidgets('a row opens the video\'s screen; coming back reads from '
      'offset 0 again', (tester) async {
    final h = await catalogue(tester);

    await tester.tap(row('O sapo que pulava alto'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/familia/videos/m1/v1');

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos/m1');
    expect(reads(h), [
      'GET /v1/family/minors/m1/catalog?offset=0',
      'GET /v1/family/minors/m1/catalog?offset=0',
    ]);
  });

  testWidgets('the loading placeholder, announced, while it loads', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    await catalogue(tester, catalog: (_, _) => answer.future);

    expect(find.byKey(const Key('family-placeholder')), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando os vídeos'), findsOne);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    answer.complete(page(liaVideos));
    await tester.pumpAndSettle();
    expect(find.byType(VideoRow), findsNWidgets(3));
    semantics.dispose();
  });

  testWidgets('a failed read offers "Tentar de novo"', (tester) async {
    var fail = true;
    await catalogue(
      tester,
      catalog: (_, _) => fail ? problem(503, 'unavailable') : page(liaVideos),
    );

    expect(find.byType(ErrorNote), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorNote), findsNothing);
    expect(find.byType(VideoRow), findsNWidgets(3));
  });

  testWidgets('a child the server does not know goes back to the list with '
      'a notice', (tester) async {
    final h = await catalogue(
      tester,
      catalog: (_, _) => problem(404, 'not_found'),
    );

    expect(h.location(tester), '/familia/videos');
    expect(find.widgetWithText(Notice, Copy.childGone), findsOneWidget);
  });

  testWidgets('a notice brought back from a video stands above the list', (
    tester,
  ) async {
    final h = await catalogue(tester);

    await tester.tap(row('O sapo que pulava alto'));
    await tester.pumpAndSettle();
    h.api = catalogApi(write: (_) => problem(404, 'not_found'));
    final hide = find.widgetWithText(FilledButton, CatalogWords.hide('Lia'));
    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos/m1');
    expect(find.widgetWithText(Notice, videoGone), findsOneWidget);
  });

  group('today\'s pacotinhos (pacotinhos in the guardian\'s catalogue)', () {
    testWidgets('a header section between the lead line and the first '
        'theme, one row per pacotinho in the server\'s order, closed by '
        'the daily line', (tester) async {
      final semantics = tester.ensureSemantics();
      await catalogue(tester, catalog: withPacks);

      final order = [
        find.text(CatalogWords.lead('Lia')),
        find.text(packsHeading),
        packRow('Bichos da fazenda'),
        packRow('Hora de dormir'),
        find.text(packsDaily),
        find.text('Bichos'),
      ];
      for (final f in order) {
        expect(f, findsOneWidget);
      }
      final tops = [for (final f in order) tester.getTopLeft(f).dy];
      expect(tops, [...tops]..sort());
      expect(
        tester.getSemantics(find.text(packsHeading)),
        isSemantics(label: packsHeading, isHeader: true),
      );
      final text = Theme.of(tester.element(find.text(packsHeading))).textTheme;
      expect(
        tester.widget<Text>(find.text(packsHeading)).style?.fontSize,
        text.titleMedium?.fontSize,
      );
      semantics.dispose();
    });

    testWidgets('a row: its cover at 96 × 54, its title, and the count and '
        'length of what plays, read as a pacotinho', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await catalogue(tester, catalog: withPacks);

      final cover = find.descendant(
        of: packRow('Bichos da fazenda'),
        matching: find.byType(VideoThumb),
      );
      expect(tester.getSize(cover), const Size(96, 54));
      expect(tester.widget<VideoThumb>(cover).videoId, 'p2');
      expect(h.actions, contains('GET /v1/family/thumbs/p2'));
      expect(
        find.descendant(
          of: packRow('Bichos da fazenda'),
          matching: find.text(nb('4 vídeos · 18 min')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: packRow('Hora de dormir'),
          matching: find.text(nb('2 de 3 vídeos para Lia · 12 min')),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          nb('Bichos da fazenda, pacotinho, 4 vídeos · 18 min'),
        ),
        findsOne,
      );
      semantics.dispose();
    });

    testWidgets('with no pacotinho the section is absent', (tester) async {
      await catalogue(tester);

      expect(find.text(packsHeading), findsNothing);
      expect(find.text(packsDaily), findsNothing);
      expect(find.byType(PackRow), findsNothing);
    });

    testWidgets('"Ver mais" keeps the section page 0 gave', (tester) async {
      await catalogue(
        tester,
        catalog: (_, offset) => offset == 0
            ? page(
                [familyItem('v1', 'O sapo que pulava alto')],
                more: true,
                packs: liaPacks,
              )
            : page([familyItem('v2', 'Gatinhos no quintal')]),
      );

      await tapOn(tester, find.text('Ver mais'));

      expect(find.byType(PackRow), findsNWidgets(2));
      expect(row('Gatinhos no quintal'), findsOneWidget);
    });

    testWidgets('a row opens the pacotinho\'s screen; coming back reads '
        'from offset 0 again', (tester) async {
      final h = await catalogue(tester, catalog: withPacks);

      await tapOn(tester, packRow('Hora de dormir'));
      expect(h.location(tester), '/familia/videos/m1/pacotinho/k2');
      expect(find.byType(PackScreen), findsOneWidget);
      expect(reads(h), ['GET /v1/family/minors/m1/catalog?offset=0']);

      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/videos/m1');
      expect(reads(h), [
        'GET /v1/family/minors/m1/catalog?offset=0',
        'GET /v1/family/minors/m1/catalog?offset=0',
      ]);
      expect(find.byType(PackRow), findsNWidgets(2));
    });
  });

  testWidgets('back returns to the children', (tester) async {
    final h = await catalogue(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos');
  });
}
