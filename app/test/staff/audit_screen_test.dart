import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/staff/audit_row.dart';

import '../access/harness.dart';
import '../curation/fixtures.dart';
import '../family/fixtures.dart';
import 'accounts_api_test.dart' show actionJson;

const intro = 'Ações da equipe, das mais recentes para as mais antigas.';

/// One action as the wire carries it, [actionJson] with [id] and
/// [event].
Map<String, Object?> entry(int id, {String event = 'account_looked_up'}) => {
  ...actionJson,
  'id': id,
  'event': event,
};

/// The log's reads among the requests sent.
List<String> audits(Harness h) => [
  for (final c in h.actions)
    if (c.startsWith('GET /v1/admin/audit')) c,
];

Future<Harness> auditOf(
  WidgetTester tester,
  FutureOr<http.Response> Function(http.Request) audit,
) async {
  final h = Harness(signedIn: true, api: adminApi(audit: audit))
    ..family = ownerFamily
    ..roles = ['admin'];
  await h.pump(tester, initial: '/admin/auditoria');
  return h;
}

void main() {
  testWidgets('"Auditoria" reads the muted line, then each action as a '
      'read row, never a door', (tester) async {
    final h = await auditOf(
      tester,
      (_) => auditPage([entry(2), entry(1, event: 'video_hidden')]),
    );

    expect(find.text('Auditoria'), findsWidgets);
    expect(find.text(intro), findsOneWidget);
    expect(find.byType(AuditActionRow), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Conta buscada')).dy,
      lessThan(tester.getTopLeft(find.text('Outra ação da equipe')).dy),
    );
    expect(
      find.descendant(
        of: find.byType(AuditActionRow),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.text('Ver mais'), findsNothing);

    await tester.tap(find.text('Conta buscada'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/admin/auditoria');
    expect(audits(h), ['GET /v1/admin/audit']);
  });

  testWidgets('"Ver mais" appends the next page while there is one', (
    tester,
  ) async {
    final h = await auditOf(
      tester,
      (req) => switch (req.url.queryParameters['offset']) {
        null => auditPage([entry(3), entry(2)], next: 50),
        _ => auditPage([entry(1, event: 'mfa_reset')]),
      },
    );
    expect(find.byType(AuditActionRow), findsNWidgets(2));

    await tester.ensureVisible(find.text('Ver mais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver mais'));
    await tester.pumpAndSettle();

    expect(find.byType(AuditActionRow), findsNWidgets(3));
    expect(find.text('Verificação em duas etapas redefinida'), findsOneWidget);
    expect(find.text('Ver mais'), findsNothing);
    expect(audits(h), ['GET /v1/admin/audit', 'GET /v1/admin/audit?offset=50']);
  });

  testWidgets('an empty log says so', (tester) async {
    await auditOf(tester, (_) => auditPage([]));

    expect(find.text('Nenhuma ação da equipe ainda.'), findsOneWidget);
    expect(find.byType(AuditActionRow), findsNothing);
  });

  testWidgets('the placeholder while it loads; failed, the error note '
      'with "Tentar de novo"', (tester) async {
    final first = Completer<http.Response>();
    var reads = 0;
    await auditOf(
      tester,
      (_) => ++reads == 1 ? first.future : auditPage([entry(1)]),
    );

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    first.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyPlaceholder), findsNothing);
    expect(find.byType(ErrorNote), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNote), findsNothing);
    expect(find.byType(AuditActionRow), findsOneWidget);
  });

  testWidgets('not_admin goes home with today\'s notice', (tester) async {
    final h = await auditOf(tester, (_) => problem(403, 'not_admin'));

    expect(h.location(tester), '/');
    expect(
      find.text('Você não tem mais acesso à administração.'),
      findsOneWidget,
    );
  });

  testWidgets('back goes to Administração', (tester) async {
    final h = await auditOf(tester, (_) => auditPage([]));

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/admin');
  });
}
