import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../account/mfa_fixtures.dart';
import '../curation/fixtures.dart';
import '../family/fixtures.dart';

const challengeTitle = 'Código do app autenticador';
const enrollTitle = 'Conecte o app autenticador';

/// Ana, holding [roles], opening [initial]; the status answers [status]
/// (required, enrolled, not elevated by default), the staff and pacotinho
/// routes as their fixtures do.
Future<Harness> gate(
  WidgetTester tester, {
  required String initial,
  List<String> roles = const ['admin'],
  FutureOr<http.Response> Function()? status,
}) async {
  final h =
      Harness(
          signedIn: true,
          api: mfaApi(
            status: status ?? () => json(200, mfaStatusJson()),
            other: (req) => req.url.path.contains('packs')
                ? packApi()(req)
                : adminApi()(req),
          ),
        )
        ..family = ownerFamily
        ..roles = roles;
  await h.pump(tester, initial: initial);
  return h;
}

Map<String, Object?> elevated() => mfaStatusJson(
  elevatedUntil: DateTime.now().add(const Duration(minutes: 30)),
);

int statusReads(Harness h) =>
    h.actions.where((c) => c == 'GET /v1/staff/mfa').length;

List<String> staffReads(Harness h) => [
  for (final c in h.actions)
    if (c.startsWith('GET /v1/admin') || c.startsWith('GET /v1/moderation')) c,
];

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> pass(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).last, '123456');
  await tapText(tester, 'Confirmar');
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('not required: the route opens, the status read before the '
      'screen\'s own', (tester) async {
    final h = await gate(
      tester,
      initial: '/admin/equipe',
      status: () => json(200, mfaStatusJson(enrolled: false, required: false)),
    );

    expect(find.text('Nomear alguém'), findsOneWidget);
    expect(find.text(challengeTitle), findsNothing);
    final reads = h.actions.where((c) => c.startsWith('GET')).toList();
    expect(reads.indexOf('GET /v1/staff/mfa'), 0);
    expect(reads, contains('GET /v1/admin/staff'));
  });

  testWidgets('required and elevated: the route opens with no challenge', (
    tester,
  ) async {
    final h = await gate(
      tester,
      initial: '/admin/equipe',
      status: () => json(200, elevated()),
    );

    expect(find.text(challengeTitle), findsNothing);
    expect(staffReads(h), ['GET /v1/admin/staff']);
  });

  testWidgets('required and not elevated: the challenge first, then the '
      'route', (tester) async {
    final h = await gate(tester, initial: '/admin/equipe');

    expect(find.text(challengeTitle), findsOneWidget);
    expect(staffReads(h), isEmpty);

    await pass(tester);

    expect(find.text(challengeTitle), findsNothing);
    expect(h.location(tester), '/admin/equipe');
    expect(staffReads(h), ['GET /v1/admin/staff']);
    expect(find.text('Nomear alguém'), findsOneWidget);
  });

  testWidgets('shows the loading placeholder while the status is read', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await gate(tester, initial: '/admin', status: () => answer.future);

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.text('Equipe'), findsNothing);
    answer.complete(json(200, elevated()));
    await tester.pumpAndSettle();
    expect(find.text('Equipe'), findsOneWidget);
  });

  testWidgets('a cancelled challenge goes home', (tester) async {
    final h = await gate(tester, initial: '/admin/equipe');

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/');
    expect(staffReads(h), isEmpty);
  });

  testWidgets('required and not enrolled: the enrollment, then the route', (
    tester,
  ) async {
    final h = await gate(
      tester,
      initial: '/admin/equipe',
      status: () => json(200, mfaStatusJson(enrolled: false)),
    );

    expect(
      h.location(tester),
      '/conta/verificacao/ativar?depois=%2Fadmin%2Fequipe',
    );
    expect(find.text(enrollTitle), findsOneWidget);
    await tapText(tester, 'Já adicionei');
    await tester.enterText(find.byType(TextField), '123456');
    await tapText(tester, 'Confirmar');
    await tapText(tester, 'Guardei os códigos em um lugar seguro');
    final before = statusReads(h);
    await tapText(tester, 'Continuar');

    expect(h.location(tester), '/admin/equipe');
    expect(find.text(challengeTitle), findsNothing);
    expect(find.text('Nomear alguém'), findsOneWidget);
    // The confirm elevated the session: no status read, no challenge.
    expect(statusReads(h), before);
  });

  testWidgets('a cancelled enrollment goes home', (tester) async {
    final h = await gate(
      tester,
      initial: '/admin',
      status: () => json(200, mfaStatusJson(enrolled: false)),
    );

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/');
  });

  testWidgets('a direct URL deep in the area reads the status once and asks '
      'once', (tester) async {
    final h = await gate(tester, initial: '/admin/equipe/a2');

    expect(find.text(challengeTitle), findsOneWidget);
    expect(statusReads(h), 1);
    await pass(tester);

    expect(find.text(challengeTitle), findsNothing);
    expect(h.location(tester), '/admin/equipe/a2');
    expect(find.text('Tirar da curadoria'), findsOneWidget);
    expect(statusReads(h), 1);
  });

  testWidgets('no new challenge or status read moving inside the area while '
      'elevated', (tester) async {
    final h = await gate(tester, initial: '/admin');
    await pass(tester);
    final reads = statusReads(h);

    await tapText(tester, 'Equipe');
    await go(tester, '/moderacao/retidos');
    await go(tester, '/admin/pacotinhos');

    expect(find.text(challengeTitle), findsNothing);
    expect(statusReads(h), reads);
    expect(h.actions, contains('GET /v1/admin/packs'));
  });

  testWidgets('the moderation routes are gated for a moderator', (
    tester,
  ) async {
    final h = await gate(
      tester,
      initial: '/moderacao/retidos',
      roles: const ['moderator'],
    );

    expect(find.text(challengeTitle), findsOneWidget);
    expect(staffReads(h), isEmpty);
    await pass(tester);
    expect(staffReads(h), ['GET /v1/moderation/videos?state=held']);
  });

  for (final path in ['/curadoria', '/pacotinhos']) {
    testWidgets('$path never reads the status', (tester) async {
      final h = await gate(
        tester,
        initial: path,
        roles: const ['curator', 'admin'],
      );

      expect(find.text(challengeTitle), findsNothing);
      expect(statusReads(h), 0);
    });
  }

  testWidgets('without the area\'s role: home, and no MFA call', (
    tester,
  ) async {
    final h = await gate(tester, initial: '/admin', roles: const ['curator']);

    expect(h.location(tester), '/');
    expect(statusReads(h), 0);
  });

  testWidgets('a status that cannot be read opens the route: the server '
      'still decides, and the screens ask then', (tester) async {
    final h = await gate(
      tester,
      initial: '/admin/equipe',
      status: () => problem(500, 'internal'),
    );

    expect(find.text(challengeTitle), findsNothing);
    expect(staffReads(h), ['GET /v1/admin/staff']);
  });
}
