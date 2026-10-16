import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/queue_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

Future<Harness> queue(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? read,
  String initial = '/curadoria',
}) async {
  final h = Harness(signedIn: true, api: curatorApi(queue: read))
    ..family = ownerFamily
    ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

/// Goes to [path] as a door or a done state's primary does.
void goTo(WidgetTester tester, String path) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);

List<String> reads(Harness h) =>
    h.actions.where((c) => c.startsWith('GET /v1/curation/queue')).toList();

void main() {
  testWidgets('lists the queue oldest first as doors: the title, the '
      'channel and the length, "Revisita" on a revisit', (tester) async {
    await queue(
      tester,
      read: (_) => queuePage([
        queuedJson('v1', 'Galinha Pintadinha', seconds: 245),
        queuedJson(
          'v2',
          'Os sons da fazenda',
          channel: 'Canal Fazendinha',
          seconds: 3900,
          revisit: true,
        ),
      ]),
    );

    expect(find.text('Curadoria'), findsOneWidget);
    expect(find.byType(DoorRow), findsNWidgets(2));
    final first = tester.getTopLeft(find.text('Galinha Pintadinha')).dy;
    final second = tester.getTopLeft(find.text('Os sons da fazenda')).dy;
    expect(first, lessThan(second), reason: 'the server\'s order');
    expect(find.text(nb('Canal Bichos · 4 min')), findsOneWidget);
    expect(find.text(nb('Canal Fazendinha · 1 h 05 min')), findsOneWidget);
    expect(find.text('Revisita'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(DoorRow, 'Galinha Pintadinha'),
        matching: find.text('Revisita'),
      ),
      findsNothing,
    );
  });

  testWidgets('a row reads as one button with what it shows, and opens the '
      'review', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await queue(
      tester,
      read: (_) =>
          queuePage([queuedJson('v2', 'Os sons da fazenda', revisit: true)]),
    );

    expect(
      tester.getSemantics(find.byType(DoorRow)),
      isSemantics(
        label: nb('Os sons da fazenda, Canal Bichos · 4 min, Revisita'),
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Os sons da fazenda'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/curadoria/v2');
    semantics.dispose();
  });

  testWidgets('a long title holds to two lines', (tester) async {
    final long = List.filled(20, 'Bichos').join(' ');
    await queue(tester, read: (_) => queuePage([queuedJson('v1', long)]));

    final text = tester.widget<Text>(find.text(long));
    expect((text.maxLines, text.overflow), (2, TextOverflow.ellipsis));
  });

  testWidgets('"Ver mais" appends the next page while there is one', (
    tester,
  ) async {
    final h = await queue(
      tester,
      read: (req) => req.url.queryParameters['offset'] == '50'
          ? queuePage([queuedJson('v51', 'Mundo Bita')])
          : queuePage([queuedJson('v1', 'Galinha Pintadinha')], next: 50),
    );

    await tester.ensureVisible(find.text('Ver mais'));
    await tester.tap(find.text('Ver mais'));
    await tester.pumpAndSettle();

    expect(reads(h), [
      'GET /v1/curation/queue',
      'GET /v1/curation/queue?offset=50',
    ]);
    expect(find.text('Galinha Pintadinha'), findsOneWidget);
    expect(find.text('Mundo Bita'), findsOneWidget);
    expect(find.text('Ver mais'), findsNothing, reason: 'the last page');
  });

  testWidgets('a failed "Ver mais" says so and keeps the rows', (tester) async {
    await queue(
      tester,
      read: (req) => req.url.queryParameters['offset'] == '50'
          ? problem(503, 'unavailable')
          : queuePage([queuedJson('v1', 'Galinha Pintadinha')], next: 50),
    );

    await tester.ensureVisible(find.text('Ver mais'));
    await tester.tap(find.text('Ver mais'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(find.text('Galinha Pintadinha'), findsOneWidget);
    expect(find.text('Ver mais'), findsOneWidget);
  });

  testWidgets('an empty queue says so', (tester) async {
    await queue(tester);

    expect(find.text(emptyQueue), findsOneWidget);
    expect(find.byType(DoorRow), findsNothing);
  });

  testWidgets('while it loads, the placeholder says what is loading; a '
      'failed read offers "Tentar de novo"', (tester) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    var fail = false;
    final h = await queue(
      tester,
      read: (_) => fail ? problem(503, 'unavailable') : answer.future,
    );

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando a fila'), findsOneWidget);
    fail = true;
    answer.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);

    fail = false;
    h.api = curatorApi(
      queue: (_) => queuePage([queuedJson('v1', 'Galinha Pintadinha')]),
    );
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNote), findsNothing);
    expect(find.text('Galinha Pintadinha'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('coming back from a review reads the queue again from the '
      'start', (tester) async {
    var first = true;
    final h = await queue(
      tester,
      read: (_) {
        final page = first
            ? queuePage([queuedJson('v1', 'Galinha Pintadinha')], next: 50)
            : queuePage([queuedJson('v2', 'Mundo Bita')]);
        first = false;
        return page;
      },
    );

    await tester.tap(find.text('Galinha Pintadinha'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/curadoria/v1');
    goTo(tester, '/curadoria');
    await tester.pumpAndSettle();

    expect(h.location(tester), '/curadoria');
    expect(reads(h), ['GET /v1/curation/queue', 'GET /v1/curation/queue']);
    expect(find.text('Mundo Bita'), findsOneWidget);
    expect(find.text('Galinha Pintadinha'), findsNothing);
  });

  testWidgets('not_curator goes home with a notice', (tester) async {
    final h = await queue(tester, read: (_) => problem(403, 'not_curator'));

    expect(h.location(tester), '/');
    expect(find.text('Você não faz mais parte da curadoria.'), findsOneWidget);
  });
}
