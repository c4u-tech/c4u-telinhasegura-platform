import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/enrollment_screen.dart';
import 'package:telinha_segura/account/mfa_widgets.dart';
import 'package:telinha_segura/account/mfa_words.dart';
import 'package:telinha_segura/account/recovery_codes_view.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid_mode/link_qr.dart' show LinkQrPainter;

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'mfa_fixtures.dart';
import 'verification_screen_test.dart'
    show location, mfaCalls, tapText, watchClipboard;

const keyTitle = 'Conecte o app autenticador';
const codeTitle = 'Digite o código que o app mostra';
const codesTitle = 'Guarde seus códigos de recuperação';

const narrow = Size(390, 844);
const wide = Size(1280, 800);

/// The enrollment for Ana, an admin, against [api].
Future<Harness> enrollment(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? api,
  String initial = '/conta/verificacao/ativar',
  Size size = narrow,
}) async {
  final h = Harness(signedIn: true, api: api ?? mfaApi())
    ..family = ownerFamily
    ..roles = ['admin'];
  await h.pump(tester, initial: initial, size: size);
  return h;
}

/// The QR's painter, which holds what the QR encodes.
LinkQrPainter qrPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(KeyQr),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as LinkQrPainter;

Future<void> typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.pumpAndSettle();
}

/// From the key step, through the code, to the recovery codes.
Future<void> toCodes(WidgetTester tester) async {
  await tapText(tester, 'Já adicionei');
  await typeCode(tester, '123456');
  await tapText(tester, 'Confirmar');
}

Future<void> keepAndContinue(WidgetTester tester) async {
  await tapText(tester, codesKept);
  await tapText(tester, 'Continuar');
}

void main() {
  testWidgets('opening starts the enrollment and shows the key step', (
    tester,
  ) async {
    final h = await enrollment(tester);

    expect(mfaCalls(h), contains('POST /v1/staff/mfa/enrollment'));
    expect(find.text(keyTitle), findsOneWidget);
    expect(location(tester), '/conta/verificacao/ativar');
  });

  testWidgets('without a platform role, it returns to /conta and asks for '
      'no key', (tester) async {
    final h = Harness(signedIn: true, api: mfaApi())..family = ownerFamily;
    await h.pump(tester, initial: '/conta/verificacao/ativar');

    expect(h.location(tester), '/conta');
    expect(mfaCalls(h), isEmpty);
  });

  testWidgets('shows the loading placeholder while the key is asked for', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await enrollment(tester, api: mfaApi(start: () => answer.future));

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    answer.complete(json(201, enrollmentJson()));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyPlaceholder), findsNothing);
  });

  testWidgets('reauth_required asks to confirm it is you, then starts again', (
    tester,
  ) async {
    var calls = 0;
    await enrollment(
      tester,
      api: mfaApi(
        start: () => calls++ == 0
            ? problem(403, 'reauth_required')
            : json(201, enrollmentJson()),
      ),
    );

    expect(find.text('Confirme que é você'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'senha-certa');
    await tapText(tester, 'Confirmar');

    expect(calls, 2);
    expect(find.text(keyTitle), findsOneWidget);
  });

  testWidgets('a cancelled confirmation returns to the status', (tester) async {
    await enrollment(
      tester,
      api: mfaApi(start: () => problem(403, 'reauth_required')),
    );

    await tapText(tester, 'Cancelar');

    expect(location(tester), '/conta/verificacao');
  });

  testWidgets('mfa_already_enrolled shows /conta/verificacao', (tester) async {
    await enrollment(
      tester,
      api: mfaApi(start: () => problem(409, 'mfa_already_enrolled')),
    );

    expect(location(tester), '/conta/verificacao');
    expect(find.text('Ativada desde 7 de outubro'), findsOneWidget);
  });

  testWidgets('a failed start offers "Tentar de novo"', (tester) async {
    var fail = true;
    await enrollment(
      tester,
      api: mfaApi(
        start: () =>
            fail ? problem(500, 'internal') : json(201, enrollmentJson()),
      ),
    );
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);

    fail = false;
    await tapText(tester, 'Tentar de novo');

    expect(find.text(keyTitle), findsOneWidget);
  });

  testWidgets('mfa_unavailable says so', (tester) async {
    await enrollment(
      tester,
      api: mfaApi(start: () => problem(503, 'mfa_unavailable')),
    );

    expect(find.widgetWithText(ErrorNote, mfaUnavailable), findsOneWidget);
  });

  group('the key step', () {
    testWidgets('shows the secret in groups of four, selectable, read group '
        'by group', (tester) async {
      final semantics = tester.ensureSemantics();
      await enrollment(tester);

      final grouped = keyGroups(testSecret).join(' ');
      expect(grouped, startsWith('JBSW Y3DP EHPK'));
      expect(find.text(grouped), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(grouped),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Chave: J B S W, Y 3 D P, ')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('"Copiar chave" copies the key', (tester) async {
      final copied = watchClipboard(tester);
      await enrollment(tester);

      await tapText(tester, 'Copiar chave');

      expect(copied, [testSecret]);
      expect(find.text('Chave copiada'), findsOneWidget);
    });

    testWidgets('narrow: "Abrir no app autenticador" first, opening the '
        'otpauth link as sent; the QR behind "Mostrar QR code"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await enrollment(tester);

      final open = find.widgetWithText(
        FilledButton,
        'Abrir no app autenticador',
      );
      expect(open, findsOneWidget);
      expect(find.byType(KeyQr), findsNothing);
      expect(
        tester.getTopLeft(open).dy,
        lessThan(
          tester.getTopLeft(find.text(keyGroups(testSecret).join(' '))).dy,
        ),
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Já adicionei'),
        findsOneWidget,
      );

      await tapText(tester, 'Abrir no app autenticador');
      expect(h.links.opened, [Uri.parse(testUri)]);
      expect(h.links.opened.single.toString(), testUri);

      await tapText(tester, 'Mostrar QR code');
      expect(find.byType(KeyQr), findsOneWidget);
      expect(qrPainter(tester).data, testUri);
      expect(find.bySemanticsLabel(keyQrLabel), findsOneWidget);
      expect(tester.getSize(find.byType(KeyQr)).width, greaterThan(200));
      // The key block's outline, so the two read as one family.
      final outlined = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(KeyQr),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        outlined.map((d) => (d.decoration as BoxDecoration).border?.top.width),
        contains(1.5),
      );
      expect(find.text('Mostrar QR code'), findsNothing);
      semantics.dispose();
    });

    testWidgets('narrow: a link that does not open says so and keeps the key '
        'and the QR', (tester) async {
      final h = Harness(signedIn: true, api: mfaApi())
        ..family = ownerFamily
        ..roles = ['admin']
        ..links.opens = false;
      await h.pump(tester, initial: '/conta/verificacao/ativar');

      await tapText(tester, 'Abrir no app autenticador');

      expect(find.widgetWithText(ErrorNote, appNotOpened), findsOneWidget);
      expect(find.text(keyGroups(testSecret).join(' ')), findsOneWidget);
      expect(find.text('Mostrar QR code'), findsOneWidget);
    });

    testWidgets('wide: the QR first, the key below it, "Já adicionei" the '
        'primary', (tester) async {
      await enrollment(tester, size: wide);

      expect(find.text('Abrir no app autenticador'), findsNothing);
      expect(find.byType(KeyQr), findsOneWidget);
      expect(qrPainter(tester).data, testUri);
      expect(
        tester.getBottomLeft(find.byType(KeyQr)).dy,
        lessThan(
          tester.getTopLeft(find.text(keyGroups(testSecret).join(' '))).dy,
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Já adicionei'), findsOneWidget);
    });

    testWidgets('"Já adicionei" leads to the code step; back steps back', (
      tester,
    ) async {
      await enrollment(tester);

      await tapText(tester, 'Já adicionei');
      expect(find.text(codeTitle), findsOneWidget);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text(keyTitle), findsOneWidget);
      expect(location(tester), '/conta/verificacao/ativar');
    });

    testWidgets('back on the key step returns to the status', (tester) async {
      await enrollment(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(location(tester), '/conta/verificacao');
    });

    testWidgets('the secret is never in the route', (tester) async {
      await enrollment(tester);
      await tapText(tester, 'Já adicionei');

      expect(location(tester), isNot(contains(testSecret)));
    });
  });

  group('the code step', () {
    testWidgets('six digits on a numeric keyboard with the one-time-code '
        'hint; "Confirmar" waits for them', (tester) async {
      await enrollment(tester);
      await tapText(tester, 'Já adicionei');

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, TextInputType.number);
      expect(field.autofillHints, [AutofillHints.oneTimeCode]);
      final confirm = find.widgetWithText(FilledButton, 'Confirmar');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await typeCode(tester, '12a34 5678');
      expect(find.text('123456'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    });

    testWidgets('confirms the code and shows the ten codes', (tester) async {
      final h = await enrollment(tester);

      await toCodes(tester);

      expect(
        mfaCalls(h).last,
        'POST /v1/staff/mfa/enrollment/confirm {"code":"123456"}',
      );
      expect(find.text(codesTitle), findsOneWidget);
      for (final code in testCodes()) {
        expect(find.text(code), findsOneWidget);
      }
      expect(find.text(keyGroups(testSecret).join(' ')), findsNothing);
    });

    testWidgets('mfa_code_invalid shows the refusal on the field and keeps '
        'the step', (tester) async {
      await enrollment(
        tester,
        api: mfaApi(confirm: (_) => problem(422, 'mfa_code_invalid')),
      );

      await toCodes(tester);

      expect(find.text(codeTitle), findsOneWidget);
      expect(find.text(codeInvalid), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.errorText,
        codeInvalid,
      );
      expect(find.byType(ErrorNote), findsNothing);
    });

    testWidgets('mfa_not_pending restarts at the key step with a notice', (
      tester,
    ) async {
      final h = await enrollment(
        tester,
        api: mfaApi(confirm: (_) => problem(409, 'mfa_not_pending')),
      );

      await toCodes(tester);

      expect(find.text(keyTitle), findsOneWidget);
      expect(find.widgetWithText(Notice, keyRestarted), findsOneWidget);
      expect(
        mfaCalls(h).where((c) => c == 'POST /v1/staff/mfa/enrollment').length,
        2,
      );
    });

    String blockedFor(int minutes) =>
        'Muitas tentativas erradas. Tente de novo em $minutes\u00A0min.';
    const sessionsDoor = 'Não foi você? Encerre a sessão nos outros aparelhos.';

    testWidgets('rate_limited blocks as the challenge does: the field and '
        '"Confirmar" disabled, the note in whole minutes, by minute, until '
        'it ends', (tester) async {
      var blocked = true;
      await enrollment(
        tester,
        api: mfaApi(
          confirm: (_) => blocked
              ? problem(429, 'rate_limited', headers: {'retry-after': '90'})
              : json(200, codesJson()),
        ),
      );

      await toCodes(tester);

      expect(find.widgetWithText(ErrorNote, blockedFor(2)), findsOneWidget);
      expect(find.text(sessionsDoor), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      final confirm = find.widgetWithText(FilledButton, 'Confirmar');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.pump(const Duration(seconds: 29));
      expect(find.text(blockedFor(2)), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(blockedFor(1)), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorNote), findsNothing);
      expect(find.text(sessionsDoor), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isTrue);
      // The expired code is gone: a new one, not a wasted attempt.
      expect(field.controller!.text, isEmpty);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      blocked = false;
      await typeCode(tester, '654321');
      await tapText(tester, 'Confirmar');
      expect(find.text(codesTitle), findsOneWidget);
    });

    testWidgets('the block\'s door opens the sessions, and coming back finds '
        'the code step as it was', (tester) async {
      await enrollment(
        tester,
        api: mfaApi(
          confirm: (_) =>
              problem(429, 'rate_limited', headers: {'retry-after': '240'}),
        ),
      );
      await toCodes(tester);

      await tapText(tester, sessionsDoor);
      expect(find.text('Aparelhos conectados'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(find.text('Digite o código que o app mostra'), findsOneWidget);
      expect(find.text(blockedFor(4)), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(field.enabled, isFalse);
    });
  });

  group('the end', () {
    testWidgets('"Continuar" lands on /conta/verificacao with "Verificação '
        'ativada.", and no challenge', (tester) async {
      final h = await enrollment(
        tester,
        api: mfaApi(status: () => json(200, mfaStatusJson(codesLeft: 10))),
      );
      await toCodes(tester);

      await keepAndContinue(tester);

      expect(location(tester), '/conta/verificacao');
      expect(find.widgetWithText(Notice, mfaEnrolled), findsOneWidget);
      expect(find.text('Códigos de recuperação: 10 restantes'), findsOneWidget);
      expect(
        mfaCalls(h),
        isNot(contains(startsWith('POST /v1/staff/mfa/challenge'))),
      );
      expect(h.services.unkeptCodes, isNull);
    });

    testWidgets('opened for a staff screen, it returns there', (tester) async {
      await enrollment(
        tester,
        initial: '/conta/verificacao/ativar?depois=%2Fadmin%2Fequipe',
      );
      await toCodes(tester);

      await keepAndContinue(tester);

      expect(location(tester), '/admin/equipe');
    });

    testWidgets('a return path outside the staff screens is dropped', (
      tester,
    ) async {
      await enrollment(
        tester,
        initial: '/conta/verificacao/ativar?depois=https%3A%2F%2Fevil.example%2Fadmin',
      );
      await toCodes(tester);

      await keepAndContinue(tester);

      expect(location(tester), '/conta/verificacao');
    });

    testWidgets('opened for a staff screen, cancelling returns home', (
      tester,
    ) async {
      await enrollment(
        tester,
        initial: '/conta/verificacao/ativar?depois=%2Fadmin%2Fequipe',
      );

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(location(tester), '/');
    });

    testWidgets('leaving the codes before "Continuar" asks first', (
      tester,
    ) async {
      await enrollment(tester);
      await toCodes(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Sair sem guardar os códigos?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(find.text(codesTitle), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sair sem guardar os códigos?'), findsOneWidget);
      await tapText(tester, 'Sair sem guardar');

      expect(location(tester), '/conta/verificacao');
      expect(find.text(testCodes().first), findsNothing);
    });
  });

  group('enrollFactor, for a staff screen that stays', () {
    Future<Future<bool>> open(WidgetTester tester) async {
      await enrollment(
        tester,
        initial: '/conta',
        api: mfaApi(status: () => json(200, mfaStatusJson(enrolled: false))),
      );
      final result = enrollFactor(tester.element(find.text('Sua conta')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('true once the codes are kept, over the screen that asked', (
      tester,
    ) async {
      final result = await open(tester);
      expect(find.text(keyTitle), findsOneWidget);

      await toCodes(tester);
      await keepAndContinue(tester);

      expect(await result, isTrue);
      expect(location(tester), '/conta');
      expect(find.text('Sua conta'), findsOneWidget);
    });

    testWidgets('false when cancelled', (tester) async {
      final result = await open(tester);

      // The enrollment's own back, over the account's.
      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(location(tester), '/conta');
    });
  });
}
