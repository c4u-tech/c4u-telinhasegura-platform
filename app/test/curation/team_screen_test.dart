import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

Future<Harness> team(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? list,
  String initial = '/admin/equipe',
}) async {
  final h = Harness(signedIn: true, api: adminApi(staff: list))
    ..family = ownerFamily
    ..roles = ['admin'];
  await h.pump(tester, initial: initial);
  return h;
}

void main() {
  testWidgets('lists each member in server order by email, the roles in '
      'words joined by a dot, then "Nomear alguém"', (tester) async {
    final semantics = tester.ensureSemantics();
    await team(
      tester,
      list: () => staffList([
        selfMember,
        memberOf('a2', 'bia@example.com', [curatorRole(), moderatorRole()]),
        memberOf('a3', 'caio@example.com', [
          curatorRole(role: 'mae-pai', verified: false),
        ]),
        memberOf('a4', 'duda@example.com', [moderatorRole()]),
      ]),
    );

    expect(find.text('Equipe'), findsOneWidget);
    final emails = [
      'ana@example.com',
      'bia@example.com',
      'caio@example.com',
      'duda@example.com',
    ];
    final tops = [
      for (final e in emails)
        tester.getTopLeft(find.widgetWithText(DoorRow, addressBreaks(e))).dy,
    ];
    expect(tops, [...tops]..sort(), reason: 'server order');
    expect(find.text('Administração'), findsOneWidget);
    expect(
      find.text(nb('Curadoria: Pedagogo(a), formação verificada · Moderação')),
      findsOneWidget,
    );
    expect(find.text('Curadoria: Mãe ou pai'), findsOneWidget);
    expect(find.text('Moderação'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'bia@example.com, Curadoria: Pedagogo(a), formação verificada; '
        'Moderação',
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Nomear alguém')).dy,
      greaterThan(tops.last),
    );
    semantics.dispose();
  });

  testWidgets('the email stands in title-medium, the roles muted', (
    tester,
  ) async {
    await team(tester);

    final email = find.text(addressBreaks('bia@example.com'));
    final text = Theme.of(tester.element(email)).textTheme;
    expect(
      tester.widget<Text>(email).style?.fontSize,
      text.titleMedium?.fontSize,
    );
  });

  testWidgets('a member opens their sheet; "Nomear alguém" the form', (
    tester,
  ) async {
    final h = await team(tester);

    await tester.tap(find.text(addressBreaks('bia@example.com')));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/admin/equipe/a2');

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/admin/equipe');
    await tester.tap(find.text('Nomear alguém'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/admin/equipe/nova');
  });

  testWidgets('back goes to "Administração"', (tester) async {
    final h = await team(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/admin');
  });

  testWidgets('while it loads, the placeholder says what is loading; a '
      'failed read offers "Tentar de novo"', (tester) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    var fail = true;
    await team(
      tester,
      list: () => answer.isCompleted
          ? (fail ? problem(503, 'unavailable') : staffList([selfMember]))
          : answer.future,
    );

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando a equipe'), findsOneWidget);
    answer.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.text(addressBreaks('ana@example.com')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a notice brought back shows its address with break marks, '
      'read plain', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await team(tester);

    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(
      '/admin/equipe',
      extra: (String Function(String) set) =>
          '${set('bia@example.com')} saiu da equipe.',
    );
    await tester.pumpAndSettle();

    expect(h.location(tester), '/admin/equipe');
    expect(
      find.widgetWithText(
        Notice,
        '${addressBreaks('bia@example.com')} saiu da equipe.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('bia@example.com saiu da equipe.'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('not_admin goes home with a notice', (tester) async {
    final h = await team(tester, list: () => problem(403, 'not_admin'));

    expect(h.location(tester), '/');
    expect(
      find.text('Você não tem mais acesso à administração.'),
      findsOneWidget,
    );
  });
}
