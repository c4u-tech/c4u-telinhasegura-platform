import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/staff/staff_root_screen.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

/// `/equipe`, the Equipe destination's root, for a session holding
/// [roles].
Future<Harness> staffRoot(
  WidgetTester tester, {
  required List<String> roles,
  Map<String, Object?>? family = ownerFamily,
}) async {
  final h = Harness(signedIn: true)
    ..family = family
    ..roles = roles;
  await h.pump(tester, initial: '/equipe');
  return h;
}

List<String> titles(WidgetTester tester) => tester
    .widgetList<DoorRow>(find.byType(DoorRow))
    .map((d) => d.title)
    .toList();

void main() {
  // Each door's line, path and the roles that show it.
  const doors = {
    'Curadoria': ('Fila de revisão', '/curadoria', ['curator']),
    'Pacotinhos': ('Montar e revisar', '/pacotinhos', ['curator']),
    'Moderação': ('Vídeos retidos', '/moderacao/retidos', ['moderator']),
    'Administração': (
      'Contas, equipe, vídeos e auditoria',
      '/admin',
      ['admin'],
    ),
  };

  for (final (roles, expected) in [
    (['curator'], ['Curadoria', 'Pacotinhos']),
    (['curator', 'moderator'], ['Curadoria', 'Pacotinhos', 'Moderação']),
    (['moderator'], ['Moderação']),
    (['admin'], ['Administração']),
    (['admin', 'curator'], ['Curadoria', 'Pacotinhos', 'Administração']),
    // An admin who also moderates reaches the held videos from
    // Administração.
    (['admin', 'moderator'], ['Administração']),
    (
      ['admin', 'curator', 'moderator'],
      ['Curadoria', 'Pacotinhos', 'Administração'],
    ),
  ]) {
    testWidgets('with $roles, Equipe lists $expected', (tester) async {
      await staffRoot(tester, roles: roles);

      expect(find.byType(StaffRootScreen), findsOneWidget);
      expect(find.text('Equipe'), findsWidgets);
      expect(titles(tester), expected);
    });
  }

  for (final MapEntry(key: title, value: (line, path, roles))
      in doors.entries) {
    testWidgets('$title says "$line" and opens $path', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await staffRoot(tester, roles: roles);
      final door = find.widgetWithText(DoorRow, title);

      expect(
        find.descendant(of: door, matching: find.text(line)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('$title, $line'), findsOne);
      await tester.tap(door);
      await tester.pumpAndSettle();

      expect(h.location(tester), path);
      semantics.dispose();
    });
  }

  testWidgets('a session with no platform role is sent home', (tester) async {
    final h = await staffRoot(tester, roles: []);

    expect(h.location(tester), '/');
    expect(find.byType(StaffRootScreen), findsNothing);
  });

  testWidgets('with no family, the staff root still opens, with its back '
      'to the home', (tester) async {
    final h = await staffRoot(tester, roles: ['curator'], family: null);

    expect(h.location(tester), '/equipe');
    expect(titles(tester), ['Curadoria', 'Pacotinhos']);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/');
  });

  testWidgets('in the shell, the staff root has no back control', (
    tester,
  ) async {
    await staffRoot(tester, roles: ['curator']);

    expect(find.byTooltip('Voltar'), findsNothing);
  });
}
