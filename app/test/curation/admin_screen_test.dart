import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'curation_api_test.dart' show pendingJson;
import 'fixtures.dart';
import 'queue_screen_test.dart' show goTo;

Future<Harness> admin(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? staff,
  FutureOr<http.Response> Function()? held,
  FutureOr<http.Response> Function()? metrics,
  String initial = '/admin',
}) async {
  final h =
      Harness(
          signedIn: true,
          api: adminApi(staff: staff, held: held, metrics: metrics),
        )
        ..family = ownerFamily
        ..roles = ['admin'];
  await h.pump(tester, initial: initial);
  return h;
}

void main() {
  testWidgets('the seven numbers on top in order, "." thousands, a '
      'suppressed count as "menos de 5", then the suppression line', (
    tester,
  ) async {
    await admin(tester);

    final rows = tester.widgetList<FigureRow>(find.byType(FigureRow));
    expect(
      [for (final r in rows) (r.label, r.figure)],
      [
        ('Contas', '1.240'),
        ('Famílias', '412'),
        ('Crianças', 'menos de 5'),
        ('Aparelhos ativos', '38'),
        ('Vídeos no catálogo', '12.500'),
        ('Pacotinhos publicados', 'menos de 5'),
        ('Denúncias nos últimos 7 dias', 'menos de 5'),
      ],
    );
    const line = 'Números abaixo de 5 aparecem como “menos de 5”.';
    final lastFigure = tester.getBottomLeft(find.byType(FigureRow).last).dy;
    expect(tester.getTopLeft(find.text(line)).dy, greaterThan(lastFigure));
    expect(
      tester.getTopLeft(find.widgetWithText(DoorRow, 'Buscar uma conta')).dy,
      greaterThan(tester.getBottomLeft(find.text(line)).dy),
    );
  });

  testWidgets('while the numbers load, the placeholder stands in their '
      'place; failed, the error note with "Tentar de novo", the doors '
      'still there', (tester) async {
    final first = Completer<http.Response>();
    var reads = 0;
    final h = await admin(
      tester,
      metrics: () => switch (++reads) {
        1 => first.future,
        2 => problem(503, 'unavailable'),
        _ => json(200, metricsJson),
      },
    );

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.byType(FigureRow), findsNothing);
    first.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyPlaceholder), findsNothing);
    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Buscar uma conta'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Auditoria'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNote), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNote), findsNothing);
    expect(find.byType(FigureRow), findsNWidgets(7));
    expect(h.actions.where((c) => c == 'GET /v1/admin/metrics'), hasLength(3));
  });

  testWidgets('coming back reads the numbers again', (tester) async {
    var accounts = 1240;
    final h = await admin(
      tester,
      metrics: () => json(200, {...metricsJson, 'accounts': accounts}),
    );
    expect(find.text('1.240'), findsOneWidget);

    goTo(tester, '/admin/equipe');
    await tester.pumpAndSettle();
    accounts = 1241;
    goTo(tester, '/admin');
    await tester.pumpAndSettle();

    expect(find.text('1.241'), findsOneWidget);
    expect(h.actions.where((c) => c == 'GET /v1/admin/metrics'), hasLength(2));
  });

  testWidgets('a numbers read refused for a lost role goes home', (
    tester,
  ) async {
    final h = await admin(tester, metrics: () => problem(403, 'not_admin'));

    expect(h.location(tester), '/');
    expect(
      find.text('Você não tem mais acesso à administração.'),
      findsOneWidget,
    );
  });

  testWidgets('offers "Buscar uma conta", "Equipe", "Vídeos retidos", '
      '"Pacotinhos" and "Auditoria" as doors in that order, the counts '
      'kept', (tester) async {
    final h = await admin(
      tester,
      staff: () => staffList([selfMember]),
      held: () => heldList([heldOf(pendingJson)]),
    );

    const doors = [
      'Buscar uma conta',
      'Equipe',
      'Vídeos retidos',
      'Pacotinhos',
      'Auditoria',
    ];
    final tops = [
      for (final door in doors)
        tester.getTopLeft(find.widgetWithText(DoorRow, door)).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(
      find.descendant(
        of: find.widgetWithText(DoorRow, 'Buscar uma conta'),
        matching: find.text('Por e-\u2060mail ou código, com motivo'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(DoorRow, 'Auditoria'),
        matching: find.text('Ações da equipe'),
      ),
      findsOneWidget,
    );
    expect(find.text('1 pessoa'), findsOneWidget);
    expect(find.text('1 vídeo'), findsOneWidget);

    await tester.tap(find.text('Buscar uma conta'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/admin/contas');
    expect(find.text('Buscar uma conta'), findsWidgets);

    goTo(tester, '/admin');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Auditoria'));
    await tester.tap(find.text('Auditoria'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/admin/auditoria');
  });

  testWidgets('offers "Equipe", "Vídeos retidos" and "Pacotinhos" as '
      'doors in that order, each with its count', (tester) async {
    await admin(
      tester,
      staff: () => staffList([
        selfMember,
        memberOf('a2', 'bia@example.com', [curatorRole()]),
      ]),
      held: () => heldList([heldOf(pendingJson)]),
    );

    expect(find.text('Administração'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Equipe'), findsOneWidget);
    expect(find.text('2 pessoas'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Vídeos retidos'), findsOneWidget);
    expect(find.text('1 vídeo'), findsOneWidget);
    final tops = [
      for (final door in ['Equipe', 'Vídeos retidos', 'Pacotinhos'])
        tester.getTopLeft(find.widgetWithText(DoorRow, door)).dy,
    ];
    expect(tops, [...tops]..sort());
  });

  testWidgets('one member reads "1 pessoa"', (tester) async {
    await admin(tester, staff: () => staffList([selfMember]));

    expect(find.text('1 pessoa'), findsOneWidget);
  });

  testWidgets('a count not read yet, or not read at all, is left out', (
    tester,
  ) async {
    final staff = Completer<http.Response>();
    await admin(
      tester,
      staff: () => staff.future,
      held: () => problem(503, 'unavailable'),
    );

    expect(find.widgetWithText(DoorRow, 'Equipe'), findsOneWidget);
    expect(find.widgetWithText(DoorRow, 'Vídeos retidos'), findsOneWidget);
    expect(find.textContaining('pessoa'), findsNothing);
    expect(find.textContaining('vídeo'), findsNothing);
    staff.complete(staffList([selfMember]));
    await tester.pumpAndSettle();
    expect(find.text('1 pessoa'), findsOneWidget);
  });

  testWidgets('the doors open the team and the held videos', (tester) async {
    final h = await admin(tester);

    await tester.ensureVisible(find.text('Equipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equipe'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/admin/equipe');

    goTo(tester, '/admin');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Vídeos retidos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vídeos retidos'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/moderacao/retidos');
  });

  testWidgets('coming back reads the counts again', (tester) async {
    var held = 2;
    final h = await admin(
      tester,
      held: () =>
          heldList([for (var i = 0; i < held; i++) heldOf(pendingJson)]),
    );
    expect(find.text('2 vídeos'), findsOneWidget);

    goTo(tester, '/moderacao/retidos');
    await tester.pumpAndSettle();
    held = 1;
    goTo(tester, '/admin');
    await tester.pumpAndSettle();

    expect(find.text('1 vídeo'), findsOneWidget);
    expect(h.actions.where((c) => c == 'GET /v1/admin/staff'), hasLength(2));
  });

  testWidgets('not_admin goes home with a notice', (tester) async {
    final h = await admin(tester, staff: () => problem(403, 'not_admin'));

    expect(h.location(tester), '/');
    expect(
      find.text('Você não tem mais acesso à administração.'),
      findsOneWidget,
    );
  });
}
