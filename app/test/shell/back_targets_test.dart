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
    ('/familia/tempo', <String>[], '/familia'),
    ('/familia/videos', <String>[], '/familia'),
    ('/familia/excluir', <String>[], '/familia'),
    ('/modo-crianca', <String>[], '/familia'),
    ('/curadoria', ['curator'], '/equipe'),
    ('/curadoria/termo', ['curator'], '/equipe'),
    ('/pacotinhos', ['curator'], '/equipe'),
    ('/admin', ['admin'], '/equipe'),
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
}
