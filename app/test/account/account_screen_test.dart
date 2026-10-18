import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/check_email_screen.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/legal/legal_links.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

/// A session as `GET /v1/sessions` lists it.
Map<String, Object?> sessionJson(
  String id, {
  bool current = false,
  String client = 'web',
  String label = 'Navegador',
  DateTime? lastSeen,
}) {
  final seen = (lastSeen ?? DateTime.utc(2026, 10, 4, 12)).toIso8601String();
  return {
    'id': id,
    'client': client,
    'device_label': label,
    'created_at': '2026-10-01T12:00:00Z',
    'last_seen_at': seen,
    'current': current,
  };
}

/// [n] sessions, the first this device's.
http.Response sessionsAnswer(int n) => json(200, {
  'sessions': [for (var i = 0; i < n; i++) sessionJson('s$i', current: i == 0)],
});

/// `/conta` for Ana, whose sessions read answers [sessions] (three by
/// default) and whose other calls answer [api] (204 by default).
Future<Harness> accountScreen(
  WidgetTester tester, {
  Map<String, Object?>? family = ownerFamily,
  bool unverified = false,
  FutureOr<http.Response> Function()? sessions,
  FutureOr<http.Response> Function(http.Request)? api,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.method == 'GET' && req.url.path == '/v1/sessions') {
              return (sessions ?? () => sessionsAnswer(3))();
            }
            return api?.call(req) ?? http.Response('', 204);
          },
        )
        ..family = family
        ..unverified = unverified;
  await h.pump(tester, initial: '/conta', size: size, textScale: textScale);
  return h;
}

/// Where the router went, even to a route a later slice registers: an
/// unmatched location renders go_router's error page, without a Scaffold.
String attempted(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first))
        .routerDelegate
        .currentConfiguration
        .uri
        .toString();

Finder door(String title) => find.widgetWithText(DoorRow, title);

Finder lineOf(String title, String line) =>
    find.descendant(of: door(title), matching: find.text(line));

void main() {
  testWidgets('shows the doors with their lines, in order', (tester) async {
    final semantics = tester.ensureSemantics();
    await accountScreen(tester);

    expect(find.text('Sua conta'), findsOneWidget);
    expect(
      tester.widgetList<DoorRow>(find.byType(DoorRow)).map((d) => d.title),
      [
        'E-⁠mail',
        'Senha',
        'Aparelhos conectados',
        'Seus dados',
        'Termos de uso',
        'Política de privacidade',
      ],
    );
    expect(lineOf('E-⁠mail', addressBreaks('ana@example.com')), findsOne);
    expect(lineOf('Senha', 'Trocar ou criar uma senha'), findsOne);
    expect(lineOf('Aparelhos conectados', '3 aparelhos'), findsOne);
    expect(lineOf('Seus dados', 'Baixar uma cópia'), findsOne);
    for (final label in [
      'E-⁠mail, ana@example.com',
      'Senha, Trocar ou criar uma senha',
      'Aparelhos conectados, 3 aparelhos',
      'Seus dados, Baixar uma cópia',
    ]) {
      expect(find.bySemanticsLabel(label), findsOne, reason: label);
    }
    semantics.dispose();
  });

  testWidgets('one session reads "1 aparelho"', (tester) async {
    await accountScreen(tester, sessions: () => sessionsAnswer(1));

    expect(lineOf('Aparelhos conectados', '1 aparelho'), findsOne);
  });

  testWidgets('the doors do not wait for the sessions read, which shows a '
      'calm line meanwhile', (tester) async {
    final answer = Completer<http.Response>();
    await accountScreen(tester, sessions: () => answer.future);

    expect(door('E-⁠mail'), findsOne);
    expect(lineOf('Aparelhos conectados', sessionsUnknown), findsOne);

    answer.complete(sessionsAnswer(2));
    await tester.pumpAndSettle();
    expect(lineOf('Aparelhos conectados', '2 aparelhos'), findsOne);
  });

  testWidgets('a failed sessions read keeps the calm line and the door', (
    tester,
  ) async {
    await accountScreen(tester, sessions: () => problem(503, 'unavailable'));

    expect(lineOf('Aparelhos conectados', sessionsUnknown), findsOne);
    expect(find.byType(ErrorNote), findsNothing);
    await tester.tap(door('Aparelhos conectados'));
    await tester.pumpAndSettle();
    expect(attempted(tester), '/conta/aparelhos');
  });

  for (final (title, path, registered) in [
    ('E-⁠mail', '/conta/email', true),
    ('Senha', '/conta/senha', true),
    ('Aparelhos conectados', '/conta/aparelhos', true),
    ('Seus dados', '/conta/dados', true),
  ]) {
    testWidgets('$title opens $path', (tester) async {
      final h = await accountScreen(tester);

      await tester.tap(door(title));
      await tester.pumpAndSettle();

      expect(registered ? h.location(tester) : attempted(tester), path);
    });
  }

  testWidgets('the terms of use and the privacy policy open the site', (
    tester,
  ) async {
    final h = await accountScreen(tester);

    for (final title in ['Termos de uso', 'Política de privacidade']) {
      await tester.ensureVisible(door(title));
      await tester.tap(door(title));
      await tester.pumpAndSettle();
    }

    expect(h.links.opened, [kTermsUrl, kPrivacyUrl]);
    expect(h.location(tester), '/conta');
  });

  testWidgets('the site rows read as links', (tester) async {
    final semantics = tester.ensureSemantics();
    await accountScreen(tester);

    for (final title in ['Termos de uso', 'Política de privacidade']) {
      expect(
        find.semantics.byPredicate(
          (n) => n.label == title && n.flagsCollection.isLink,
        ),
        findsOne,
        reason: title,
      );
    }
    semantics.dispose();
  });

  testWidgets('the foot holds a quiet clay Excluir conta that opens '
      '/conta/excluir', (tester) async {
    final h = await accountScreen(tester);

    final action = tester.widget<QuietAction>(
      find.widgetWithText(QuietAction, 'Excluir conta'),
    );
    expect(action.destructive, isTrue);
    expect(find.widgetWithText(FilledButton, 'Excluir conta'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Excluir conta')).dy,
      greaterThan(tester.getBottomLeft(door('Seus dados')).dy),
    );
    await tester.ensureVisible(find.text('Excluir conta'));
    await tester.tap(find.text('Excluir conta'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/conta/excluir');
  });

  testWidgets('the count is read again on returning from the devices', (
    tester,
  ) async {
    var count = 3;
    final h = Harness(
      signedIn: true,
      api: (req) {
        if (req.method == 'GET' && req.url.path == '/v1/sessions') {
          return sessionsAnswer(count);
        }
        if (req.method == 'DELETE') count = 1;
        return http.Response('', 204);
      },
    )..family = ownerFamily;
    await h.pump(tester, initial: '/conta');
    expect(lineOf('Aparelhos conectados', '3 aparelhos'), findsOne);

    await tester.tap(door('Aparelhos conectados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair dos outros aparelhos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/conta');
    expect(lineOf('Aparelhos conectados', '1 aparelho'), findsOne);
  });

  testWidgets('the band\'s back control returns home', (tester) async {
    await accountScreen(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  testWidgets('without a family, the index is the same', (tester) async {
    await accountScreen(tester, family: null);

    expect(find.byType(DoorRow), findsNWidgets(6));
    expect(find.text('Excluir conta'), findsOneWidget);
  });

  group('email unverified', () {
    testWidgets('shows the verify line above the doors, which still open', (
      tester,
    ) async {
      final h = await accountScreen(tester, family: null, unverified: true);

      expect(find.textContaining('confirme seu e-⁠mail'), findsOne);
      expect(find.text(addressBreaks('ana@example.com')), findsWidgets);
      expect(
        tester.getBottomLeft(find.text('Reenviar e-⁠mail')).dy,
        lessThan(tester.getTopLeft(door('E-⁠mail')).dy),
      );
      expect(find.byType(DoorRow), findsNWidgets(6));
      await tester.tap(door('Senha'));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/conta/senha');
    });

    testWidgets('Reenviar e-mail resends to the account\'s address', (
      tester,
    ) async {
      final h = await accountScreen(
        tester,
        family: null,
        unverified: true,
        api: (_) => http.Response('', 202),
      );

      await tester.tap(find.text('Reenviar e-⁠mail'));
      await tester.pumpAndSettle();

      // The sessions read is filtered with the session reads.
      expect(h.actions, [
        'POST /v1/email-verifications {"email":"ana@example.com"}',
      ]);
      expect(find.text(resentNotice), findsOneWidget);
    });

    testWidgets('a confirmed email shows no verify line', (tester) async {
      await accountScreen(tester);

      expect(find.text('Reenviar e-⁠mail'), findsNothing);
    });
  });
}
