import 'package:flutter_test/flutter_test.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

void main() {
  // Where each screen that used to return home now returns: the root of
  // the destination it belongs to.
  for (final (path, roles, back) in [
    ('/familia/criancas', <String>[], '/familia'),
    ('/familia/responsaveis', <String>[], '/familia'),
    ('/familia/convites', <String>[], '/familia'),
    ('/familia/excluir', <String>[], '/familia'),
    ('/modo-crianca', <String>[], '/familia'),
    ('/curadoria', ['curator'], '/equipe'),
    ('/curadoria/termo', ['curator'], '/equipe'),
    ('/pacotinhos', ['curator'], '/equipe'),
    ('/admin/numeros', ['admin'], '/equipe'),
    ('/admin/equipe', ['admin'], '/equipe'),
    ('/admin/contas', ['admin'], '/equipe'),
    ('/admin/auditoria', ['admin'], '/equipe'),
    ('/moderacao/auditoria', ['moderator'], '/equipe'),
    ('/moderacao/retidos', ['admin'], '/equipe'),
    ('/pacotinhos', ['admin'], '/equipe'),
    ('/pacotinhos/p1', ['admin'], '/pacotinhos'),
    ('/pacotinhos/p1', ['admin', 'curator'], '/pacotinhos'),
    ('/moderacao/retidos', ['moderator'], '/equipe'),
    // A suggestion is the home's.
    ('/sugestoes', <String>[], '/'),
  ]) {
    testWidgets('back from $path goes to $back', (tester) async {
      final h = Harness(signedIn: true)
        ..family = ownerFamily
        ..roles = roles;
      await h.pump(tester, initial: path);

      await tester.tap(find.byTooltip('Voltar').first);
      await tester.pumpAndSettle();

      expect(h.location(tester), back);
    });
  }

  // A child's page returns to the children; every errand opened from it
  // returns to it.
  for (final (path, back) in [
    ('/familia/criancas/m1', '/familia/criancas'),
    ('/familia/criancas/m1/editar', '/familia/criancas/m1'),
    ('/familia/tempo/m1/mais', '/familia/criancas/m1'),
    ('/familia/tempo/m1/limite', '/familia/criancas/m1'),
    ('/familia/videos/m1', '/familia/criancas/m1'),
    ('/familia/videos/m1/v1', '/familia/criancas/m1'),
    ('/familia/videos/m1/pacotinho/k1', '/familia/criancas/m1'),
  ]) {
    testWidgets('back from $path goes to $back', (tester) async {
      final h = Harness(signedIn: true)..family = ownerFamily;
      await h.pump(tester, initial: path);

      await tester.tap(find.byTooltip('Voltar').first);
      await tester.pumpAndSettle();

      expect(h.location(tester), back);
    });
  }
}
