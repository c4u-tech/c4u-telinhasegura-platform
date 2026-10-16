import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/packs_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';
import 'queue_screen_test.dart' show goTo;

Future<Harness> packsList(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? list,
  String initial = '/pacotinhos',
}) async {
  final h = Harness(signedIn: true, api: packApi(list: list))
    ..family = ownerFamily
    ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

List<String> listReads(Harness h) => h.actions
    .where(
      (c) =>
          c == 'GET /v1/curation/packs' ||
          c.startsWith('GET /v1/curation/packs?'),
    )
    .toList();

void main() {
  testWidgets('leads with "Montar um pacotinho", which opens the composer', (
    tester,
  ) async {
    final h = await packsList(tester);

    expect(find.text('Pacotinhos'), findsOneWidget);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Montar um pacotinho'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/pacotinhos/novo');
  });

  testWidgets('lists the pacotinhos in the server\'s order as doors: the '
      'title, the count, the total and the theme', (tester) async {
    await packsList(
      tester,
      list: (_) => packPage([
        packOf('p1', 'Hora do banho', theme: 'musica', reviewable: true),
        packOf(
          'p2',
          'Bichos da fazenda',
          videos: [
            packVideoJson('v1', 'A', seconds: 300),
            packVideoJson('v2', 'B', seconds: 300),
            packVideoJson('v3', 'C', seconds: 300),
            packVideoJson('v4', 'D', seconds: 180),
          ],
        ),
      ]),
    );

    expect(find.byType(DoorRow), findsNWidgets(2));
    final first = tester.getTopLeft(find.text('Hora do banho')).dy;
    final second = tester.getTopLeft(find.text('Bichos da fazenda')).dy;
    expect(first, lessThan(second));
    expect(find.text(nb('3 vídeos · 12 min · Música')), findsOneWidget);
    expect(find.text(nb('4 vídeos · 18 min')), findsOneWidget);
  });

  for (final (state, reviewable, words) in [
    ('pending', true, 'Para você revisar'),
    ('held', true, 'Para você revisar'),
    ('approved', true, 'Nova versão para você revisar'),
    ('pending', false, 'Em revisão'),
    ('approved', false, 'Publicado'),
    ('held', false, 'Recusado'),
  ]) {
    testWidgets(
      'a $state pacotinho${reviewable ? ' the curator may '
                'review' : ''} reads "$words"',
      (tester) async {
        await packsList(
          tester,
          list: (_) => packPage([
            packOf('p1', 'Hora do banho', state: state, reviewable: reviewable),
          ]),
        );

        expect(
          find.descendant(of: find.byType(DoorRow), matching: find.text(words)),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('a row reads as one button with what it shows, and opens the '
      'review', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await packsList(
      tester,
      list: (_) => packPage([packOf('p1', 'Hora do banho', reviewable: true)]),
    );

    expect(
      tester.getSemantics(find.byType(DoorRow)),
      isSemantics(
        label: nb('Hora do banho, 3 vídeos · 12 min, Para você revisar'),
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Hora do banho'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/pacotinhos/p1');
    semantics.dispose();
  });

  testWidgets('"Ver mais" appends the next page while there is one', (
    tester,
  ) async {
    final h = await packsList(
      tester,
      list: (req) => req.url.queryParameters['offset'] == '1'
          ? packPage([packOf('p2', 'Bichos da fazenda')])
          : packPage([packOf('p1', 'Hora do banho')], hasMore: true),
    );

    await tester.tap(find.text('Ver mais'));
    await tester.pumpAndSettle();

    expect(listReads(h).last, 'GET /v1/curation/packs?offset=1');
    expect(find.byType(DoorRow), findsNWidgets(2));
    expect(find.widgetWithText(QuietAction, 'Ver mais'), findsNothing);
  });

  testWidgets('empty, it says so', (tester) async {
    await packsList(tester);

    expect(find.text(emptyPacks), findsOneWidget);
    expect(find.byType(DoorRow), findsNothing);
  });

  testWidgets('coming back from a pacotinho, it reads the list again from '
      'the start', (tester) async {
    final h = await packsList(
      tester,
      list: (_) => packPage([packOf('p1', 'Hora do banho')]),
    );
    expect(listReads(h), hasLength(1));

    goTo(tester, '/pacotinhos/p1');
    await tester.pumpAndSettle();
    goTo(tester, '/pacotinhos');
    await tester.pumpAndSettle();

    expect(listReads(h), hasLength(2));
    expect(listReads(h).last, 'GET /v1/curation/packs');
  });

  testWidgets('a failed read offers "Tentar de novo"', (tester) async {
    var fail = true;
    await packsList(
      tester,
      list: (_) => fail
          ? http.Response('', 500)
          : packPage([packOf('p1', 'Hora do banho')]),
    );

    expect(find.text(Copy.genericRetry), findsOneWidget);
    fail = false;
    await tester.tap(find.widgetWithText(PrimaryButton, 'Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Hora do banho'), findsOneWidget);
  });

  testWidgets('a notice brought back shows above the list', (tester) async {
    await packsList(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/pacotinhos', extra: 'Esse pacotinho foi removido.');
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(Notice, 'Esse pacotinho foi removido.'),
      findsOneWidget,
    );
  });

  testWidgets('a lost role goes home', (tester) async {
    final h = await packsList(tester, list: (_) => problem(403, 'not_curator'));

    expect(h.location(tester), '/');
  });
}
