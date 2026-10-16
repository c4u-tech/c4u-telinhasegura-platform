import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/auth_api.dart';
import 'package:telinha_segura/curation/role_gate.dart';
import 'package:telinha_segura/shell/routes.dart';

import 'role_gate_test.dart' show guardian, open;

void main() {
  group('the pacotinho routes (pacotinho curation screens, Routes)', () {
    test('their paths', () {
      expect(Routes.packs, '/pacotinhos');
      expect(Routes.newPack, '/pacotinhos/novo');
      expect(Routes.newPackVideos, '/pacotinhos/novo/videos');
      expect(Routes.packReview('p/1'), '/pacotinhos/p%2F1');
      expect(Routes.packVideo('p1', 'v/1'), '/pacotinhos/p1/videos/v%2F1');
      expect(Routes.approvePack('p1'), '/pacotinhos/p1/aprovar');
      expect(Routes.refusePack('p1'), '/pacotinhos/p1/recusar');
      expect(Routes.recompose('p1'), '/pacotinhos/p1/mudar');
      expect(Routes.recomposeVideos('p1'), '/pacotinhos/p1/mudar/videos');
      expect(Routes.adminPacks, '/admin/pacotinhos');
      expect(Routes.adminPack('p/1'), '/admin/pacotinhos/p%2F1');
    });

    test('each is signed-in only', () {
      for (final path in [
        '/pacotinhos',
        '/pacotinhos/novo/videos',
        '/pacotinhos/p1/mudar',
        '/admin/pacotinhos/p1',
      ]) {
        expect(Routes.signedInOnly(path), isTrue, reason: path);
      }
      expect(Routes.signedInOnly('/pacotinhosx'), isFalse);
    });
  });

  group('roleRedirect', () {
    test('a pacotinho route needs curator; the admin ones need admin', () {
      for (final path in ['/pacotinhos', '/pacotinhos/p1/recusar']) {
        expect(roleRedirect({PlatformRole.curator}, path), isNull);
        expect(roleRedirect({PlatformRole.admin}, path), Routes.home);
        expect(roleRedirect(const {}, path), Routes.home);
      }
      for (final path in ['/admin/pacotinhos', '/admin/pacotinhos/p1']) {
        expect(roleRedirect({PlatformRole.admin}, path), isNull);
        expect(roleRedirect({PlatformRole.curator}, path), Routes.home);
      }
    });
  });

  group('the router', () {
    for (final (roles, packs, admin) in [
      (<String>[], '/', '/'),
      (['curator'], '/pacotinhos', '/'),
      (['admin'], '/', '/admin/pacotinhos'),
    ]) {
      testWidgets('with roles $roles: /pacotinhos lands on $packs, '
          '/admin/pacotinhos on $admin', (tester) async {
        final h = guardian(roles: roles);
        await h.pump(tester);

        expect(await open(tester, h, '/pacotinhos'), packs);
        expect(await open(tester, h, '/admin/pacotinhos'), admin);
      });
    }
  });
}
