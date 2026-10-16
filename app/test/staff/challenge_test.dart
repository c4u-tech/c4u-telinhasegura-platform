import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/mfa_words.dart';

import '../access/harness.dart';
import '../account/mfa_fixtures.dart';
import '../family/fixtures.dart';

const title = 'Código do app autenticador';
const recoveryTitle = 'Use um código de recuperação';
const recoveryField = 'Código de recuperação';
const codeField = 'Código de 6 números';
const toRecovery = 'Usar um código de recuperação';
const toApp = 'Usar o app autenticador';
const codesShown = 'Guarde seus códigos de recuperação';
const sessionsDoor = 'Não foi você? Encerre a sessão nos outros aparelhos.';

/// `/conta/verificacao` for Ana, an admin, whose new codes first answer
/// `elevation_required`: "Gerar novos códigos" opens the challenge, whose
/// route answers [challenge]. The regeneration succeeds once asked again.
Future<Harness> openChallenge(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? challenge,
  List<String> roles = const ['admin'],
  FutureOr<http.Response> Function()? start,
}) async {
  var asked = 0;
  final h =
      Harness(
          signedIn: true,
          api: mfaApi(
            challenge: challenge,
            start: start,
            regenerate: () => asked++ == 0
                ? problem(403, 'elevation_required')
                : json(200, codesJson(elevated: false)),
          ),
        )
        ..family = ownerFamily
        ..roles = roles;
  await h.pump(tester, initial: '/conta/verificacao');
  await tapText(tester, 'Gerar novos códigos');
  await tapText(tester, 'Gerar novos códigos');
  return h;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

List<String> challenges(Harness h) => [
  for (final c in h.actions)
    if (c.startsWith('POST /v1/staff/mfa/challenge')) c,
];

Finder get field => find.byType(TextField);

TextField fieldOf(WidgetTester tester) => tester.widget<TextField>(field);

VoidCallback? primaryOf(WidgetTester tester, String label) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, label))
    .onPressed;

void main() {
  testWidgets('asks for the six digits, with a numeric keyboard and the '
      'one-time-code autofill', (tester) async {
    await openChallenge(tester);

    expect(find.text(title), findsOneWidget);
    expect(
      find.text('Digite o código de 6 números que o app mostra agora.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, codeField), findsOneWidget);
    expect(fieldOf(tester).keyboardType, TextInputType.number);
    expect(fieldOf(tester).autofillHints, [AutofillHints.oneTimeCode]);
    expect(find.text(toRecovery), findsOneWidget);
    expect(primaryOf(tester, 'Confirmar'), isNull);
    await tester.enterText(field, '12345');
    await tester.pump();
    expect(primaryOf(tester, 'Confirmar'), isNull);
  });

  testWidgets('passed, it returns to the asking screen, whose write runs '
      'again', (tester) async {
    final h = await openChallenge(tester);

    await tester.enterText(field, '123456');
    await tapText(tester, 'Confirmar');

    expect(challenges(h), [
      'POST /v1/staff/mfa/challenge ${jsonEncode({'code': '123456'})}',
    ]);
    expect(find.text(title), findsNothing);
    expect(find.text(codesShown), findsOneWidget);
  });

  testWidgets('"Usar um código de recuperação" swaps the field, which sends '
      'a recovery code as typed; "Usar o app autenticador" swaps back', (
    tester,
  ) async {
    final h = await openChallenge(tester);

    await tapText(tester, toRecovery);
    expect(find.text(recoveryTitle), findsOneWidget);
    expect(find.widgetWithText(TextField, codeField), findsNothing);
    expect(find.widgetWithText(TextField, recoveryField), findsOneWidget);
    await tapText(tester, toApp);
    expect(find.widgetWithText(TextField, codeField), findsOneWidget);
    await tapText(tester, toRecovery);

    await tester.enterText(field, 'abcde fghj-k');
    await tapText(tester, 'Confirmar');

    expect(challenges(h), [
      'POST /v1/staff/mfa/challenge '
          '${jsonEncode({'recovery_code': 'abcde fghj-k'})}',
    ]);
  });

  for (final (left, lines, absent) in [
    (4, ['Restam 4 códigos de recuperação.'], ['Gere novos em Sua conta.']),
    (3, ['Restam 3 códigos de recuperação.', 'Gere novos em Sua conta.'], []),
    (1, ['Resta 1 código de recuperação.', 'Gere novos em Sua conta.'], []),
  ]) {
    testWidgets('after a recovery code with $left left, says so before '
        'going on', (tester) async {
      await openChallenge(
        tester,
        challenge: (_) => json(200, elevationJson(left: left)),
      );
      await tapText(tester, toRecovery);
      await tester.enterText(field, 'ABCDE-FGHJK');
      await tapText(tester, 'Confirmar');

      for (final line in lines) {
        expect(find.text(line), findsOneWidget);
      }
      for (final line in absent) {
        expect(find.text(line), findsNothing);
      }
      expect(find.text(codesShown), findsNothing);
      await tapText(tester, 'Continuar');
      expect(find.text(codesShown), findsOneWidget);
    });
  }

  testWidgets('mfa_code_invalid keeps the screen and says so on the field', (
    tester,
  ) async {
    await openChallenge(
      tester,
      challenge: (_) => problem(400, 'mfa_code_invalid'),
    );

    await tester.enterText(field, '123456');
    await tapText(tester, 'Confirmar');
    expect(
      find.text(
        'Esse código não confere. Use o código que aparece agora no '
        'app.',
      ),
      findsOneWidget,
    );
    expect(find.text(title), findsOneWidget);

    await tapText(tester, toRecovery);
    await tester.enterText(field, 'ABCDE-FGHJK');
    await tapText(tester, 'Confirmar');
    expect(
      find.text('Esse código não confere ou já foi usado.'),
      findsOneWidget,
    );
    expect(find.text(recoveryTitle), findsOneWidget);
  });

  group('blocked', () {
    Future<Harness> blocked(WidgetTester tester, {int seconds = 240}) async {
      var calls = 0;
      final h = await openChallenge(
        tester,
        challenge: (_) => calls++ == 0
            ? problem(429, 'rate_limited', retryAfterBody: seconds)
            : json(200, elevationJson()),
      );
      await tester.enterText(field, '123456');
      await tapText(tester, 'Confirmar');
      return h;
    }

    String blockedFor(int minutes) =>
        'Muitas tentativas erradas. Tente de novo em $minutes\u00A0min.';

    testWidgets('disables the field and the primary, and counts down in '
        'minutes until it enables them again', (tester) async {
      await blocked(tester);

      expect(find.widgetWithText(ErrorNote, blockedFor(4)), findsOneWidget);
      expect(fieldOf(tester).enabled, isFalse);
      expect(primaryOf(tester, 'Confirmar'), isNull);

      // Not every second: the note changes, and is announced, by minute.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(blockedFor(4)), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(blockedFor(3)), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      expect(find.text(blockedFor(1)), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      expect(find.text(blockedFor(1)), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ErrorNote), findsNothing);
      expect(find.text(sessionsDoor), findsNothing);
      expect(fieldOf(tester).enabled, isTrue);
      // The expired code is gone: a new one, not a wasted attempt.
      expect(fieldOf(tester).controller!.text, isEmpty);
      expect(primaryOf(tester, 'Confirmar'), isNull);
      await tester.enterText(field, '654321');
      await tester.pump();
      expect(primaryOf(tester, 'Confirmar'), isNotNull);
    });

    testWidgets('a block on a recovery code clears that field too', (
      tester,
    ) async {
      await openChallenge(
        tester,
        challenge: (_) => problem(429, 'rate_limited', retryAfterBody: 60),
      );
      await tapText(tester, toRecovery);
      await tester.enterText(field, 'ABCDE-FGHJK');
      await tapText(tester, 'Confirmar');

      expect(find.text(blockedFor(1)), findsOneWidget);
      expect(fieldOf(tester).controller!.text, isEmpty);
      expect(fieldOf(tester).enabled, isFalse);
    });

    testWidgets('a block under a minute reads as 1 min', (tester) async {
      await blocked(tester, seconds: 30);

      expect(find.text(blockedFor(1)), findsOneWidget);
    });

    testWidgets('the note is announced as a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      await blocked(tester);

      expect(
        tester.getSemantics(find.text(blockedFor(4))),
        matchesSemantics(label: blockedFor(4), isLiveRegion: true),
      );
      semantics.dispose();
    });

    testWidgets('the door opens the sessions, and coming back shows the '
        'challenge as it was', (tester) async {
      await blocked(tester);
      expect(find.text(sessionsDoor), findsOneWidget);

      await tapText(tester, sessionsDoor);
      expect(find.text('Aparelhos conectados'), findsOneWidget);
      expect(find.text(title), findsNothing);

      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(blockedFor(4)), findsOneWidget);
      expect(fieldOf(tester).controller!.text, isEmpty);
      expect(fieldOf(tester).enabled, isFalse);
    });

    testWidgets('the system back from the sessions also comes back', (
      tester,
    ) async {
      await blocked(tester);
      await tapText(tester, sessionsDoor);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(find.text(blockedFor(4)), findsOneWidget);
    });
  });

  testWidgets('mfa_not_enrolled opens the enrollment', (tester) async {
    await openChallenge(
      tester,
      challenge: (_) => problem(409, 'mfa_not_enrolled'),
    );

    await tester.enterText(field, '123456');
    await tapText(tester, 'Confirmar');

    expect(find.text(title), findsNothing);
    expect(find.text('Conecte o app autenticador'), findsOneWidget);
  });

  for (final (code, roles, notice) in [
    ('not_admin', ['admin'], 'Você não tem mais acesso à administração.'),
    ('not_moderator', ['moderator'], 'Você não tem mais acesso à moderação.'),
    ('not_staff', ['admin'], 'Você não tem mais acesso à administração.'),
    ('not_staff', ['moderator'], 'Você não tem mais acesso à moderação.'),
    ('not_staff', ['curator'], 'Você não faz mais parte da curadoria.'),
  ]) {
    testWidgets('$code for $roles goes home, which says why', (tester) async {
      final h = await openChallenge(
        tester,
        roles: roles,
        challenge: (_) => problem(403, code),
      );
      h.roles = const [];

      await tester.enterText(field, '123456');
      await tapText(tester, 'Confirmar');

      expect(find.text(title), findsNothing);
      expect(h.location(tester), '/');
      expect(find.text(notice), findsOneWidget);
    });
  }

  testWidgets('mfa_unavailable says so', (tester) async {
    await openChallenge(
      tester,
      challenge: (_) => problem(503, 'mfa_unavailable'),
    );

    await tester.enterText(field, '123456');
    await tapText(tester, 'Confirmar');

    expect(find.widgetWithText(ErrorNote, mfaUnavailable), findsOneWidget);
    expect(find.text(title), findsOneWidget);
  });

  testWidgets('a network failure says so, and "Tentar de novo" sends the '
      'same code again', (tester) async {
    var calls = 0;
    final h = await openChallenge(
      tester,
      challenge: (_) => calls++ == 0
          ? throw http.ClientException('offline')
          : json(200, elevationJson()),
    );

    await tester.enterText(field, '123456');
    await tapText(tester, 'Confirmar');
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);

    await tapText(tester, 'Tentar de novo');
    expect(challenges(h), hasLength(2));
    expect(challenges(h).toSet(), hasLength(1));
    expect(find.text(codesShown), findsOneWidget);
  });

  testWidgets('cancelled, the asking screen stays as it was, with no '
      'message', (tester) async {
    final h = await openChallenge(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(find.text(title), findsNothing);
    expect(find.text('Gerar novos códigos'), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
    expect(challenges(h), isEmpty);
  });

  testWidgets('the system back cancels too', (tester) async {
    await openChallenge(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(title), findsNothing);
    expect(find.text('Gerar novos códigos'), findsOneWidget);
  });
}
