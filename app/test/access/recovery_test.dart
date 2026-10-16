import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/forgot_password_screen.dart';

import 'harness.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets('a reset request confirms generically, never naming the '
      'account', (tester) async {
    final h = Harness(api: (_) => http.Response('', 202));
    await h.pump(tester, initial: '/esqueci-a-senha');

    await tester.enterText(field('E-\u2060mail'), 'ana@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar link'));
    await tester.pumpAndSettle();

    expect(
      h.actions.single,
      'POST /v1/password-resets '
      '{"email":"ana@example.com"}',
    );
    expect(find.text(resetLinkSent), findsOneWidget);
    expect(resetLinkSent, startsWith('Se houver uma conta com esse e-'));
  });

  testWidgets('a new password resets, says devices were signed out and leads '
      'to /entrar', (tester) async {
    final h = Harness(api: (_) => http.Response('', 204));
    await h.pump(tester, initial: '/redefinir-senha?token=t-9');

    await tester.enterText(field('Nova senha'), 'uma senha bem comprida');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar nova senha'));
    await tester.pumpAndSettle();

    expect(
      h.actions.single,
      'POST /v1/password-resets/confirm '
      '{"token":"t-9","new_password":"uma senha bem comprida"}',
    );
    expect(find.textContaining('todos os aparelhos'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('a short new password is refused before any request', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester, initial: '/redefinir-senha?token=t-9');

    await tester.enterText(field('Nova senha'), 'curta');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar nova senha'));
    await tester.pumpAndSettle();

    expect(h.actions, isEmpty);
  });

  testWidgets('weak_password shows its reason on the field', (tester) async {
    final h = Harness(
      api: (_) => problem(422, 'weak_password', reasons: ['breached']),
    );
    await h.pump(tester, initial: '/redefinir-senha?token=t-9');

    await tester.enterText(field('Nova senha'), 'uma senha bem comprida');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar nova senha'));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(field('Nova senha'));
    expect(input.decoration!.errorText, contains('vazamento'));
    expect(input.autofillHints, [AutofillHints.newPassword]);
  });
}
