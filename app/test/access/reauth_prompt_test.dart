import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/auth/provider_authenticator.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/family/family_write.dart';
import 'package:telinha_segura/shell/services.dart';

import '../family/fixtures.dart';
import 'harness.dart';

const _password = 'uma senha bem comprida';

/// The family home over a scripted API. [reauth] answers
/// `POST /v1/session/reauth`; `DELETE /v1/family` answers
/// `reauth_required` until a re-authentication succeeded.
Future<Harness> signedIn(
  WidgetTester tester, {
  http.Response Function()? reauth,
  ProviderSettings settings = noProviders,
  FakeGoogleWeb? googleWeb,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  var confirmed = false;
  final h = Harness(
    signedIn: true,
    settings: settings,
    googleWeb: googleWeb,
    api: (req) {
      if (req.url.path == '/v1/session/reauth') {
        final answer = (reauth ?? () => http.Response('', 204))();
        confirmed = answer.statusCode == 204;
        return answer;
      }
      if (req.method == 'DELETE' && req.url.path == '/v1/family') {
        return confirmed
            ? http.Response('', 204)
            : problem(403, 'reauth_required');
      }
      return http.Response('', 204);
    },
  )..family = ownerFamily;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, size: size, textScale: textScale);
  return h;
}

BuildContext homeContext(WidgetTester tester) =>
    tester.element(find.byType(FamilyHomeScreen));

/// Opens the prompt from the home; the future holds its answer.
Future<bool> open(WidgetTester tester) {
  final answer = confirmItsYou(homeContext(tester));
  return answer;
}

/// Deletes the family through a [FamilyWrite], as the family screens do.
({Future<bool> done, FamilyWrite write}) deleteFamily(WidgetTester tester) {
  final context = homeContext(tester);
  final services = AppScope.of(context);
  final write = FamilyWrite(
    family: services.familyModel,
    confirm: () => confirmItsYou(context),
  );
  return (done: write.write(services.family.delete), write: write);
}

Future<void> typePassword(
  WidgetTester tester, [
  String text = _password,
]) async {
  await tester.enterText(find.byType(TextField), text);
  // Focus scrolls the field into view; let it land before tapping.
  await tester.pumpAndSettle();
}

Future<void> tapConfirm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Confirmar'));
  await tester.tap(find.text('Confirmar'));
  await tester.pumpAndSettle();
}

/// The answer of [future] once the app settled; null while pending. The
/// app's requests only advance while the test pumps.
Future<bool?> answerOf(WidgetTester tester, Future<bool> future) async {
  bool? answer;
  unawaited(future.then((v) => answer = v));
  await tester.pumpAndSettle();
  return answer;
}

Map<String, dynamic> bodyOf(String call) =>
    jsonDecode(call.split(' ').skip(2).join(' ')) as Map<String, dynamic>;

void main() {
  testWidgets('a reauth_required write opens the prompt, says why, and '
      'retries once after the password', (tester) async {
    final h = await signedIn(tester);

    final run = deleteFamily(tester);
    await tester.pumpAndSettle();

    expect(find.byType(ReauthPrompt), findsOneWidget);
    expect(find.text('Confirme que é você'), findsOneWidget);
    expect(find.text(reauthReason), findsOneWidget);
    expect(h.actions, ['DELETE /v1/family']);

    await typePassword(tester);
    await tapConfirm(tester);

    expect(await answerOf(tester, run.done), isTrue);
    expect(find.byType(ReauthPrompt), findsNothing);
    expect(h.actions, [
      'DELETE /v1/family',
      'POST /v1/session/reauth {"password":"$_password"}',
      'DELETE /v1/family',
    ]);
    expect(run.write.message, isNull);
  });

  testWidgets('cancel closes the prompt and leaves the action undone', (
    tester,
  ) async {
    final h = await signedIn(tester);

    final run = deleteFamily(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancelar'));
    // Cancelar starts on the column edge, under Confirmar.
    expect(
      tester.getTopLeft(find.text('Cancelar')).dx,
      tester
          .getTopLeft(
            find.descendant(
              of: find.byType(ReauthPrompt),
              matching: find.byType(FilledButton),
            ),
          )
          .dx,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(await answerOf(tester, run.done), isFalse);
    expect(find.byType(ReauthPrompt), findsNothing);
    expect(h.actions, ['DELETE /v1/family']);
    expect(run.write.message, isNull);
    expect(run.write.blocked, isFalse);
  });

  testWidgets('the band\'s back control cancels too', (tester) async {
    await signedIn(tester);

    final answer = open(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(await answerOf(tester, answer), isFalse);
  });

  testWidgets('Confirmar waits for a password', (tester) async {
    final h = await signedIn(tester);

    unawaited(open(tester));
    await tester.pumpAndSettle();
    await tapConfirm(tester);

    expect(h.actions, isEmpty);
    expect(find.byType(ReauthPrompt), findsOneWidget);
  });

  testWidgets('invalid_credentials keeps the prompt open with the sign-in '
      'message and a cleared password', (tester) async {
    final h = await signedIn(
      tester,
      reauth: () => problem(401, 'invalid_credentials'),
    );

    unawaited(open(tester));
    await tester.pumpAndSettle();
    await typePassword(tester);
    await tapConfirm(tester);

    expect(find.byType(ReauthPrompt), findsOneWidget);
    expect(
      find.text(
        'O e-\u2060mail ou a senha não conferem. Confira e tente de novo.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(h.actions, hasLength(1));
  });

  testWidgets('rate_limited counts down and blocks Confirmar', (tester) async {
    final h = await signedIn(
      tester,
      reauth: () => problem(429, 'rate_limited', retryAfterBody: 2),
    );

    unawaited(open(tester));
    await tester.pumpAndSettle();
    await typePassword(tester);
    await tapConfirm(tester);

    expect(find.text(Copy.retryIn(const Duration(seconds: 2))), findsOne);
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    expect(h.actions, hasLength(1));

    await tester.pump(const Duration(seconds: 2));
    expect(find.text(Copy.retryIn(const Duration(seconds: 1))), findsNothing);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(h.actions, hasLength(2));
  });

  testWidgets('without provider settings only the password is offered', (
    tester,
  ) async {
    await signedIn(tester);

    unawaited(open(tester));
    await tester.pumpAndSettle();

    expect(find.text('ou'), findsNothing);
    expect(find.text('Continuar com o Google'), findsNothing);
    expect(find.text('Continuar com a Apple'), findsNothing);
  });

  testWidgets('a provider token re-authenticates and the write retries', (
    tester,
  ) async {
    final h = await signedIn(tester, settings: allProviders);
    h.providers.answers[IdentityProvider.google] = 'google-id-token';

    final run = deleteFamily(tester);
    await tester.pumpAndSettle();
    expect(find.text('ou'), findsOneWidget);
    expect(find.text('Continuar com a Apple'), findsOneWidget);
    await tester.ensureVisible(find.text('Continuar com o Google'));
    await tester.tap(find.text('Continuar com o Google'));
    await tester.pumpAndSettle();

    expect(await answerOf(tester, run.done), isTrue);
    expect(h.providers.asked, [IdentityProvider.google]);
    expect(h.actions, hasLength(3));
    final body = bodyOf(h.actions[1]);
    expect(body, {'provider': 'google', 'id_token': 'google-id-token'});
  });

  testWidgets('a cancelled provider sheet keeps the prompt open and quiet', (
    tester,
  ) async {
    final h = await signedIn(tester, settings: allProviders);
    h.providers.answers[IdentityProvider.apple] = null;

    unawaited(open(tester));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar com a Apple'));
    await tester.tap(find.text('Continuar com a Apple'));
    await tester.pumpAndSettle();

    expect(h.actions, isEmpty);
    expect(find.byType(ReauthPrompt), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('another provider account is refused in its own words', (
    tester,
  ) async {
    final h = await signedIn(
      tester,
      settings: allProviders,
      reauth: () => problem(401, 'invalid_credentials'),
    );
    h.providers.answers[IdentityProvider.apple] = 'apple-id-token';

    unawaited(open(tester));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar com a Apple'));
    await tester.tap(find.text('Continuar com a Apple'));
    await tester.pumpAndSettle();

    expect(find.byType(ReauthPrompt), findsOneWidget);
    expect(find.text(Copy.otherProviderAccount), findsOneWidget);
  });

  testWidgets('on the web, Google\'s rendered button delivers the token', (
    tester,
  ) async {
    final google = FakeGoogleWeb();
    final h = await signedIn(tester, settings: allProviders, googleWeb: google);

    final answer = open(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gis-button')), findsOneWidget);
    expect(find.text('Continuar com o Google'), findsNothing);

    google.tokens.add('web-id-token');
    await tester.pumpAndSettle();

    expect(await answerOf(tester, answer), isTrue);
    expect(bodyOf(h.actions.single), {
      'provider': 'google',
      'id_token': 'web-id-token',
    });
  });

  testWidgets('the title is a header for assistive technology', (tester) async {
    final semantics = tester.ensureSemantics();
    await signedIn(tester);

    unawaited(open(tester));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Confirme que é você')),
      matchesSemantics(label: 'Confirme que é você', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('meets the tap target, label and contrast guidelines, with '
      'an error showing', (tester) async {
    final semantics = tester.ensureSemantics();
    await signedIn(
      tester,
      settings: allProviders,
      reauth: () => problem(401, 'invalid_credentials'),
    );

    unawaited(open(tester));
    await tester.pumpAndSettle();
    await typePassword(tester);
    await tapConfirm(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('holds at text scale 2.0 on ${size.width.toInt()} wide, '
        'Confirmar reachable', (tester) async {
      final h = await signedIn(
        tester,
        settings: allProviders,
        size: size,
        textScale: 2,
      );

      unawaited(open(tester));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final control in ['Continuar com a Apple', 'Cancelar']) {
        await tester.ensureVisible(find.text(control));
        expect(tester.takeException(), isNull);
      }
      await typePassword(tester);
      await tapConfirm(tester);
      expect(tester.takeException(), isNull);
      expect(h.actions, hasLength(1));
    });
  }
}
