import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/account/email_screen.dart';
import 'package:telinha_segura/design/address.dart';

import '../access/harness.dart';
import '../design/pump.dart' show expectAddressBreaks, linesOf;
import '../family/fixtures.dart';

const changeRequest = 'POST /v1/account/email {"new_email":"bia@example.com"}';

/// `/conta/email` for Ana, whose calls answer [answer] (the email change
/// 202 and anything else 204 by default).
Future<Harness> emailScreen(
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
            _ when answer != null => answer(req),
            '/v1/account/email' => http.Response('', 202),
            _ => http.Response('', 204),
          },
        )
        ..family = family
        ..unverified = unverified;
  await h.pump(tester, initial: '/conta/email');
  return h;
}

/// The done state's notice as shown, both addresses set to break.
final sentNotice = emailLinkSent(
  addressBreaks('bia@example.com'),
  addressBreaks('ana@example.com'),
);

Finder get newEmail => find.widgetWithText(TextField, 'Novo e-⁠mail');
Finder get send => find.widgetWithText(FilledButton, 'Enviar link');

Future<void> submit(
  WidgetTester tester, [
  String to = 'bia@example.com',
]) async {
  await tester.enterText(newEmail, to);
  await tester.tap(send);
  await tester.pumpAndSettle();
}

/// The paragraph that shows exactly [address], however it is set.
RenderParagraph addressParagraph(WidgetTester tester, String address) => tester
    .renderObjectList<RenderParagraph>(find.byType(RichText))
    .singleWhere(
      (p) =>
          p.text.toPlainText().replaceAll(RegExp('[\u200B\u2060]'), '') ==
          address,
    );

void main() {
  testWidgets('at 200% text, 360 wide, the current address breaks only '
      'after "@" or before "."', (tester) async {
    final h = Harness(
      signedIn: true,
      api: (req) => switch (req.url.path) {
        '/v1/sessions' => json(200, {'sessions': <Object>[]}),
        _ => http.Response('', 204),
      },
    )..email = 'ana.souza@example.com';
    await h.pump(
      tester,
      initial: '/conta/email',
      size: const Size(360, 640),
      textScale: 2,
    );

    final lines = linesOf(addressParagraph(tester, 'ana.souza@example.com'));
    expect(lines.length, greaterThan(1));
    expectAddressBreaks(lines);
  });

  testWidgets('the done state sets both addresses to break at their safe '
      'points, and reads them plain', (tester) async {
    final semantics = tester.ensureSemantics();
    await emailScreen(tester);
    await submit(tester);

    final plain = emailLinkSent('bia@example.com', 'ana@example.com');
    expect(find.text(sentNotice), findsOneWidget);
    expect(find.bySemanticsLabel(plain), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shows the current address, a new-email field and Enviar '
      'link', (tester) async {
    await emailScreen(tester);

    expect(find.byType(EmailScreen), findsOneWidget);
    expect(find.text(addressBreaks('ana@example.com')), findsOneWidget);
    expect(newEmail, findsOneWidget);
    expect(send, findsOneWidget);
  });

  testWidgets('the helper under the field says what will happen, before '
      'anything was sent', (tester) async {
    await emailScreen(tester);

    expect(find.text(newEmailHelper), findsOneWidget);
    expect(
      newEmailHelper,
      'Vamos enviar um link para o endereço novo. A troca vale quando você '
      'abrir o link.',
    );
  });

  testWidgets('works without a family and with the email unverified', (
    tester,
  ) async {
    await emailScreen(tester, family: null, unverified: true);

    expect(find.byType(EmailScreen), findsOneWidget);
    expect(newEmail, findsOneWidget);
  });

  testWidgets('submitting asks for the change, then names the new address '
      'and keeps the current one until the link', (tester) async {
    final h = await emailScreen(tester);

    await submit(tester, '  bia@example.com ');

    expect(h.actions, [changeRequest]);
    expect(newEmail, findsNothing);
    expect(send, findsNothing);
    expect(find.text(sentNotice), findsOneWidget);
    expect(
      emailLinkSent('bia@example.com', 'ana@example.com'),
      'Enviamos um link para bia@example.com. Seu e-⁠mail continua '
      'ana@example.com até você abrir o link.',
    );
  });

  testWidgets('the answer is the same whether or not the address is in use', (
    tester,
  ) async {
    // The server answers 202 either way; any 2xx reads the same.
    await emailScreen(tester, answer: (_) => http.Response('', 204));

    await submit(tester);

    expect(find.text(sentNotice), findsOneWidget);
  });

  testWidgets('the done state leads back to the account', (tester) async {
    await emailScreen(tester);
    await submit(tester);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Voltar para sua conta'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('the band\'s back control returns to the account', (
    tester,
  ) async {
    await emailScreen(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('reauth_required asks to confirm it is you, then retries once', (
    tester,
  ) async {
    var confirmed = false;
    final h = await emailScreen(
      tester,
      answer: (req) {
        if (req.url.path == '/v1/session/reauth') {
          confirmed = true;
          return http.Response('', 204);
        }
        return confirmed
            ? http.Response('', 202)
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
      'POST /v1/account/email',
      'POST /v1/session/reauth',
      'POST /v1/account/email',
    ]);
    expect(h.actions.last, changeRequest);
    expect(find.text(sentNotice), findsOneWidget);
  });

  testWidgets('a cancelled prompt keeps the screen and its input, quietly', (
    tester,
  ) async {
    final h = await emailScreen(
      tester,
      answer: (_) => problem(403, 'reauth_required'),
    );

    await submit(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(ReauthPrompt), findsNothing);
    expect(h.actions, [changeRequest]);
    expect(find.text('bia@example.com'), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
  });

  testWidgets('validation shows field copy for an invalid or the current '
      'address, keeping the input', (tester) async {
    await emailScreen(tester, answer: (_) => problem(422, 'validation'));

    await submit(tester, 'ana@example.com');

    expect(find.text(Copy.newEmailInvalid), findsOneWidget);
    expect(Copy.newEmailInvalid, contains('válido'));
    expect(Copy.newEmailInvalid, contains('atual'));
    expect(find.byType(ErrorNote), findsNothing);
    expect(
      tester.widget<TextField>(newEmail).controller!.text,
      'ana@example.com',
    );
  });

  testWidgets('an empty address shows the field copy without a request', (
    tester,
  ) async {
    final h = await emailScreen(tester);

    await submit(tester, '   ');

    expect(h.actions, isEmpty);
    expect(find.text(Copy.newEmailInvalid), findsOneWidget);
  });

  testWidgets('a network failure or 5xx keeps the input', (tester) async {
    await emailScreen(tester, answer: (_) => problem(503, 'unavailable'));

    await submit(tester);

    expect(find.text(Copy.genericRetry), findsOneWidget);
    expect(
      tester.widget<TextField>(newEmail).controller!.text,
      'bia@example.com',
    );
  });

  testWidgets('rate_limited shows its countdown and waits', (tester) async {
    await emailScreen(
      tester,
      answer: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'}),
    );

    await submit(tester);

    expect(
      find.text(Copy.retryIn(const Duration(seconds: 30))),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('the button waits, with progress, while the call runs', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await emailScreen(tester, answer: (_) => answer.future);

    await tester.enterText(newEmail, 'bia@example.com');
    await tester.tap(send);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Enviar link'), findsOneWidget);
    answer.complete(http.Response('', 202));
    await tester.pumpAndSettle();
  });

  testWidgets('unauthenticated lands on the entry screen, signed out', (
    tester,
  ) async {
    await emailScreen(tester, answer: (_) => problem(401, 'unauthenticated'));

    await submit(tester);

    expect(find.byType(EntryScreen), findsOneWidget);
  });
}
