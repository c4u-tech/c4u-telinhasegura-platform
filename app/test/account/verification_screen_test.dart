import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/mfa_words.dart';
import 'package:telinha_segura/account/recovery_codes_view.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'mfa_fixtures.dart';

const lostDevice =
    'Perdeu o celular com o app? Entre com um código de recuperação. Sem '
    'códigos, a equipe da Telinha Segura redefine a verificação para você.';

/// `/conta/verificacao` for Ana, an admin, against [api].
Future<Harness> verification(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? api,
  List<String> roles = const ['admin'],
  String initial = '/conta/verificacao',
}) async {
  final h = Harness(signedIn: true, api: api ?? mfaApi())
    ..family = ownerFamily
    ..roles = roles;
  await h.pump(tester, initial: initial);
  return h;
}

/// How many times the status was read; `/conta` beneath reads it too.
int statusReads(Harness h) =>
    h.actions.where((c) => c == 'GET /v1/staff/mfa').length;

/// The MFA requests a test cares about.
List<String> mfaCalls(Harness h) =>
    h.actions.where((c) => c.contains('/v1/staff/mfa')).toList();

/// Records what the app put on the clipboard.
List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// From the enrolled status, through the confirmation, to the new codes.
Future<void> regenerate(WidgetTester tester) async {
  await tapText(tester, 'Gerar novos códigos');
  await tapText(tester, 'Gerar novos códigos');
}

String location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first))
        .routerDelegate
        .currentConfiguration
        .uri
        .toString();

void main() {
  testWidgets('not enrolled: what the factor is, and "Ativar" opens the '
      'enrollment', (tester) async {
    await verification(
      tester,
      api: mfaApi(
        status: () => json(200, mfaStatusJson(enrolled: false)),
        start: () => Completer<http.Response>().future,
      ),
    );

    expect(find.text(mfaTitle), findsOneWidget);
    expect(find.textContaining('código de 6 números'), findsOneWidget);
    expect(find.textContaining('a cada 30 minutos'), findsOneWidget);
    expect(find.text('Gerar novos códigos'), findsNothing);
    await tapText(tester, 'Ativar');

    expect(location(tester), '/conta/verificacao/ativar');
  });

  testWidgets('enrolled: since when, the codes left, "Gerar novos códigos" '
      'and the lost-device line; no way to turn it off', (tester) async {
    await verification(tester);

    expect(find.text('Ativada desde 7 de outubro'), findsOneWidget);
    expect(find.text('Códigos de recuperação: 7 restantes'), findsOneWidget);
    expect(find.text('Gere novos códigos antes que acabem'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Gerar novos códigos'),
      findsOneWidget,
    );
    expect(find.text(lostDevice), findsOneWidget);
    expect(find.textContaining('Desativar'), findsNothing);
    expect(find.text('Ativar'), findsNothing);
  });

  for (final (left, line) in [
    (3, 'Códigos de recuperação: 3 restantes'),
    (1, 'Códigos de recuperação: 1 restante'),
    (0, 'Códigos de recuperação: 0 restantes'),
  ]) {
    testWidgets('$left left: "Gere novos códigos antes que acabem"', (
      tester,
    ) async {
      await verification(
        tester,
        api: mfaApi(status: () => json(200, mfaStatusJson(codesLeft: left))),
      );

      expect(find.text(line), findsOneWidget);
      expect(find.text('Gere novos códigos antes que acabem'), findsOneWidget);
    });
  }

  testWidgets('shows the loading placeholder while the status is read', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await verification(tester, api: mfaApi(status: () => answer.future));

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    answer.complete(json(200, mfaStatusJson()));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyPlaceholder), findsNothing);
  });

  testWidgets('mfa_unavailable says so', (tester) async {
    await verification(
      tester,
      api: mfaApi(status: () => problem(503, 'mfa_unavailable')),
    );

    expect(find.widgetWithText(ErrorNote, mfaUnavailable), findsOneWidget);
  });

  testWidgets('a failed read offers "Tentar de novo", which reads again', (
    tester,
  ) async {
    var fail = true;
    final h = await verification(
      tester,
      api: mfaApi(
        status: () =>
            fail ? problem(500, 'internal') : json(200, mfaStatusJson()),
      ),
    );
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    final before = statusReads(h);

    fail = false;
    await tapText(tester, 'Tentar de novo');

    expect(find.text('Ativada desde 7 de outubro'), findsOneWidget);
    expect(statusReads(h), before + 1);
  });

  testWidgets('without a platform role, it returns to /conta (MFA screens, '
      'Routes)', (tester) async {
    final h = await verification(tester, roles: const []);

    expect(h.location(tester), '/conta');
    expect(mfaCalls(h), isEmpty);
  });

  group('Gerar novos códigos', () {
    testWidgets('asks on the full-screen confirmation, naming the codes that '
        'stop working, with the ink primary', (tester) async {
      final h = await verification(tester);

      await tapText(tester, 'Gerar novos códigos');

      expect(find.text('Gerar novos códigos?'), findsOneWidget);
      expect(
        find.text('Os 7 códigos de agora deixam de valer.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Motivo'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Gerar novos códigos'),
        findsOneWidget,
      );
      await tapText(tester, 'Cancelar');
      expect(mfaCalls(h), everyElement('GET /v1/staff/mfa'));
    });

    testWidgets('confirmed, it asks for new codes and shows them', (
      tester,
    ) async {
      final h = await verification(
        tester,
        api: mfaApi(
          regenerate: () =>
              json(200, codesJson(codes: testCodes('QRSTU'), elevated: false)),
        ),
      );

      await regenerate(tester);

      expect(mfaCalls(h).last, 'POST /v1/staff/mfa/recovery-codes');
      expect(find.text('Guarde seus códigos de recuperação'), findsOneWidget);
      for (final code in testCodes('QRSTU')) {
        expect(find.text(code), findsOneWidget);
      }
    });

    testWidgets('reauth_required asks to confirm it is you, then asks again', (
      tester,
    ) async {
      var calls = 0;
      final h = await verification(
        tester,
        api: mfaApi(
          regenerate: () => calls++ == 0
              ? problem(403, 'reauth_required')
              : json(200, codesJson(elevated: false)),
        ),
      );

      await regenerate(tester);
      expect(find.text('Confirme que é você'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'senha-certa');
      await tapText(tester, 'Confirmar');

      expect(h.actions, contains(startsWith('POST /v1/session/reauth')));
      expect(calls, 2);
      expect(find.text('Guarde seus códigos de recuperação'), findsOneWidget);
    });

    testWidgets('elevation_required opens the challenge, then asks again', (
      tester,
    ) async {
      var calls = 0;
      final h = await verification(
        tester,
        api: mfaApi(
          regenerate: () => calls++ == 0
              ? problem(403, 'elevation_required')
              : json(200, codesJson(elevated: false)),
        ),
      );

      await regenerate(tester);
      expect(find.text('Código do app autenticador'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tapText(tester, 'Confirmar');

      expect(mfaCalls(h).where((c) => c.startsWith('POST')).toList(), [
        'POST /v1/staff/mfa/recovery-codes',
        'POST /v1/staff/mfa/challenge {"code":"123456"}',
        'POST /v1/staff/mfa/recovery-codes',
      ]);
      expect(find.text('Guarde seus códigos de recuperação'), findsOneWidget);
    });
  });

  group('the codes screen', () {
    testWidgets('reads the ten codes as a list, in order', (tester) async {
      final semantics = tester.ensureSemantics();
      await verification(tester);
      await regenerate(tester);

      for (final (i, code) in testCodes().indexed) {
        final groups = code.split('-').map((g) => g.split('').join(' '));
        expect(
          find.bySemanticsLabel('Código ${i + 1}: ${groups.join(', ')}'),
          findsOneWidget,
          reason: code,
        );
      }
      semantics.dispose();
    });

    testWidgets('"Copiar códigos" copies all ten, one per line', (
      tester,
    ) async {
      final copied = watchClipboard(tester);
      await verification(tester);
      await regenerate(tester);

      await tapText(tester, 'Copiar códigos');

      expect(copied, [testCodes().join('\n')]);
      expect(find.text(codesCopied), findsOneWidget);
    });

    testWidgets('"Continuar" waits on the checkbox, then shows the status '
        'read again', (tester) async {
      final h = await verification(tester);
      await regenerate(tester);
      final before = statusReads(h);

      final primary = find.widgetWithText(FilledButton, 'Continuar');
      expect(tester.widget<FilledButton>(primary).onPressed, isNull);
      await tapText(tester, codesKept);
      expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
      await tapText(tester, 'Continuar');

      expect(find.text('Guarde seus códigos de recuperação'), findsNothing);
      expect(find.text('Códigos de recuperação: 7 restantes'), findsOneWidget);
      expect(statusReads(h), before + 1);
      expect(h.services.unkeptCodes, isNull);
    });

    testWidgets('the band\'s back asks first; "Cancelar" keeps the codes', (
      tester,
    ) async {
      await verification(tester);
      await regenerate(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(find.text('Sair sem guardar os códigos?'), findsOneWidget);
      expect(
        find.text('Eles não aparecem de novo. A verificação continua ativada.'),
        findsOneWidget,
      );
      await tapText(tester, 'Cancelar');
      expect(find.text('Guarde seus códigos de recuperação'), findsOneWidget);
      expect(find.text(testCodes().first), findsOneWidget);
    });

    testWidgets('confirmed, leaving drops the codes', (tester) async {
      final h = await verification(tester);
      await regenerate(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Sair sem guardar');

      expect(find.text(testCodes().first), findsNothing);
      expect(find.text('Códigos de recuperação: 7 restantes'), findsOneWidget);
      expect(h.services.unkeptCodes, isNull);
    });

    testWidgets('the system back asks first', (tester) async {
      await verification(tester);
      await regenerate(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Sair sem guardar os códigos?'), findsOneWidget);
    });

    testWidgets('any other way off the route (browser back, a link) asks '
        'first, and stays when cancelled', (tester) async {
      await verification(tester);
      await regenerate(tester);

      GoRouter.of(tester.element(find.byType(Navigator).first)).go('/conta');
      await tester.pumpAndSettle();
      expect(find.text('Sair sem guardar os códigos?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(location(tester), '/conta/verificacao');
      expect(find.text(testCodes().first), findsOneWidget);

      GoRouter.of(tester.element(find.byType(Navigator).first)).go('/conta');
      await tester.pumpAndSettle();
      await tapText(tester, 'Sair sem guardar');
      expect(location(tester), '/conta');
    });
  });
}
