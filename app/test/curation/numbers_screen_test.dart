import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';
import 'queue_screen_test.dart' show goTo;

Future<Harness> admin(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? staff,
  FutureOr<http.Response> Function()? held,
  FutureOr<http.Response> Function()? metrics,
  String initial = '/admin/numeros',
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
    // The numbers alone: the admin's doors are Equipe's.
    expect(find.byType(DoorRow), findsNothing);
    expect(find.text('Números da plataforma'), findsWidgets);
  });

  testWidgets('while the numbers load, the placeholder stands in their '
      'place; failed, the error note with "Tentar de novo"', (tester) async {
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
    goTo(tester, '/admin/numeros');
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

  testWidgets('back goes to Equipe', (tester) async {
    final h = await admin(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/equipe');
  });
}
