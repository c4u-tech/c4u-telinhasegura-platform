import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/legal/legal_links.dart';
import 'package:telinha_segura/legal/terms_update_screen.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

/// Ana, signed in with a family, who has not accepted the current terms.
/// `POST /v1/account/terms` answers [accept] (204 by default) and, on a
/// 204, the account reads as accepted from then on.
Future<Harness> outdated(
  WidgetTester tester, {
  String initial = '/',
  http.Response Function()? accept,
  String status = 'active',
}) async {
  late final Harness h;
  h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.method == 'POST' && req.url.path == '/v1/account/terms') {
              final answer = accept?.call() ?? http.Response('', 204);
              if (answer.statusCode == 204) h.termsAccepted = true;
              return answer;
            }
            return http.Response('', 204);
          },
        )
        ..family = ownerFamily
        ..status = status
        ..termsAccepted = false;
  await h.pump(tester, initial: initial);
  return h;
}

void main() {
  testWidgets('the screen: title, the text, both links and both actions', (
    tester,
  ) async {
    final h = await outdated(tester);

    expect(h.location(tester), '/termos');
    expect(find.byType(TermsUpdateScreen), findsOneWidget);
    expect(find.text('Atualizamos os termos'), findsOneWidget);
    expect(find.text(termsUpdateText), findsOneWidget);
    expect(find.text('Termos de uso'), findsOneWidget);
    expect(find.text('Política de privacidade'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Concordo'), findsOneWidget);
    expect(find.text('Sair da conta'), findsOneWidget);
  });

  for (final path in [
    '/conta',
    '/conta/dados',
    '/familia/criancas',
    '/familia/tempo',
    '/modo-crianca',
    '/curadoria',
  ]) {
    testWidgets('$path waits behind the terms', (tester) async {
      final h = await outdated(tester, initial: path);

      expect(h.location(tester), '/termos');
    });
  }

  testWidgets('the links open the site pages', (tester) async {
    final h = await outdated(tester);

    await tester.ensureVisible(find.text('Termos de uso'));
    await tester.tap(find.text('Termos de uso'));
    await tester.ensureVisible(find.text('Política de privacidade'));
    await tester.tap(find.text('Política de privacidade'));
    await tester.pumpAndSettle();

    expect(h.links.opened, [kTermsUrl, kPrivacyUrl]);
    expect(h.location(tester), '/termos');
  });

  testWidgets('Concordo records the acceptance, reads the session again '
      'and leaves for the home', (tester) async {
    final h = await outdated(tester);
    final reads = h.calls.where((c) => c == 'GET /v1/session').length;

    await tester.ensureVisible(find.text('Concordo'));
    await tester.tap(find.text('Concordo'));
    await tester.pumpAndSettle();

    expect(h.actions, [
      'POST /v1/account/terms {"terms_version":"2026-10-17"}',
    ]);
    expect(
      h.calls.where((c) => c == 'GET /v1/session').length,
      greaterThan(reads),
    );
    expect(h.location(tester), '/');
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    expect(find.byType(TermsUpdateScreen), findsNothing);
  });

  testWidgets('a refused acceptance says why and stays', (tester) async {
    final h = await outdated(
      tester,
      accept: () => problem(409, 'terms_outdated'),
    );

    await tester.ensureVisible(find.text('Concordo'));
    await tester.tap(find.text('Concordo'));
    await tester.pumpAndSettle();

    expect(
      find.text('Os termos mudaram. Atualize o app para continuar.'),
      findsOneWidget,
    );
    expect(h.location(tester), '/termos');
  });

  testWidgets('Sair da conta signs out from here', (tester) async {
    final h = await outdated(tester);

    await tester.ensureVisible(find.text('Sair da conta'));
    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();

    expect(h.actions, ['DELETE /v1/session']);
    expect(h.location(tester), '/entrar');
    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('accepted terms change nothing', (tester) async {
    final h = Harness(signedIn: true)..family = ownerFamily;
    await h.pump(tester, initial: '/conta');

    expect(h.location(tester), '/conta');
  });

  testWidgets('with the terms accepted, the screen sends home', (tester) async {
    final h = Harness(signedIn: true)..family = ownerFamily;
    await h.pump(tester, initial: '/termos');

    expect(h.location(tester), '/');
    expect(find.byType(TermsUpdateScreen), findsNothing);
  });

  testWidgets('a suspended account keeps to the suspended home, where '
      'signing out waits', (tester) async {
    final h = await outdated(tester, status: 'suspended');

    expect(h.location(tester), '/');
    expect(find.text('Sua conta está suspensa'), findsOneWidget);
    expect(find.byType(TermsUpdateScreen), findsNothing);
    expect(find.text('Sair da conta'), findsOneWidget);
  });

  testWidgets('signed out, the screen is not reached', (tester) async {
    final h = Harness();
    await h.pump(tester, initial: '/termos');

    expect(h.location(tester), '/entrar');
  });
}
