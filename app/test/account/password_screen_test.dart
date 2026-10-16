import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/forgot_password_screen.dart';
import 'package:telinha_segura/access/new_password.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/account/password_screen.dart';
import 'package:telinha_segura/auth/api_error.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

const before = 'a senha de antes, longa';
const after = 'uma senha nova bem longa';
const changeRequest =
    'POST /v1/account/password '
    '{"current_password":"$before","new_password":"$after"}';
const resetRequest = 'POST /v1/password-resets {"email":"ana@example.com"}';

/// `/conta/senha` for Ana, whose calls answer [answer] (204 by default).
Future<Harness> passwordScreen(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? answer,
  Map<String, Object?>? family = ownerFamily,
  bool unverified = false,
}) async {
  final h =
      Harness(
          signedIn: true,
          api: (req) => switch (req.url.path) {
            '/v1/sessions' => json(200, {'sessions': <Object>[]}),
            _ => answer?.call(req) ?? http.Response('', 204),
          },
        )
        ..family = family
        ..unverified = unverified;
  await h.pump(tester, initial: '/conta/senha');
  return h;
}

Finder get current => find.widgetWithText(TextField, 'Senha atual');
Finder get next => find.widgetWithText(TextField, 'Nova senha');
Finder get change => find.widgetWithText(FilledButton, 'Trocar senha');
Finder get create => find.widgetWithText(TextButton, 'Criar uma senha');

String textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

Future<void> submit(
  WidgetTester tester, {
  String now = before,
  String then = after,
}) async {
  await tester.enterText(current, now);
  await tester.enterText(next, then);
  await tester.ensureVisible(change);
  await tester.tap(change);
  await tester.pumpAndSettle();
}

void expectBothCleared(WidgetTester tester) {
  expect(textOf(tester, current), isEmpty);
  expect(textOf(tester, next), isEmpty);
}

/// The error under [field], as its decoration shows it.
String? errorOn(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).decoration!.errorText;

void main() {
  group('Trocar a senha', () {
    testWidgets('shows the current and new password, the length guidance '
        'and Trocar senha', (tester) async {
      await passwordScreen(tester);

      expect(find.byType(PasswordScreen), findsOneWidget);
      expect(current, findsOneWidget);
      expect(find.byType(NewPasswordField), findsOneWidget);
      expect(find.text(Copy.passwordGuidance), findsOneWidget);
      expect(change, findsOneWidget);
    });

    testWidgets('works without a family and with the email unverified', (
      tester,
    ) async {
      await passwordScreen(tester, family: null, unverified: true);

      expect(change, findsOneWidget);
    });

    testWidgets('submitting changes the password, says what followed, and '
        'clears both fields', (tester) async {
      final h = await passwordScreen(tester);

      await submit(tester);

      expect(h.actions, [changeRequest]);
      expect(find.text(passwordChanged), findsOneWidget);
      expect(passwordChanged, contains('outros aparelhos'));
      expect(passwordChanged, contains('e-⁠mail'));
    });

    testWidgets('a change done replaces the form with its notice and a way '
        'back, so no password stays on screen', (tester) async {
      await passwordScreen(tester);

      await submit(tester);

      expect(find.text(passwordChanged), findsOneWidget);
      expect(current, findsNothing);
      expect(next, findsNothing);
      expect(change, findsNothing);
      expect(create, findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Voltar para sua conta'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
    });

    testWidgets('a change done ends the autofill context while the fields '
        'are still there, so a password manager can save', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );
      await passwordScreen(tester);

      await submit(tester);

      expect(calls, contains('TextInput.finishAutofillContext'));
    });

    testWidgets('a short new password is refused before any request, on '
        'its field', (tester) async {
      final h = await passwordScreen(tester);

      await submit(tester, then: 'curta');

      expect(h.actions, isEmpty);
      expect(errorOn(tester, next), tooShortMessage);
    });

    testWidgets('a wrong current password shows on its field and clears '
        'both', (tester) async {
      await passwordScreen(
        tester,
        answer: (_) => problem(401, 'invalid_credentials'),
      );

      await submit(tester);

      expect(errorOn(tester, current), Copy.currentPasswordWrong);
      expect(find.byType(ErrorNote), findsNothing);
      expectBothCleared(tester);
    });

    for (final reason in ['breached', 'too_short', 'too_long']) {
      testWidgets('weak_password ($reason) shows on the new password and '
          'clears both', (tester) async {
        await passwordScreen(
          tester,
          answer: (_) => problem(422, 'weak_password', reasons: [reason]),
        );

        await submit(tester);

        expect(
          errorOn(tester, next),
          Copy.forError(
            ApiError(status: 422, code: 'weak_password', reasons: [reason]),
          ),
        );
        expectBothCleared(tester);
      });
    }

    testWidgets('typing again clears the field\'s error', (tester) async {
      await passwordScreen(
        tester,
        answer: (_) => problem(401, 'invalid_credentials'),
      );
      await submit(tester);

      await tester.enterText(current, 'x');
      await tester.pump();

      expect(errorOn(tester, current), isNull);
    });

    testWidgets('rate_limited shows its countdown, waits, and clears both', (
      tester,
    ) async {
      await passwordScreen(
        tester,
        answer: (_) =>
            problem(429, 'rate_limited', headers: {'retry-after': '30'}),
      );

      await submit(tester);

      expect(
        find.text(Copy.retryIn(const Duration(seconds: 30))),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(change).onPressed, isNull);
      expectBothCleared(tester);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a network failure or 5xx keeps no password', (tester) async {
      await passwordScreen(tester, answer: (_) => problem(503, 'unavailable'));

      await submit(tester);

      expect(find.text(Copy.genericRetry), findsOneWidget);
      expectBothCleared(tester);
    });

    testWidgets('the button waits, with progress, while the call runs', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      await passwordScreen(tester, answer: (_) => answer.future);

      await tester.enterText(current, before);
      await tester.enterText(next, after);
      await tester.tap(change);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Trocar senha'), findsOneWidget);
      answer.complete(http.Response('', 204));
      await tester.pumpAndSettle();
    });

    testWidgets('reauth_required confirms it is you, then retries once with '
        'the same passwords', (tester) async {
      var confirmed = false;
      final h = await passwordScreen(
        tester,
        answer: (req) {
          if (req.url.path == '/v1/session/reauth') {
            confirmed = true;
            return http.Response('', 204);
          }
          return confirmed
              ? http.Response('', 204)
              : problem(403, 'reauth_required');
        },
      );

      await submit(tester);
      expect(find.byType(ReauthPrompt), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'uma senha longa');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(h.actions.map((a) => a.split(' {').first), [
        'POST /v1/account/password',
        'POST /v1/session/reauth',
        'POST /v1/account/password',
      ]);
      expect(h.actions.last, changeRequest);
      expect(find.text(passwordChanged), findsOneWidget);
    });

    testWidgets('unauthenticated lands on the entry screen, signed out', (
      tester,
    ) async {
      await passwordScreen(
        tester,
        answer: (_) => problem(401, 'unauthenticated'),
      );

      await submit(tester);

      expect(find.byType(EntryScreen), findsOneWidget);
    });
  });

  group('Criar uma senha', () {
    testWidgets('is a quiet secondary, below the change, with its lead-in', (
      tester,
    ) async {
      await passwordScreen(tester);

      expect(find.text(createLeadIn), findsOneWidget);
      expect(
        createLeadIn,
        'Entrou com Google ou Apple? Receba um link para criar uma senha.',
      );
      expect(create, findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Criar uma senha'),
        findsNothing,
      );
      expect(
        tester.getTopLeft(create).dy,
        greaterThan(tester.getBottomLeft(change).dy),
      );
    });

    testWidgets('sends the reset link to the account\'s email and shows the '
        'recovery\'s check-your-email state', (tester) async {
      final h = await passwordScreen(
        tester,
        answer: (_) => http.Response('', 202),
      );

      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(h.actions, [resetRequest]);
      expect(find.text(resetLinkSent), findsOneWidget);
      expect(change, findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Voltar para sua conta'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
    });

    testWidgets('a failure keeps the screen and says so', (tester) async {
      await passwordScreen(tester, answer: (_) => problem(503, 'unavailable'));

      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(create, findsOneWidget);
      expect(find.text(resetLinkSent), findsNothing);
    });
  });

  testWidgets('the band\'s back control returns to the account', (
    tester,
  ) async {
    await passwordScreen(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });
}
