import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/staff/account_words.dart';

import '../access/harness.dart';
import 'account_sheet_screen_test.dart'
    show
        at,
        directory,
        expectBeside,
        masked,
        quiet,
        sheetOf,
        sheetWith,
        tallSheet;
import 'accounts_api_test.dart' show actionJson, sheetJson, suspensionJson;
import 'on_demand_test.dart' show confirmWith, confirming, tapOn, why;

const suspend = '/v1/admin/accounts/a2/suspend';
const reinstate = '/v1/admin/accounts/a2/reinstate';

/// The suspended standing as the suspension's answer reads it.
final since = AccountWords.suspendedSince(at(suspensionJson['since']!));
const quoted = '“Denuncia de conteudo improprio.”';

/// [sheetJson] suspended: no roles, no sessions, the standing.
Map<String, Object?> suspendedSheet([
  Map<String, Object?> changes = const {},
]) => sheetWith({
  'roles': <Object>[],
  'sessions': <Object>[],
  'suspension': suspensionJson,
  ...changes,
});

/// The suspension's and reinstatement's answers; [refuse] answers both
/// instead when given.
http.Response standing(http.Request req, {http.Response? refuse}) {
  if (refuse != null) return refuse;
  return req.url.path == suspend
      ? json(200, suspendedSheet())
      : json(200, sheetWith({'roles': <Object>[], 'suspension': null}));
}

DestructiveConfirmation confirmation(WidgetTester tester) => tester
    .widget<DestructiveConfirmation>(find.byType(DestructiveConfirmation));

/// The tops of [finders], which must each find one widget, in order.
void expectInOrder(WidgetTester tester, List<Finder> finders) {
  for (final f in finders) {
    expect(f, findsOneWidget, reason: '$f');
  }
  final tops = [for (final f in finders) tester.getTopLeft(f).dy];
  expect(tops, [...tops]..sort());
}

void main() {
  group('Situação', () {
    testWidgets('opens the sheet, a header above Acesso: "Conta ativa." '
        'while active, with no "Reativar conta"', (tester) async {
      final semantics = tester.ensureSemantics();
      await sheetOf(tester);

      expectInOrder(tester, [
        find.text(addressBreaks(masked)),
        find.text('Situação'),
        find.text('Conta ativa.'),
        find.text('Acesso'),
      ]);
      expect(
        tester.getSemantics(find.text('Situação')),
        isSemantics(label: 'Situação', isHeader: true),
      );
      expect(find.text('Reativar conta'), findsNothing);
      // The section's grammar: the standing between hairlines.
      expect(
        find.descendant(
          of: find.byType(Doors),
          matching: find.text('Conta ativa.'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('suspended: since when, local, the reason in quotes on '
        'its own line, then the ink "Reativar conta", all above Acesso', (
      tester,
    ) async {
      await sheetOf(tester, sheet: suspendedSheet());

      expect(since, startsWith('Suspensa desde 8 de outubro de 2026, '));
      expectInOrder(tester, [
        find.text('Situação'),
        find.text(since),
        find.text(quoted),
        quiet('Reativar conta'),
        find.text('Acesso'),
      ]);
      expect(find.text('Conta ativa.'), findsNothing);
      expect(
        tester.widget<QuietAction>(quiet('Reativar conta')).destructive,
        isFalse,
      );
      final text = Theme.of(tester.element(find.text(since))).textTheme;
      for (final line in [since, quoted]) {
        expect(
          tester.widget<Text>(find.text(line)).style?.fontSize,
          text.bodyLarge?.fontSize,
          reason: line,
        );
      }
      // Suspended, there is nothing to suspend.
      expect(find.text('Suspender conta'), findsNothing);
    });
  });

  group('the foot', () {
    testWidgets('active, not one\'s own, no admin role: the clay '
        '"Suspender conta" is the sheet\'s last thing, after Ações da '
        'equipe', (tester) async {
      final semantics = tester.ensureSemantics();
      await sheetOf(tester);

      final foot = quiet('Suspender conta');
      await tester.ensureVisible(foot);
      await tester.pumpAndSettle();
      expectInOrder(tester, [find.text('Ações da equipe'), foot]);
      expect(
        tester.getTopLeft(foot).dy,
        greaterThan(tester.getBottomLeft(find.text('Conta buscada')).dy),
      );
      expect(tester.widget<QuietAction>(foot).destructive, isTrue);
      final button = find.descendant(
        of: foot,
        matching: find.byType(TextButton),
      );
      expect(
        tester.getSemantics(button),
        isSemantics(label: 'Suspender conta', isButton: true),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(
        find.text('Uma conta com administração não é suspensa.'),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('holding the admin role: the muted line, no action', (
      tester,
    ) async {
      await sheetOf(
        tester,
        sheet: sheetWith({
          'roles': ['admin', 'curator'],
        }),
      );

      const line = 'Uma conta com administração não é suspensa.';
      await tester.ensureVisible(find.text(line));
      await tester.pumpAndSettle();
      expectInOrder(tester, [find.text('Ações da equipe'), find.text(line)]);
      final text = Theme.of(tester.element(find.text(line))).textTheme;
      final style = tester.widget<Text>(find.text(line)).style;
      expect(style?.fontSize, text.bodyMedium?.fontSize);
      expect(style?.color, isNot(text.bodyMedium?.color));
      expect(find.text('Suspender conta'), findsNothing);
    });

    for (final (label, sheet) in [
      ('active', sheetWith({'account_id': 'a'})),
      ('suspended', suspendedSheet({'account_id': 'a'})),
    ]) {
      testWidgets('on the caller\'s own sheet ($label): neither action, '
          'the own-sheet line', (tester) async {
        await sheetOf(tester, sheet: sheet);

        expect(find.text('Suspender conta'), findsNothing);
        expect(find.text('Reativar conta'), findsNothing);
        expect(
          find.text('Uma conta com administração não é suspensa.'),
          findsNothing,
        );
        expect(
          find.text('Suas sessões e aparelhos ficam em Sua conta.'),
          findsOneWidget,
        );
      });
    }
  });

  group('the confirmations', () {
    const consequence =
        'A pessoa sai de todos os aparelhos. Ao entrar de novo, só consegue '
        'baixar os dados, excluir a conta ou sair. A família e os aparelhos '
        'das crianças continuam funcionando.';
    const told = 'A pessoa recebe um e-⁠mail avisando, sem o motivo.';

    testWidgets('"Suspender conta" says the whole consequence, the roles '
        'in words when held, asks Motivo, then suspends with the reason', (
      tester,
    ) async {
      final h = await sheetOf(tester, support: standing);

      await tapOn(tester, quiet('Suspender conta'));
      final c = confirmation(tester);
      expect(c.title, 'Suspender a conta ${addressBreaks(masked)}?');
      expect(c.titleSemanticsLabel, 'Suspender a conta $masked?');
      expect(c.body, [
        consequence,
        'Ela também sai da equipe (Curadoria). Reativar a conta não devolve '
            'esses papéis.',
        told,
      ]);
      expect(c.askReason, isTrue);
      expect(c.action, 'Suspender conta');
      expect(
        tester.widget<FilledButton>(confirming('Suspender conta')).onPressed,
        isNull,
      );

      await confirmWith(tester, 'Suspender conta');

      expect(directory(h).skip(1), ['POST $suspend {"reason":"$why"}']);
      expect(find.byType(DestructiveConfirmation), findsNothing);
    });

    testWidgets('several roles read joined by the dot, in the app\'s order', (
      tester,
    ) async {
      await sheetOf(
        tester,
        sheet: sheetWith({
          'roles': ['moderator', 'curator'],
        }),
      );

      await tapOn(tester, quiet('Suspender conta'));
      expect(
        confirmation(tester).body[1],
        // Roles in words in prose, not the data rows' interpunct.
        'Ela também sai da equipe (Curadoria e Moderação). Reativar a '
        'conta não devolve esses papéis.',
      );
    });

    testWidgets('without a role, no roles line', (tester) async {
      await sheetOf(tester, sheet: sheetWith({'roles': <Object>[]}));

      await tapOn(tester, quiet('Suspender conta'));
      expect(confirmation(tester).body, [consequence, told]);
    });

    testWidgets('"Reativar conta" says the reinstatement\'s consequence, '
        'asks Motivo, then reinstates with the reason', (tester) async {
      final h = await sheetOf(
        tester,
        sheet: suspendedSheet(),
        support: standing,
      );

      await tapOn(tester, quiet('Reativar conta'));
      final c = confirmation(tester);
      expect(c.title, 'Reativar a conta ${addressBreaks(masked)}?');
      expect(c.titleSemanticsLabel, 'Reativar a conta $masked?');
      expect(c.body, [
        'A pessoa volta a usar a Telinha Segura normalmente, nos aparelhos '
            'em que já estiver. Os papéis na equipe não voltam: para isso, '
            'nomeie de novo em Equipe. A pessoa recebe um e-⁠mail '
            'avisando.',
      ]);
      expect(c.askReason, isTrue);
      expect(c.action, 'Reativar conta');

      await confirmWith(tester, 'Reativar conta');

      expect(directory(h).skip(1), ['POST $reinstate {"reason":"$why"}']);
    });

    for (final (label, sheet) in [
      ('Suspender conta', sheetJson),
      ('Reativar conta', suspendedSheet()),
    ]) {
      testWidgets('"$label" cancelled changes nothing', (tester) async {
        final h = await sheetOf(tester, sheet: sheet);

        await tapOn(tester, quiet(label));
        await tapOn(tester, find.text('Cancelar'));

        expect(find.byType(DestructiveConfirmation), findsNothing);
        expect(directory(h), hasLength(1));
        expect(find.byType(Notice), findsNothing);
        expect(quiet(label), findsOneWidget);
      });
    }

    testWidgets('a cancelled re-authentication changes nothing', (
      tester,
    ) async {
      final h = await sheetOf(
        tester,
        support: (_) => problem(403, 'reauth_required'),
      );

      await tapOn(tester, quiet('Suspender conta'));
      await confirmWith(tester, 'Suspender conta');
      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(directory(h), hasLength(2));
      expect(find.byType(Notice), findsNothing);
      expect(find.byType(ErrorNote), findsNothing);
      expect(find.text('Conta ativa.'), findsOneWidget);
    });
  });

  group('done', () {
    testWidgets('suspended: the answered sheet, "Conta suspensa." under '
        'Situação, brought into view from the foot', (tester) async {
      await sheetOf(tester, sheet: tallSheet(), support: standing);

      await tapOn(tester, quiet('Suspender conta'));
      await confirmWith(tester, 'Suspender conta');

      final notice = find.widgetWithText(Notice, 'Conta suspensa.');
      expectBeside(tester, notice, section: 'Situação', next: 'Acesso');
      // The notice comes with its evidence: the standing stays in view.
      expect(tester.getRect(find.text('Situação')).top, greaterThan(0));
      expect(find.text(since), findsOneWidget);
      expect(find.text(quoted), findsOneWidget);
      expect(find.text('Na equipe'), findsNothing);
      expect(find.text('Nenhuma sessão ativa.'), findsOneWidget);
      expect(find.text('Suspender conta'), findsNothing);
      expect(quiet('Reativar conta'), findsOneWidget);
      expect(find.byType(ErrorNote), findsNothing);
    });

    testWidgets('reinstated: "Conta ativa.", "Conta reativada." under '
        'Situação, the foot back', (tester) async {
      await sheetOf(tester, sheet: suspendedSheet(), support: standing);

      await tapOn(tester, quiet('Reativar conta'));
      await confirmWith(tester, 'Reativar conta');

      final notice = find.widgetWithText(Notice, 'Conta reativada.');
      expectBeside(tester, notice, section: 'Situação', next: 'Acesso');
      expect(tester.getRect(find.text('Situação')).top, greaterThan(0));
      expect(find.text('Conta ativa.'), findsOneWidget);
      expect(find.text(since), findsNothing);
      expect(find.text('Reativar conta'), findsNothing);
      expect(quiet('Suspender conta'), findsOneWidget);
    });
  });

  group('refusals, beside the action, never a second read', () {
    for (final (code, status, label, words, section) in [
      (
        'already_suspended',
        409,
        'Suspender conta',
        'Outra pessoa da equipe já suspendeu esta conta.',
        'Ações da equipe',
      ),
      (
        'subject_is_admin',
        409,
        'Suspender conta',
        'Essa conta tem administração e não é suspensa.',
        'Ações da equipe',
      ),
      (
        'not_suspended',
        409,
        'Reativar conta',
        'Outra pessoa da equipe já reativou esta conta.',
        'Situação',
      ),
    ]) {
      testWidgets('$code: "$words" under "$label"', (tester) async {
        final h = await sheetOf(
          tester,
          sheet: label == 'Reativar conta' ? suspendedSheet() : tallSheet(),
          support: (_) => problem(status, code),
        );

        await tapOn(tester, quiet(label));
        await confirmWith(tester, label);

        final note = find.widgetWithText(ErrorNote, words);
        expectBeside(
          tester,
          note,
          section: section,
          next: section == 'Situação' ? 'Acesso' : null,
        );
        expect(
          tester.getTopLeft(note).dy,
          greaterThan(tester.getBottomLeft(quiet(label)).dy),
        );
        expect(find.byType(Notice), findsNothing);
        expect(h.location(tester), '/admin/contas/a2');
        // The write, and nothing read after it.
        expect(directory(h), hasLength(2));
        expect(h.actions.last, startsWith('POST /v1/admin/accounts/a2/'));
      });
    }

    testWidgets('account_not_found goes to the search with "Essa conta '
        'não existe mais."', (tester) async {
      final h = await sheetOf(
        tester,
        support: (_) => problem(404, 'account_not_found'),
      );

      await tapOn(tester, quiet('Suspender conta'));
      await confirmWith(tester, 'Suspender conta');

      expect(h.location(tester), '/admin/contas');
      expect(
        find.widgetWithText(Notice, 'Essa conta não existe mais.'),
        findsOneWidget,
      );
    });

    testWidgets('not_admin goes home with today\'s notice', (tester) async {
      final h = await sheetOf(
        tester,
        sheet: suspendedSheet(),
        support: (_) => problem(403, 'not_admin'),
      );

      await tapOn(tester, quiet('Reativar conta'));
      await confirmWith(tester, 'Reativar conta');

      expect(h.location(tester), '/');
      expect(
        find.text('Você não tem mais acesso à administração.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed request: the error note under the action, the '
        'sheet as it was', (tester) async {
      await sheetOf(
        tester,
        sheet: suspendedSheet(),
        support: (_) => throw http.ClientException('offline'),
      );

      await tapOn(tester, quiet('Reativar conta'));
      await confirmWith(tester, 'Reativar conta');

      expectBeside(
        tester,
        find.byType(ErrorNote),
        section: 'Situação',
        next: 'Acesso',
      );
      expect(find.text(since), findsOneWidget);
      expect(quiet('Reativar conta'), findsOneWidget);
    });
  });

  testWidgets('the sheet\'s actions word the suspension\'s events', (
    tester,
  ) async {
    await sheetOf(
      tester,
      sheet: suspendedSheet({
        'actions': [
          for (final (i, event) in [
            'account_reinstated',
            'account_suspended',
          ].indexed)
            {...actionJson, 'id': i, 'event': event},
        ],
      }),
    );

    expect(find.text('Conta reativada'), findsOneWidget);
    expect(find.text('Conta suspensa'), findsOneWidget);
    expect(find.text(AccountWords.otherEvent), findsNothing);
  });
}
