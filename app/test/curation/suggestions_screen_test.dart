import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/suggestions_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

Future<Harness> suggestions(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? list,
  FutureOr<http.Response> Function(http.Request)? suggest,
  String initial = '/sugestoes',
}) async {
  final h = Harness(
    signedIn: true,
    api: suggestionApi(suggestions: list, suggest: suggest),
  )..family = ownerFamily;
  await h.pump(tester, initial: initial);
  return h;
}

http.Response listOf(List<Map<String, Object?>> rows) =>
    json(200, {'suggestions': rows});

List<String> reads(Harness h) =>
    h.actions.where((c) => c == 'GET /v1/suggestions').toList();

void main() {
  testWidgets('says what happens to a suggestion, offers the primary, and '
      'lists the guardian\'s own, newest first', (tester) async {
    await suggestions(
      tester,
      list: () => listOf([
        suggestionJson('v1', 'Galinha Pintadinha', daysAgo: 3),
        suggestionJson(
          'v2',
          'Os sons da fazenda',
          channel: 'Canal Fazendinha',
          state: 'approved',
        ),
        suggestionJson('v3', 'Bita e os animais', state: 'held', daysAgo: 1),
        suggestionJson('v4', 'Mundo Bita', state: 'removed', daysAgo: 9),
      ]),
    );

    expect(find.text(suggestionsLead), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, 'Sugerir um vídeo'), findsOne);
    expect(find.text('Suas sugestões'), findsOneWidget);
    final titles = [
      'Os sons da fazenda',
      'Bita e os animais',
      'Galinha Pintadinha',
      'Mundo Bita',
    ];
    final tops = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(tops, [...tops]..sort(), reason: 'newest first');
    expect(find.text(nb('Canal Fazendinha · hoje')), findsOneWidget);
    expect(find.text(nb('Canal Bichos · ontem')), findsOneWidget);
    expect(find.text(nb('Canal Bichos · há 3 dias')), findsOneWidget);
    for (final state in [
      'Em revisão',
      'No catálogo',
      'Fora do catálogo por enquanto',
      'Removido',
    ]) {
      expect(find.text(state), findsOneWidget, reason: state);
    }
  });

  testWidgets('a row is read as one line, and is never a target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await suggestions(
      tester,
      list: () =>
          listOf([suggestionJson('v1', 'Galinha Pintadinha', daysAgo: 3)]),
    );

    expect(
      tester.getSemantics(find.text('Galinha Pintadinha')),
      isSemantics(
        label: 'Galinha Pintadinha, Canal Bichos, há 3 dias, Em revisão',
        isButton: false,
        hasTapAction: false,
      ),
    );
    expect(find.byType(DoorRow), findsNothing);
    expect(
      find.ancestor(
        of: find.text('Galinha Pintadinha'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('a long title holds to two lines', (tester) async {
    final long = List.filled(20, 'Bichos').join(' ');
    await suggestions(tester, list: () => listOf([suggestionJson('v1', long)]));

    final text = tester.widget<Text>(find.text(long));
    expect((text.maxLines, text.overflow), (2, TextOverflow.ellipsis));
  });

  testWidgets('with none, it says so', (tester) async {
    await suggestions(tester);

    expect(find.text(noSuggestions), findsOneWidget);
    expect(find.text('Sugerir um vídeo'), findsOneWidget);
  });

  testWidgets('while the list loads, the placeholder says what is loading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    await suggestions(tester, list: () => answer.future);

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando suas sugestões'), findsOneWidget);
    expect(find.text('Sugerir um vídeo'), findsOneWidget);
    answer.complete(listOf([]));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyPlaceholder), findsNothing);
    semantics.dispose();
  });

  testWidgets('a failed read says so, and "Tentar de novo" reads again', (
    tester,
  ) async {
    var fail = true;
    final h = await suggestions(
      tester,
      list: () => fail
          ? problem(503, 'unavailable')
          : listOf([suggestionJson('v1', 'Galinha Pintadinha')]),
    );

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(find.text('Sugerir um vídeo'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(reads(h), hasLength(2));
    expect(find.byType(ErrorNote), findsNothing);
    expect(find.text('Galinha Pintadinha'), findsOneWidget);
  });
}
