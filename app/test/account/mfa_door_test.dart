import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'account_screen_test.dart' show door, lineOf, attempted;
import 'mfa_fixtures.dart';

const doorTitle = 'Verificação em duas etapas';

/// `/conta` for Ana holding [roles], whose status read answers [status].
Future<Harness> accountWithRoles(
  WidgetTester tester, {
  List<String> roles = const ['admin'],
  FutureOr<http.Response> Function()? status,
}) async {
  final h = Harness(signedIn: true, api: mfaApi(status: status))
    ..family = ownerFamily
    ..roles = roles;
  await h.pump(tester, initial: '/conta');
  return h;
}

void main() {
  testWidgets('a role holder sees the door between Senha and Aparelhos '
      'conectados', (tester) async {
    final semantics = tester.ensureSemantics();
    await accountWithRoles(tester);

    expect(
      tester.widgetList<DoorRow>(find.byType(DoorRow)).map((d) => d.title),
      [
        'E-⁠mail',
        'Senha',
        doorTitle,
        'Aparelhos conectados',
        'Seus dados',
        'Termos de uso',
        'Política de privacidade',
      ],
    );
    expect(lineOf(doorTitle, 'Ativada desde 7 de outubro'), findsOne);
    expect(
      find.bySemanticsLabel('$doorTitle, Ativada desde 7 de outubro'),
      findsOne,
    );
    semantics.dispose();
  });

  for (final (roles, required, line) in [
    (['admin'], true, 'Necessária para a administração'),
    (['admin', 'moderator'], true, 'Necessária para a administração'),
    (['moderator'], true, 'Necessária para a moderação'),
    (['curator', 'moderator'], true, 'Necessária para a moderação'),
    (['curator'], false, 'Opcional para a curadoria'),
    // The switch off: no role needs it, and only a curator's line names
    // the curation.
    (['admin'], false, 'Opcional'),
    (['moderator'], false, 'Opcional'),
    (['curator', 'admin'], false, 'Opcional'),
  ]) {
    testWidgets('not enrolled, $roles: "$line"', (tester) async {
      await accountWithRoles(
        tester,
        roles: roles,
        status: () =>
            json(200, mfaStatusJson(enrolled: false, required: required)),
      );

      expect(lineOf(doorTitle, line), findsOne);
    });
  }

  for (final (name, answer) in [
    ('mfa_unavailable', () => problem(503, 'mfa_unavailable')),
    ('a failed read', () => problem(500, 'internal')),
  ]) {
    testWidgets('$name: "Indisponível no momento", and the door still opens', (
      tester,
    ) async {
      await accountWithRoles(tester, status: answer);

      expect(lineOf(doorTitle, 'Indisponível no momento'), findsOne);
      await tester.tap(door(doorTitle));
      await tester.pumpAndSettle();
      expect(attempted(tester), '/conta/verificacao');
    });
  }

  testWidgets('the door opens /conta/verificacao', (tester) async {
    await accountWithRoles(tester);

    await tester.tap(door(doorTitle));
    await tester.pumpAndSettle();

    expect(attempted(tester), '/conta/verificacao');
  });

  testWidgets('without a platform role: no door, and no MFA call', (
    tester,
  ) async {
    final h = await accountWithRoles(tester, roles: const []);

    expect(door(doorTitle), findsNothing);
    expect(find.byType(DoorRow), findsNWidgets(6));
    expect(h.calls.where((c) => c.contains('/v1/staff/mfa')), isEmpty);
  });
}
