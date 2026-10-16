import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/shell/routes.dart';

void main() {
  group('the enrollment\'s return path', () {
    test('takes an admin or moderation path, its query kept', () {
      for (final path in [
        '/admin',
        '/admin/equipe',
        '/admin/equipe/nova?email=bia%40example.com&papel=moderacao',
        '/moderacao/retidos',
        '/moderacao/retidos/v1',
      ]) {
        expect(Routes.staffReturn(path), path, reason: path);
      }
    });

    test('refuses anything else: no open redirect', () {
      for (final path in [
        null,
        '',
        'admin',
        '/',
        '/conta',
        '/curadoria',
        '/administracao',
        '/admin/../conta',
        '/admin/%2e%2e/conta',
        '/admin//equipe',
        '//evil.example/admin',
        'https://evil.example/admin',
        'javascript:alert(1)//admin',
        '/admin#x',
      ]) {
        expect(Routes.staffReturn(path), isNull, reason: '$path');
      }
    });

    test('the enrollment route carries it as depois', () {
      expect(Routes.mfaEnrollment(), '/conta/verificacao/ativar');
      expect(
        Routes.mfaEnrollment(then: '/admin/equipe'),
        '/conta/verificacao/ativar?depois=%2Fadmin%2Fequipe',
      );
    });
  });
}
