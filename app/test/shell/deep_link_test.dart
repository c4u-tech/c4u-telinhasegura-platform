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

  group('the share link maps onto /sugestoes/nova', () {
    test('with a YouTube URL', () {
      final mapped = Uri.parse(
        Routes.fromDeepLink(
          Uri.parse(
            'telinhasegura://sugerir?texto='
            '${Uri.encodeQueryComponent('Título https://youtu.be/dQw4w9WgXcQ?si=a')}',
          ),
        )!,
      );
      expect(mapped.path, '/sugestoes/nova');
      expect(mapped.queryParameters, {'link': 'https://youtu.be/dQw4w9WgXcQ'});
    });
    test('with the text as the native side encodes it', () {
      final texto = Uri.encodeComponent(
        'Ação + diversão & #1 https://youtu.be/dQw4w9WgXcQ?si=a',
      );
      final mapped = Uri.parse(
        Routes.fromDeepLink(Uri.parse('telinhasegura://sugerir?texto=$texto'))!,
      );
      expect(mapped.path, '/sugestoes/nova');
      expect(mapped.queryParameters, {'link': 'https://youtu.be/dQw4w9WgXcQ'});
    });
    test(
      'without one',
      () => expect(
        Routes.fromDeepLink(Uri.parse('telinhasegura://sugerir?texto=oi')),
        '/sugestoes/nova',
      ),
    );
    test(
      'bare',
      () => expect(
        Routes.fromDeepLink(Uri.parse('telinhasegura://sugerir')),
        '/sugestoes/nova',
      ),
    );
    for (final other in [
      'telinhasegura://sugerir/mais?texto=x',
      'https://sugerir?texto=x',
    ]) {
      test(
        '$other is not the link',
        () => expect(Routes.fromDeepLink(Uri.parse(other)), isNull),
      );
    }
  });
}
