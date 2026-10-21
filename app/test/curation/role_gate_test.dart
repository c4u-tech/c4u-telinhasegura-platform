import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/auth_api.dart';
import 'package:telinha_segura/curation/role_gate.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

Harness guardian({List<String> roles = const []}) => Harness(signedIn: true)
  ..family = ownerFamily
  ..roles = roles;

Future<String> open(WidgetTester tester, Harness h, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
  return h.location(tester);
}

void main() {
  group('the curation routes', () {
    test('their paths', () {
      expect(Routes.suggestions, '/sugestoes');
      expect(Routes.newSuggestion, '/sugestoes/nova');
      expect(Routes.curation, '/curadoria');
      expect(Routes.review('v/1'), '/curadoria/v%2F1');
      expect(Routes.approve('v1'), '/curadoria/v1/aprovar');
      expect(Routes.refuse('v1'), '/curadoria/v1/recusar');
      expect(
        Routes.refuse('v1', items: ['c04', 'c15']),
        '/curadoria/v1/recusar?itens=c04%2Cc15',
      );
      expect(Routes.refuseItems('c04,c15'), ['c04', 'c15']);
      expect(Routes.refuseItems(',c04,'), ['c04']);
      expect(Routes.refuseItems(''), isEmpty);
      expect(Routes.refuseItems(null), isEmpty);
      expect(Routes.admin, '/admin');
      expect(Routes.team, '/admin/equipe');
      expect(Routes.appoint, '/admin/equipe/nova');
      expect(
        Routes.appointFor('bia@example.com', PlatformRole.moderator),
        '/admin/equipe/nova?email=bia%40example.com&papel=moderacao',
      );
      expect(
        Routes.appointFor('bia@example.com', PlatformRole.curator),
        '/admin/equipe/nova?email=bia%40example.com&papel=curadoria',
      );
      expect(Routes.member('a/1'), '/admin/equipe/a%2F1');
      expect(Routes.heldVideos, '/moderacao/retidos');
      expect(Routes.heldVideo('v1'), '/moderacao/retidos/v1');
    });

    test('each is signed-in only', () {
      for (final path in [
        '/sugestoes',
        '/sugestoes/nova',
        '/curadoria',
        '/curadoria/v1',
        '/admin',
        '/admin/equipe',
        '/admin/equipe/nova',
        '/admin/equipe/a1',
        '/moderacao/retidos',
        '/moderacao/retidos/v1',
      ]) {
        expect(Routes.signedInOnly(path), isTrue, reason: path);
      }
      expect(Routes.signedInOnly('/sugestoesx'), isFalse);
      expect(Routes.signedInOnly('/administrar'), isFalse);
    });
  });

  group('roleRedirect', () {
    test('a curator route needs curator; an admin route needs admin', () {
      const both = {PlatformRole.admin, PlatformRole.curator};
      for (final path in ['/curadoria', '/curadoria/v1/aprovar']) {
        expect(roleRedirect({PlatformRole.curator}, path), isNull);
        expect(roleRedirect({PlatformRole.admin}, path), Routes.home);
        expect(roleRedirect(const {}, path), Routes.home);
      }
      for (final path in [
        '/admin',
        '/admin/equipe',
        '/admin/equipe/nova',
        '/admin/equipe/a1',
      ]) {
        expect(roleRedirect({PlatformRole.admin}, path), isNull);
        expect(roleRedirect({PlatformRole.curator}, path), Routes.home);
        expect(roleRedirect({PlatformRole.moderator}, path), Routes.home);
      }
      expect(roleRedirect(both, '/admin'), isNull);
    });

    test('a moderation route needs moderator or admin', () {
      for (final path in ['/moderacao/retidos', '/moderacao/retidos/v1']) {
        expect(roleRedirect({PlatformRole.moderator}, path), isNull);
        expect(roleRedirect({PlatformRole.admin}, path), isNull);
        expect(roleRedirect({PlatformRole.curator}, path), Routes.home);
        expect(roleRedirect(const {}, path), Routes.home);
      }
      expect(roleRedirect({PlatformRole.moderator}, '/admin'), Routes.home);
    });

    test('suggestions and every other path need no role', () {
      for (final path in ['/sugestoes', '/sugestoes/nova', '/', '/conta']) {
        expect(roleRedirect(const {}, path), isNull, reason: path);
      }
    });

    test('roles not read yet decide nothing: the screen reads them', () {
      expect(roleRedirect(null, '/curadoria'), isNull);
      expect(roleRedirect(null, '/admin'), isNull);
    });
  });

  group('the router', () {
    for (final (roles, curation, admin) in [
      (<String>[], '/', '/'),
      (['curator'], '/curadoria', '/'),
      (['admin'], '/', '/admin'),
      (['admin', 'curator'], '/curadoria', '/admin'),
    ]) {
      testWidgets('with roles $roles: /sugestoes renders, /curadoria lands on '
          '$curation, /admin on $admin', (tester) async {
        final h = guardian(roles: roles);
        await h.pump(tester);

        expect(await open(tester, h, '/sugestoes'), '/sugestoes');
        expect(find.text('Sugestões'), findsOneWidget);
        expect(await open(tester, h, '/curadoria'), curation);
        expect(await open(tester, h, '/admin'), admin);
        expect(
          await open(tester, h, '/admin/equipe'),
          admin == '/' ? '/' : '/admin/equipe',
        );
        expect(
          await open(tester, h, '/admin/equipe/a2'),
          admin == '/' ? '/' : '/admin/equipe/a2',
        );
      });
    }

    for (final (path, title) in [
      ('/sugestoes', 'Sugestões'),
      ('/curadoria', 'Curadoria'),
      ('/admin', 'Administração'),
    ]) {
      testWidgets('opened directly, $path reads the session for its '
          'role, renders "$title" and goes back home', (tester) async {
        final h = guardian(roles: ['admin', 'curator']);
        await h.pump(tester, initial: path);

        expect(h.location(tester), path);
        expect(
          find.descendant(
            of: find.byType(FieldLayout),
            matching: find.text(title),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Voltar'));
        await tester.pumpAndSettle();
        expect(h.location(tester), '/');
      });
    }

    for (final (roles, held) in [
      (<String>[], '/'),
      (['curator'], '/'),
      (['moderator'], '/moderacao/retidos'),
      (['admin'], '/moderacao/retidos'),
    ]) {
      testWidgets('with roles $roles: /moderacao/retidos lands on $held', (
        tester,
      ) async {
        final h = guardian(roles: roles);
        await h.pump(tester);

        expect(await open(tester, h, '/moderacao/retidos'), held);
        expect(await open(tester, h, '/moderacao/retidos/v1'), switch (held) {
          '/' => '/',
          _ => '/moderacao/retidos/v1',
        });
      });
    }

    testWidgets('opened directly without the role, /moderacao/retidos goes '
        'home', (tester) async {
      final h = guardian(roles: ['curator']);
      await h.pump(tester, initial: '/moderacao/retidos');

      expect(h.location(tester), '/');
    });

    testWidgets('opened directly without the role, /curadoria goes home', (
      tester,
    ) async {
      final h = guardian();
      await h.pump(tester, initial: '/curadoria');

      expect(h.location(tester), '/');
    });
  });

  group('takeLostRole', () {
    for (final (code, path, notice) in [
      ('not_curator', '/curadoria', 'Você não faz mais parte da curadoria.'),
      ('not_admin', '/admin', 'Você não tem mais acesso à administração.'),
    ]) {
      testWidgets('$code goes home with a notice, and the door goes with '
          'the session read again', (tester) async {
        final h = guardian(roles: ['admin', 'curator']);
        await h.pump(tester, initial: path);
        h.roles = [code == 'not_curator' ? 'admin' : 'curator'];
        final reads = h.calls.where((c) => c == 'GET /v1/session').length;

        final took = takeLostRole(
          tester.element(find.byType(FieldLayout)),
          ApiError(status: 403, code: code),
        );
        await tester.pumpAndSettle();

        expect(took, isTrue);
        expect(h.location(tester), '/');
        expect(find.text(notice), findsOneWidget);
        final door = code == 'not_curator' ? 'Curadoria' : 'Administração';
        expect(find.widgetWithText(DoorRow, door), findsNothing);
        expect(h.calls.where((c) => c == 'GET /v1/session').length, reads + 1);
      });
    }

    testWidgets('not_moderator goes home with a notice, and the session is '
        'read again', (tester) async {
      final h = guardian(roles: ['admin', 'moderator']);
      await h.pump(tester, initial: '/admin');
      h.roles = ['admin'];
      final reads = h.calls.where((c) => c == 'GET /v1/session').length;

      final took = takeLostRole(
        tester.element(find.byType(FieldLayout)),
        const ApiError(status: 403, code: 'not_moderator'),
      );
      await tester.pumpAndSettle();

      expect(took, isTrue);
      expect(h.location(tester), '/');
      expect(
        find.text('Você não tem mais acesso à moderação.'),
        findsOneWidget,
      );
      expect(h.calls.where((c) => c == 'GET /v1/session').length, reads + 1);
    });

    testWidgets('any other problem is not taken', (tester) async {
      final h = guardian(roles: ['curator']);
      await h.pump(tester, initial: '/curadoria');

      final took = takeLostRole(
        tester.element(find.byType(FieldLayout)),
        const ApiError(status: 404, code: 'not_found'),
      );
      await tester.pumpAndSettle();

      expect(took, isFalse);
      expect(h.location(tester), '/curadoria');
      expect(
        takeLostRole(
          tester.element(find.byType(FieldLayout)),
          StateError('socket'),
        ),
        isFalse,
      );
    });
  });
}
