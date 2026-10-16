import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/catalog/pack_rows.dart';
import 'package:telinha_segura/catalog/video_row.dart';
import 'package:telinha_segura/catalog/words.dart';
import 'package:telinha_segura/kid_mode/kid_mode_door.dart' show StateLine;

import '../access/harness.dart';
import '../curation/fixtures.dart' show nb;
import '../curation/appoint_screen_test.dart' show tapOn;
import 'child_catalog_screen_test.dart' show catalogue, packRow, reads;
import 'fixtures.dart';

/// The Text reading [line], its non-breaking spaces made plain.
Finder plainText(String line) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll('\u00A0', ' ') == line,
);

Finder videoRow(String title) => find.widgetWithText(PackVideoRow, title);

/// Opens "Hora de dormir" from its row on Lia's catalogue.
Future<Harness> fromRow(WidgetTester tester) async {
  final h = await catalogue(tester, catalog: withPacks);
  await tapOn(tester, packRow('Hora de dormir'));
  return h;
}

void main() {
  testWidgets('titled "Pacotinho": its title whole and its count, then who '
      'built and reviewed it', (tester) async {
    await fromRow(tester);

    final order = [
      find.text('Pacotinho'),
      find.text('Hora de dormir'),
      find.text(nb('2 de 3 vídeos para Lia · 12 min')),
      plainText(
        'Montado por mãe ou pai · revisado por 2 pedagogos(as) · última '
        'revisão há 3 dias',
      ),
      find.text('Vídeos, nesta ordem'),
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
  });

  testWidgets('"Vídeos, nesta ordem" is a title-medium header', (tester) async {
    final semantics = tester.ensureSemantics();
    await fromRow(tester);

    final heading = find.text('Vídeos, nesta ordem');
    final text = Theme.of(tester.element(heading)).textTheme;
    expect(
      tester.widget<Text>(heading).style?.fontSize,
      text.titleMedium?.fontSize,
    );
    expect(
      tester.getSemantics(heading),
      isSemantics(label: 'Vídeos, nesta ordem', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('every video in order, numbered, with its thumbnail and its '
      'length', (tester) async {
    final h = await fromRow(tester);

    final rows = [
      videoRow('1. A lua e o sono'),
      videoRow('2. Gatinhos no quintal'),
      videoRow('3. Canção de ninar'),
    ];
    for (final r in rows) {
      expect(r, findsOneWidget);
      expect(
        tester.getSize(
          find.descendant(of: r, matching: find.byType(VideoThumb)),
        ),
        const Size(96, 54),
      );
    }
    final tops = [for (final r in rows) tester.getTopLeft(r).dy];
    expect(tops, [...tops]..sort());
    expect(
      find.descendant(of: rows[2], matching: find.text(nb('7 min'))),
      findsOneWidget,
    );
    for (final id in ['d1', 'd2', 'd3']) {
      expect(h.actions, contains('GET /v1/family/thumbs/$id'));
    }
  });

  testWidgets('a skipped video says so with a hollow module and words, '
      'read with its row, never faded', (tester) async {
    final semantics = tester.ensureSemantics();
    await fromRow(tester);

    final mark = find.descendant(
      of: videoRow('2. Gatinhos no quintal'),
      matching: find.byType(StateLine),
    );
    expect(mark, findsOneWidget);
    expect(tester.widget<StateLine>(mark).filled, isFalse);
    expect(tester.widget<StateLine>(mark).words, 'Fica de fora para Lia');
    expect(
      find.descendant(
        of: videoRow('1. A lua e o sono'),
        matching: find.byType(StateLine),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: videoRow('2. Gatinhos no quintal'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(
        nb('2. Gatinhos no quintal, 4 min, fica de fora para Lia'),
      ),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('the videos are read, never targets, with no chevron', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await fromRow(tester);

    expect(
      find.descendant(
        of: find.byType(PackVideoRow),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(PackVideoRow),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(
      tester.getSemantics(videoRow('1. A lua e o sono')),
      isSemantics(label: nb('1. A lua e o sono, 5 min'), isButton: false),
    );
    semantics.dispose();
  });

  testWidgets('it ends on where hiding a video is done', (tester) async {
    await fromRow(tester);

    final hint = find.text(CatalogWords.packHint('Lia'));
    expect(hint, findsOneWidget);
    expect(
      tester.getTopLeft(hint).dy,
      greaterThan(tester.getTopLeft(videoRow('3. Canção de ninar')).dy),
    );
  });

  testWidgets('opened by its address, it reads the catalogue\'s first page '
      'and finds the pacotinho', (tester) async {
    final h = await catalogue(
      tester,
      catalog: withPacks,
      initial: '/familia/videos/m1/pacotinho/k1',
    );

    expect(find.text('Bichos da fazenda'), findsOneWidget);
    expect(find.byType(PackVideoRow), findsNWidgets(4));
    expect(reads(h), ['GET /v1/family/minors/m1/catalog?offset=0']);
  });

  testWidgets('not among today\'s, it goes back to the catalogue with a '
      'notice', (tester) async {
    final h = await catalogue(
      tester,
      catalog: withPacks,
      initial: '/familia/videos/m1/pacotinho/k9',
    );

    expect(h.location(tester), '/familia/videos/m1');
    expect(find.widgetWithText(Notice, packGone), findsOneWidget);
  });

  testWidgets('a child the server does not know goes back to the children '
      'with a notice', (tester) async {
    final h = await catalogue(
      tester,
      catalog: (_, _) => problem(404, 'not_found'),
      initial: '/familia/videos/m1/pacotinho/k1',
    );

    expect(h.location(tester), '/familia/videos');
    expect(find.widgetWithText(Notice, Copy.childGone), findsOneWidget);
  });

  testWidgets('the loading placeholder while it reads, then a failed read '
      'offers "Tentar de novo"', (tester) async {
    final answer = Completer<http.Response>();
    var fail = true;
    var first = true;
    await catalogue(
      tester,
      catalog: (m, o) {
        if (first) {
          first = false;
          return answer.future;
        }
        return fail ? problem(503, 'unavailable') : withPacks(m, o);
      },
      initial: '/familia/videos/m1/pacotinho/k1',
    );
    expect(find.byKey(const Key('family-placeholder')), findsOneWidget);

    answer.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNote), findsOneWidget);

    fail = false;
    await tapOn(tester, find.text('Tentar de novo'));
    expect(find.byType(ErrorNote), findsNothing);
    expect(find.byType(PackVideoRow), findsNWidgets(4));
  });

  testWidgets('back returns to the child\'s catalogue', (tester) async {
    final h = await fromRow(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos/m1');
  });
}
