import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/pin_pad.dart';
import 'package:telinha_segura/kid_mode/set_pin_screen.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

/// `/modo-crianca/pin` over an API that answers the PIN write with
/// [answer] (204 by default); [reauth] makes the first write answer
/// `reauth_required` until the guardian confirms.
Future<Harness> setPin(
  WidgetTester tester, {
  bool pinSet = false,
  FutureOr<http.Response> Function(http.Request)? answer,
  FutureOr<http.Response> Function(http.Request)? read,
  bool reauth = false,
}) async {
  late final Harness h;
  var confirmed = !reauth;
  h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.url.path == '/v1/session/reauth') {
              confirmed = true;
              return http.Response('', 204);
            }
            if (req.url.path == '/v1/parental/pin' && req.method == 'PUT') {
              if (!confirmed) return problem(403, 'reauth_required');
              if (answer != null) return answer(req);
              h.pinSet = true;
              return http.Response('', 204);
            }
            return http.Response('', 204);
          },
        )
        ..family = ownerFamily
        ..pinSet = pinSet
        ..parentalRead = read;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/modo-crianca/pin');
  return h;
}

Future<void> type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.bySemanticsLabel(d));
    await tester.pump();
  }
}

/// Types [digits] and confirms them on the pad.
Future<void> enter(WidgetTester tester, String digits) async {
  await type(tester, digits);
  await tester.ensureVisible(find.bySemanticsLabel('Confirmar'));
  await tester.tap(find.bySemanticsLabel('Confirmar'));
  await tester.pumpAndSettle();
}

List<bool> modules(WidgetTester tester) => tester
    .widgetList<StateModule>(
      find.descendant(
        of: find.byType(PinPad),
        matching: find.byType(StateModule),
      ),
    )
    .map((m) => m.filled)
    .toList();

bool padEnabled(WidgetTester tester) =>
    tester.widget<PinPad>(find.byType(PinPad)).enabled;

/// Every PIN screen reads in one order: [lead] (the intro line or the
/// title), then the error note right above the pad (fix round, item 7).
void expectNoteAbovePad(WidgetTester tester, Finder lead) {
  final note = tester.getRect(find.byType(ErrorNote));
  expect(tester.getRect(lead).bottom, lessThanOrEqualTo(note.top));
  expect(
    note.bottom,
    lessThanOrEqualTo(tester.getRect(find.byType(PinPad)).top),
  );
}

void main() {
  group('the title says what the PIN screen does', () {
    for (final (pinSet, title) in [
      (false, 'Criar o PIN'),
      (true, 'Trocar o PIN'),
    ]) {
      testWidgets(title, (tester) async {
        await setPin(tester, pinSet: pinSet);

        expect(find.text(title), findsOneWidget);
        expect(find.byType(PinPad), findsOneWidget);
        expect(find.text(firstEntry), findsOneWidget);
      });
    }
  });

  testWidgets('the first entry asks for the confirmation on an empty pad', (
    tester,
  ) async {
    final h = await setPin(tester);

    await enter(tester, '2580');

    expect(find.text(confirmEntry), findsOneWidget);
    expect(modules(tester), List.filled(6, false));
    expect(h.actions, isEmpty);
  });

  testWidgets('a matching confirmation saves the PIN and returns to the '
      'guide at Passo 2 de 2, the sun rising', (tester) async {
    final h = await setPin(tester);

    await enter(tester, '2580');
    await enter(tester, '2580');

    expect(h.actions, ['PUT /v1/parental/pin {"pin":"2580"}']);
    expect(h.location(tester), '/modo-crianca');
    final step = tester.widget<StepMarks>(find.byType(StepMarks));
    expect((step.step, step.of), (2, 2));
    expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);
    expect(
      find.text(
        'PIN criado. Avisamos por e-⁠mail os outros adultos da família.',
      ),
      findsOne,
    );
  });

  testWidgets('a changed PIN returns to the index', (tester) async {
    final h = await setPin(tester, pinSet: true);

    await enter(tester, '4719');
    await enter(tester, '4719');

    expect(h.location(tester), '/modo-crianca');
    expect(find.byType(StepMarks), findsNothing);
    expect(find.textContaining('PIN trocado.'), findsOne);
  });

  testWidgets('a confirmation that differs says so and starts again, the '
      'pad empty', (tester) async {
    final h = await setPin(tester);

    await enter(tester, '2580');
    await enter(tester, '2581');

    expect(find.text(pinMismatch), findsOneWidget);
    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.text(firstEntryAgain), findsOneWidget);
    expectNoteAbovePad(tester, find.text(firstEntryAgain));
    expect(modules(tester), List.filled(6, false));
    expect(h.actions, isEmpty);

    // Starting over: the next two matching entries save.
    await enter(tester, '4719');
    await enter(tester, '4719');
    expect(h.actions, ['PUT /v1/parental/pin {"pin":"4719"}']);
  });

  for (final (code, words) in [
    ('validation', Copy.pinRule),
    ('weak_pin', 'Esse PIN é fácil de adivinhar'),
  ]) {
    testWidgets('$code says the rule and starts again', (tester) async {
      await setPin(tester, answer: (_) => problem(422, code));

      await enter(tester, '1111');
      await enter(tester, '1111');

      expect(find.textContaining(words), findsOneWidget);
      expect(find.text(firstEntryAgain), findsOneWidget);
      expect(modules(tester), List.filled(6, false));
    });
  }

  testWidgets('reauth_required asks to confirm it is you, then retries '
      'once', (tester) async {
    final h = await setPin(tester, reauth: true);

    await enter(tester, '2580');
    await enter(tester, '2580');
    expect(find.byType(ReauthPrompt), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'uma senha longa');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(h.actions, [
      'PUT /v1/parental/pin {"pin":"2580"}',
      'POST /v1/session/reauth {"password":"uma senha longa"}',
      'PUT /v1/parental/pin {"pin":"2580"}',
    ]);
    expect(h.location(tester), '/modo-crianca');
  });

  testWidgets('a cancelled confirmation saves nothing and starts again', (
    tester,
  ) async {
    final h = await setPin(tester, reauth: true);

    await enter(tester, '2580');
    await enter(tester, '2580');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(h.actions, ['PUT /v1/parental/pin {"pin":"2580"}']);
    expect(h.location(tester), '/modo-crianca/pin');
    expect(find.text(firstEntryAgain), findsOneWidget);
    expect(modules(tester), List.filled(6, false));
  });

  testWidgets('the pad waits while the PIN is saved', (tester) async {
    final answer = Completer<http.Response>();
    await setPin(tester, answer: (_) => answer.future);

    await enter(tester, '2580');
    await type(tester, '2580');
    await tester.tap(find.bySemanticsLabel('Confirmar'));
    await tester.pump();

    expect(padEnabled(tester), isFalse);
    answer.complete(http.Response('', 204));
    await tester.pumpAndSettle();
  });

  testWidgets('a dropped connection says so, keeps nothing of the PIN and '
      'starts again', (tester) async {
    await setPin(tester, answer: (_) => throw http.ClientException('down'));

    await enter(tester, '2580');
    await enter(tester, '2580');

    expect(find.text(Copy.genericRetry), findsOneWidget);
    expect(find.text(firstEntryAgain), findsOneWidget);
    expect(modules(tester), List.filled(6, false));
    expect(padEnabled(tester), isTrue);
    expect(find.textContaining('2580'), findsNothing);
  });

  testWidgets('rate_limited disables the pad while the countdown runs', (
    tester,
  ) async {
    await setPin(
      tester,
      answer: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'}),
    );

    await enter(tester, '2580');
    await type(tester, '2580');
    await tester.tap(find.bySemanticsLabel('Confirmar'));
    await tester.pump();

    expect(find.textContaining('30 s'), findsOneWidget);
    expect(padEnabled(tester), isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(padEnabled(tester), isTrue);
  });

  testWidgets('a failed read offers Tentar de novo, which reads again', (
    tester,
  ) async {
    var fail = true;
    await setPin(
      tester,
      read: (_) =>
          fail ? problem(503, 'unavailable') : json(200, {'set': true}),
    );

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.byType(PinPad), findsNothing);
    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.text('Trocar o PIN'), findsOneWidget);
    expect(find.byType(PinPad), findsOneWidget);
  });

  testWidgets('back returns to /modo-crianca', (tester) async {
    final h = await setPin(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/modo-crianca');
  });
}
