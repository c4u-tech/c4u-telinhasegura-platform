import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/shell/routes.dart';

void main() {
  group('the link scheme maps onto /vincular-aparelho', () {
    for (final (link, location) in [
      (
        'telinhasegura://vincular?codigo=ABCD1234',
        '/vincular-aparelho?codigo=ABCD1234',
      ),
      // go_router gives an empty path a slash.
      (
        'telinhasegura://vincular/?codigo=abcd-1234',
        '/vincular-aparelho?codigo=abcd-1234',
      ),
      ('telinhasegura://vincular', '/vincular-aparelho'),
      ('TelinhaSegura://vincular?codigo=X', '/vincular-aparelho?codigo=X'),
    ]) {
      test(link, () {
        expect(Routes.fromDeepLink(Uri.parse(link)), location);
      });
    }

    for (final other in [
      '/vincular-aparelho?codigo=ABCD1234',
      '/',
      'telinhasegura://outro?codigo=X',
      'telinhasegura://vincular/mais?codigo=X',
      'https://vincular?codigo=X',
    ]) {
      test('$other is not the link', () {
        expect(Routes.fromDeepLink(Uri.parse(other)), isNull);
      });
    }
  });
}
