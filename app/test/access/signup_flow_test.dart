import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/check_email_screen.dart';
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/forgot_password_screen.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/legal/legal_links.dart';

import 'harness.dart';

import 'package:telinha_segura/design/address.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

FilledButton submitButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

const longPassword = 'uma senha bem comprida';

Future<void> fillSignup(WidgetTester tester, {bool declare = true}) async {
  await tester.enterText(field('E-\u2060mail'), 'ana@example.com');
  await tester.enterText(field('Senha'), longPassword);
  if (declare) {
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
  }
  await tester.pump();
}

void main() {
  group('signup', () {
    testWidgets('renders email, password with show/hide, guidance and an '
        'unchecked declaration', (tester) async {
      await Harness().pump(tester, initial: '/criar-conta');

      expect(field('E-\u2060mail'), findsOneWidget);
      expect(field('Senha'), findsOneWidget);
      expect(find.byTooltip('Mostrar senha'), findsOneWidget);
      expect(find.text(Copy.passwordGuidance), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(find.text('Passo 1 de 2'), findsOneWidget);
    });

    testWidgets('under the declaration, the agreement names the terms and '
        'the privacy policy, each opening its page', (tester) async {
      final h = Harness();
      await h.pump(tester, initial: '/criar-conta');

      expect(find.text(signupAgreement), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(signupAgreement)).dy,
        greaterThan(tester.getBottomLeft(find.byType(DeclarationRow)).dy),
      );
      await tester.ensureVisible(find.text('Termos de uso'));
      await tester.tap(find.text('Termos de uso'));
      await tester.ensureVisible(find.text('Política de privacidade'));
      await tester.tap(find.text('Política de privacidade'));
      await tester.pump();

      expect(h.links.opened, [kTermsUrl, kPrivacyUrl]);
      expect(h.actions, isEmpty);
    });

    testWidgets('submit stays disabled until the declaration is checked', (
      tester,
    ) async {
      await Harness().pump(tester, initial: '/criar-conta');
      await fillSignup(tester, declare: false);

      expect(submitButton(tester, 'Criar conta').onPressed, isNull);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(submitButton(tester, 'Criar conta').onPressed, isNotNull);
    });

    testWidgets('a disabled submit says why', (tester) async {
      await Harness().pump(tester, initial: '/criar-conta');

      expect(find.text(declarationHint), findsOneWidget);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text(declarationHint), findsNothing);
    });

    testWidgets('a short password shows the guidance unmet and calls nothing', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester, initial: '/criar-conta');
      await fillSignup(tester);
      await tester.enterText(field('Senha'), 'curta');
      await tester.pump();

      final guidance = tester.widget<Guidance>(find.byType(Guidance));
      expect(guidance.met, isFalse);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Criar conta'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();
      expect(h.actions, isEmpty);
      expect(find.text(Copy.forError(_weak('too_short'))), findsOneWidget);
    });

    testWidgets('a breached password is explained on the field', (
      tester,
    ) async {
      final h = Harness(
        api: (_) => problem(422, 'weak_password', reasons: ['breached']),
      );
      await h.pump(tester, initial: '/criar-conta');
      await fillSignup(tester);

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Criar conta'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      final input = tester.widget<TextField>(field('Senha'));
      expect(input.decoration!.errorText, contains('vazamento'));
    });

    testWidgets('success goes to check-your-email with the address, claiming '
        'no account', (tester) async {
      final h = Harness(api: (_) => http.Response('', 202));
      await h.pump(tester, initial: '/criar-conta');
      await fillSignup(tester);

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Criar conta'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(h.actions.single, startsWith('POST /v1/accounts '));
      expect(h.actions.single, contains('"adult_declaration":true'));
      expect(h.actions.single, contains('"terms_version":"$kTermsVersion"'));
      expect(find.byType(CheckEmailScreen), findsOneWidget);
      expect(
        find.textContaining(addressBreaks('ana@example.com')),
        findsOneWidget,
      );
      expect(find.textContaining('conta criada'), findsNothing);
      expect(find.textContaining('Conta criada'), findsNothing);
    });
  });

  group('check your email', () {
    testWidgets('resend calls the API and confirms generically', (
      tester,
    ) async {
      final h = Harness(api: (_) => http.Response('', 202));
      await h.pump(tester, initial: '/criar-conta');
      await fillSignup(tester);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Criar conta'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reenviar e-\u2060mail'));
      await tester.pumpAndSettle();

      expect(
        h.actions.last,
        'POST /v1/email-verifications '
        '{"email":"ana@example.com"}',
      );
      expect(find.textContaining('Se houver'), findsOneWidget);
    });

    testWidgets('resend under a rate limit counts down', (tester) async {
      final h = Harness(api: (_) => http.Response('', 202));
      await h.pump(tester, initial: '/criar-conta');
      await fillSignup(tester);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Criar conta'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();
      h.api = (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'});

      await tester.tap(find.text('Reenviar e-\u2060mail'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('30 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    });
  });

  group('verify email', () {
    testWidgets('confirms the token once and offers to continue', (
      tester,
    ) async {
      final h = Harness(api: (_) => http.Response('', 204));
      await h.pump(tester, initial: '/verificar-email?token=tok-1');
      await tester.pumpAndSettle();

      expect(h.actions, [
        'POST /v1/email-verifications/confirm {"token":"tok-1"}',
      ]);
      expect(find.text('E-\u2060mail confirmado'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
    });

    testWidgets('an expired confirm link offers a fresh email', (tester) async {
      final h = Harness(api: (_) => problem(400, 'invalid_token'));
      await h.pump(tester, initial: '/verificar-email?token=old');

      expect(find.textContaining('expirou'), findsOneWidget);
      expect(find.text('Reenviar e-\u2060mail'), findsOneWidget);
    });

    testWidgets('a missing token is treated as an expired link', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester, initial: '/verificar-email');

      expect(h.actions, isEmpty);
      expect(find.textContaining('expirou'), findsOneWidget);
    });

    testWidgets('an expired reset link leads to a new one', (tester) async {
      final h = Harness(api: (_) => problem(400, 'invalid_token'));
      await h.pump(tester, initial: '/redefinir-senha');

      expect(find.textContaining('expirou'), findsOneWidget);
      await tester.tap(find.text('Pedir um novo link'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });
  });
}

ApiError _weak(String reason) =>
    ApiError(status: 422, code: 'weak_password', reasons: [reason]);
