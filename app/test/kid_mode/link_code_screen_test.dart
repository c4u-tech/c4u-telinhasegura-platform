import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/kid_mode/kid_mode_screen.dart';
import 'package:telinha_segura/kid_mode/link_code_screen.dart';
import 'package:telinha_segura/kid_mode/link_qr.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../parental/parental_api_test.dart' show deviceJson;
import 'hand_over_screen_test.dart'
    show chosen, choice, expectChoosingMovesNothing, primary, tapOn;

final twoChildren = [minorJson('m1', 'Lia'), minorJson('m2', 'Téo')];

/// A live code for the child the request names, expiring 10 minutes
/// from the test's clock.
http.Response liveCode(http.Request req, [String code = 'ABCD-1234']) =>
    json(201, {
      'code': code,
      'minor_id': (jsonDecode(req.body) as Map)['minor_id'],
      'expires_at': clock
          .now()
          .add(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String(),
    });

/// `/modo-crianca/vincular` for a family holding [minors]; generating
/// answers [answer] (a live code by default).
Future<Harness> linkCode(
  WidgetTester tester, {
  List<Map<String, Object?>>? minors,
  FutureOr<http.Response> Function(http.Request)? answer,
  int devices = 0,
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  final h =
      Harness(
          signedIn: true,
          api: (req) => req.url.path == '/v1/parental/link-codes'
              ? (answer ?? liveCode)(req)
              : http.Response('', 204),
        )
        ..family = familyWith(minors ?? twoChildren)
        ..pinSet = true
        ..linkedDevices = [
          for (var i = 0; i < devices; i++) {...deviceJson, 'id': 'd$i'},
        ];
  unawaited(h.services.familyModel.load());
  await h.pump(
    tester,
    initial: '/modo-crianca/vincular',
    textScale: textScale,
    size: size,
  );
  return h;
}

/// Matches a number left to break from the word after it at a line end:
/// "10 minutos" must not wrap to "10 / minutos" (fix round, item 6).
final strandable = RegExp(
  r'\d (minutos?|min|aparelhos?|códigos?|caracteres|s)\b',
);

/// Every text on screen, none with a number that could strand.
void expectNoStrandedNumbers(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data ?? text.textSpan?.toPlainText() ?? '';
    expect(strandable.hasMatch(data), isFalse, reason: data);
  }
}

/// Chooses [nickname] and generates a code.
Future<void> generate(WidgetTester tester, [String nickname = 'Téo']) async {
  await tapOn(tester, find.text(nickname));
  await tapOn(tester, find.text('Gerar código'));
}

const post = 'POST /v1/parental/link-codes';

void main() {
  testWidgets('each child is a choice of one, none chosen, and "Gerar '
      'código" waits for one', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await linkCode(tester);

    expect(find.byType(LinkCodeScreen), findsOneWidget);
    expect(find.text('Vincular o aparelho da criança'), findsOneWidget);
    for (final name in ['Lia', 'Téo']) {
      expect(tester.getSemantics(choice(name)), chosen(name, false));
    }
    expect(find.text('Gerar código'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(primary).onPressed, isNull);
    expect(h.actions, isEmpty);
    semantics.dispose();
  });

  testWidgets('at 1440 × 900 choosing a child keeps the title where it '
      'is (fix round, item 3)', (tester) async {
    await linkCode(tester, size: const Size(1440, 900));
    await tester.pumpAndSettle();
    await expectChoosingMovesNothing(tester, 'Vincular o aparelho da criança');
  });

  testWidgets('without children, it asks to register one first', (
    tester,
  ) async {
    final h = await linkCode(tester, minors: []);

    expect(find.text(childFirst), findsOneWidget);
    await tapOn(tester, find.text('Cadastrar criança'));

    expect(h.location(tester), '/familia/criancas/nova');
  });

  testWidgets('a chosen child gets a code in two groups of four, a QR of '
      'its link, and the minutes left', (tester) async {
    final h = await linkCode(tester);

    await generate(tester);

    expect(h.actions, ['$post {"minor_id":"m2"}']);
    expect(find.text('ABCD'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(tester.widget<LinkQr>(find.byType(LinkQr)).code, 'ABCD-1234');
    // A moment after the 10 minutes began: whole minutes, rounded down.
    expect(find.text('expira em 9\u00A0min'), findsOneWidget);
    expect(find.textContaining('Téo'), findsWidgets);
  });

  testWidgets('the code is read character by character, and the QR says it '
      'holds the same code', (tester) async {
    final semantics = tester.ensureSemantics();
    await linkCode(tester);

    await generate(tester);

    expect(
      find.bySemanticsLabel('Código: A, B, C, D, 1, 2, 3, 4'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('QR com o código A, B, C, D, 1, 2, 3, 4'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('at 200% text each step number stays on one line', (
    tester,
  ) async {
    await linkCode(tester, textScale: 2);
    await generate(tester);

    for (final marker in ['1.', '2.', '3.']) {
      final finder = find.text(marker);
      await tester.ensureVisible(finder);
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final lines = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      expect(
        lines.map((b) => b.top).toSet(),
        hasLength(1),
        reason: '"$marker" wraps',
      );
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('at ${scale * 100}% text the steps start at one x, each '
        'marker 8 dp clear of its line', (tester) async {
      await linkCode(tester, textScale: scale);
      await generate(tester);

      final starts = <double>{};
      for (final (i, step) in [
        'Instale o Telinha',
        'Aponte a câmera',
        'Ou toque em',
      ].indexed) {
        final text = find.textContaining(step);
        await tester.ensureVisible(text);
        final left = tester.getTopLeft(text).dx;
        starts.add(left);
        final marker = find.text('${i + 1}.');
        final glyphs = tester
            .renderObject<RenderParagraph>(marker)
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 2),
            );
        final right =
            tester.getTopLeft(marker).dx +
            glyphs.map((b) => b.right).reduce(math.max);
        expect(left - right, greaterThanOrEqualTo(8), reason: '${i + 1}.');
      }
      expect(starts, hasLength(1));
    });
  }

  testWidgets('no number is stranded from its word at a line break', (
    tester,
  ) async {
    await linkCode(
      tester,
      devices: 10,
      answer: (_) => problem(409, 'limit_reached'),
    );
    expectNoStrandedNumbers(tester);
    await generate(tester);
    expect(find.text(Copy.devicesFull), findsOneWidget);
    expectNoStrandedNumbers(tester);
    for (final text in [codeExpired, Copy.devicesFull, Copy.linkCodesFull]) {
      expect(strandable.hasMatch(text), isFalse, reason: text);
    }
    expect(codeExpired, contains('10\u00A0minutos'));
    expect(Copy.devicesFull, contains('10\u00A0aparelhos'));
  });

  testWidgets('three short steps on the child device', (tester) async {
    await linkCode(tester);

    await generate(tester);

    expect(
      find.textContaining('Instale o Telinha Segura no aparelho da criança'),
      findsOneWidget,
    );
    expect(find.textContaining('câmera'), findsOneWidget);
    expect(
      find.textContaining('“Este aparelho é de uma criança”'),
      findsOneWidget,
    );
  });

  testWidgets('the minutes left stay current while the screen is open', (
    tester,
  ) async {
    await linkCode(tester);
    await generate(tester);

    expect(find.text('expira em 9\u00A0min'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    expect(find.text('expira em 8\u00A0min'), findsOneWidget);

    await tester.pump(const Duration(minutes: 7));
    expect(find.text('expira em 1\u00A0min'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    expect(find.text('expira em menos de 1\u00A0min'), findsOneWidget);
  });

  testWidgets('an expired code hides the code and the QR, says so, and '
      '"Gerar outro código" makes a new one for the same child', (
    tester,
  ) async {
    var n = 0;
    final h = await linkCode(
      tester,
      answer: (req) => liveCode(req, ++n == 1 ? 'ABCD-1234' : 'WXYZ-5678'),
    );
    await generate(tester);

    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();

    expect(find.text('ABCD'), findsNothing);
    expect(find.byType(LinkQr), findsNothing);
    expect(find.textContaining('expira em'), findsNothing);
    expect(find.text(codeExpired), findsOneWidget);
    expect(
      tester.widget<PrimaryButton>(primary).onPressed,
      isNotNull,
      reason: 'Gerar outro código is the primary',
    );
    expect(find.text('Gerar outro código'), findsOneWidget);

    await tapOn(tester, find.text('Gerar outro código'));

    expect(h.actions, ['$post {"minor_id":"m2"}', '$post {"minor_id":"m2"}']);
    expect(find.text('WXYZ'), findsOneWidget);
    expect(find.text('expira em 9\u00A0min'), findsOneWidget);
  });

  testWidgets('limit_reached with 10 devices says the family is full and '
      'links to the devices', (tester) async {
    final h = await linkCode(
      tester,
      devices: 10,
      answer: (_) => problem(409, 'limit_reached'),
    );

    await generate(tester);

    expect(find.text(Copy.devicesFull), findsOneWidget);
    await tapOn(tester, find.text('Ver aparelhos vinculados'));
    expect(h.location(tester), '/modo-crianca/aparelhos');
  });

  testWidgets('limit_reached with room for devices means 5 codes waiting', (
    tester,
  ) async {
    await linkCode(
      tester,
      devices: 2,
      answer: (_) => problem(409, 'limit_reached'),
    );

    await generate(tester);

    expect(find.text(Copy.linkCodesFull), findsOneWidget);
    expect(find.text(Copy.devicesFull), findsNothing);
    expect(find.text('Ver aparelhos vinculados'), findsNothing);
  });

  testWidgets('rate_limited counts down and keeps "Gerar código" disabled', (
    tester,
  ) async {
    await linkCode(
      tester,
      answer: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'}),
    );

    await generate(tester);

    expect(find.text(Copy.retryIn(const Duration(seconds: 30))), findsOne);
    expect(tester.widget<PrimaryButton>(primary).onPressed, isNull);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(tester.widget<PrimaryButton>(primary).onPressed, isNotNull);
  });

  testWidgets('not_found says the child is gone and goes back to the '
      'choice with the children refreshed', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await linkCode(tester, answer: (_) => problem(404, 'not_found'));
    final reads = h.calls.where((c) => c == 'GET /v1/family').length;

    await generate(tester);

    expect(find.text(Copy.childGone), findsOneWidget);
    expect(tester.getSemantics(choice('Téo')), chosen('Téo', false));
    expect(
      h.calls.where((c) => c == 'GET /v1/family').length,
      greaterThan(reads),
    );
    semantics.dispose();
  });

  testWidgets('leaving the screen sends nothing: the code simply expires', (
    tester,
  ) async {
    final h = await linkCode(tester);
    await generate(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/modo-crianca');
    expect(h.actions, ['$post {"minor_id":"m2"}']);
  });
}
