import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/held_videos_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'curation_api_test.dart' show rejectionJson;
import 'fixtures.dart';

/// The held list as [roles] reach it; a moderator with no family of
/// their own unless [family] says otherwise.
Future<Harness> held(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? list,
  String initial = '/moderacao/retidos',
  List<String> roles = const ['admin'],
  Map<String, Object?>? family = ownerFamily,
}) async {
  final h = Harness(signedIn: true, api: adminApi(held: list))
    ..family = family
    ..roles = roles;
  await h.pump(tester, initial: initial);
  return h;
}

final refused = heldOf(
  queuedJson('v1', 'Baby Shark', channel: 'Canal Baby Shark'),
  rejections: [
    rejectionJson,
    {...rejectionJson, 'display_role': 'psicologo', 'reason': 'Tem susto.'},
  ],
  reports: {'assustador': 2, 'publicidade': 1},
  notes: ['Minha filha chorou.'],
);

final reported = heldOf(
  queuedJson('v2', 'Galinha Pintadinha'),
  reason: 'reports',
  reports: {'inadequado': 1},
);

final unavailable = heldOf(
  queuedJson('v3', 'Patati Patatá'),
  reason: 'unavailable',
);

void main() {
  testWidgets('lists each held video as a door: its title, why it is held '
      'in words, then its counts of refusals and reports', (tester) async {
    final h = await held(
      tester,
      list: () => heldList([refused, reported, unavailable]),
    );

    expect(h.actions, contains('GET /v1/moderation/videos?state=held'));
    expect(find.text('Vídeos retidos'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Baby Shark'), findsOneWidget);
    expect(find.text('Retido por recusa'), findsOneWidget);
    expect(find.text(nb('2 recusas · 3 denúncias')), findsOneWidget);
    expect(find.text('Retido por denúncias'), findsOneWidget);
    expect(find.text('1 denúncia'), findsOneWidget);
    expect(find.text('Indisponível no YouTube'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Retido por recusa')).dy,
      lessThan(tester.getTopLeft(find.text(nb('2 recusas · 3 denúncias'))).dy),
    );
  });

  testWidgets('a moderator with no family reads the same list', (tester) async {
    final h = await held(
      tester,
      roles: ['moderator'],
      family: null,
      list: () => heldList([refused]),
    );

    expect(h.location(tester), '/moderacao/retidos');
    expect(find.widgetWithText(DoorRow, 'Baby Shark'), findsOneWidget);
  });

  testWidgets('a held video opens its screen', (tester) async {
    final h = await held(tester, list: () => heldList([refused]));

    await tester.tap(find.text('Baby Shark'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/moderacao/retidos/v1');
  });

  testWidgets('with nothing held, it says so', (tester) async {
    await held(tester);

    expect(find.text(noHeldVideos), findsOneWidget);
  });

  for (final (roles, back) in [
    (['admin'], '/admin'),
    (['admin', 'moderator'], '/admin'),
    (['moderator'], '/'),
  ]) {
    testWidgets('with roles $roles, back goes to $back', (tester) async {
      final h = await held(tester, roles: roles);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), back);
    });
  }

  testWidgets('while it loads, the placeholder says what is loading; a '
      'failed read offers "Tentar de novo"', (tester) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    var fail = true;
    await held(
      tester,
      list: () => answer.isCompleted
          ? (fail ? problem(503, 'unavailable') : heldList([refused]))
          : answer.future,
    );

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(
      find.bySemanticsLabel('Carregando os vídeos retidos'),
      findsOneWidget,
    );
    answer.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Baby Shark'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a notice brought back shows above the list', (tester) async {
    await held(tester);

    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/moderacao/retidos', extra: 'Esse vídeo não está mais retido.');
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(Notice, 'Esse vídeo não está mais retido.'),
      findsOneWidget,
    );
  });

  testWidgets('not_moderator goes home with a notice', (tester) async {
    final h = await held(
      tester,
      roles: ['moderator'],
      list: () => problem(403, 'not_moderator'),
    );

    expect(h.location(tester), '/');
    expect(find.text('Você não tem mais acesso à moderação.'), findsOneWidget);
  });
}
