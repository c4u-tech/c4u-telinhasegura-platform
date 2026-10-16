import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/auth/api_error.dart';

import 'harness.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

TextField textField(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label));

FilledButton submit(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(field('E-\u2060mail'), 'ana@example.com');
  await tester.enterText(field('Senha'), 'uma senha bem comprida');
}

void main() {
  testWidgets('valid input signs in and lands home', (tester) async {
    final h = Harness(
      api: (req) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return json(200, {'csrf_token': 'c2'});
      },
    );
    await h.pump(tester, initial: '/entrar/email');
    await fill(tester);
    h.signedIn = true;

    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(submit(tester).onPressed, isNull, reason: 'busy while it runs');
    await tester.pumpAndSettle();

    expect(h.actions.single, startsWith('POST /v1/sessions '));
    expect(h.actions.single, contains('"email":"ana@example.com"'));
    // This device's label, the harness's own.
    expect(h.actions.single, contains('"device_label":"$testDeviceLabel"'));
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  testWidgets('invalid_credentials keeps the email and clears the password', (
    tester,
  ) async {
    final h = Harness(api: (_) => problem(401, 'invalid_credentials'));
    await h.pump(tester, initial: '/entrar/email');
    await fill(tester);

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text(Copy.forError(_err('invalid_credentials'))), findsOne);
    expect(
      textField(tester, 'E-\u2060mail').controller!.text,
      'ana@example.com',
    );
    expect(textField(tester, 'Senha').controller!.text, isEmpty);
  });

  testWidgets('rate_limited counts down and re-enables at zero', (
    tester,
  ) async {
    final h = Harness(
      api: (_) => problem(429, 'rate_limited', headers: {'retry-after': '3'}),
    );
    await h.pump(tester, initial: '/entrar/email');
    await fill(tester);

    await tester.tap(find.text('Entrar'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('3 s'), findsOneWidget);
    expect(submit(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('2 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining(' s.'), findsNothing);
    expect(submit(tester).onPressed, isNotNull);
  });

  testWidgets('a network failure keeps every value and offers a retry', (
    tester,
  ) async {
    final h = Harness(api: (_) => throw http.ClientException('down'));
    await h.pump(tester, initial: '/entrar/email');
    await fill(tester);

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text(Copy.genericRetry), findsOneWidget);
    expect(
      textField(tester, 'E-\u2060mail').controller!.text,
      'ana@example.com',
    );
    expect(
      textField(tester, 'Senha').controller!.text,
      'uma senha bem comprida',
    );
    expect(find.textContaining('500'), findsNothing);
  });

  testWidgets('fields carry the email keyboard and autofill hints', (
    tester,
  ) async {
    await Harness().pump(tester, initial: '/entrar/email');

    final email = textField(tester, 'E-\u2060mail');
    expect(email.keyboardType, TextInputType.emailAddress);
    expect(email.autofillHints, [AutofillHints.email]);
    expect(textField(tester, 'Senha').autofillHints, [AutofillHints.password]);
  });

  testWidgets('the screen links to password recovery', (tester) async {
    await Harness().pump(tester, initial: '/entrar/email');

    expect(find.text('Esqueci a senha'), findsOneWidget);
  });
}

ApiError _err(String code) => ApiError(status: 400, code: code);
