import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/sessions_screen.dart'
    show sessionLastUse;
import 'package:telinha_segura/curation/member_screen.dart';
import 'package:telinha_segura/curation/words.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/staff/account_words.dart';
import 'package:telinha_segura/staff/audit_row.dart';

import '../access/harness.dart';
import '../curation/fixtures.dart';
import '../family/fixtures.dart';
import 'account_search_screen_test.dart' show fill, press;
import 'on_demand_test.dart' show confirmWith, confirming, tapOn, why;
import 'accounts_api_test.dart' show actionJson, sheetJson;

const masked = 'b•••@e•••.com';

/// The directory's requests among those sent.
List<String> directory(Harness h) => [
  for (final c in h.actions)
    if (c.startsWith('POST /v1/admin/accounts')) c,
];

/// [sheetJson] with [changes].
Map<String, Object?> sheetWith([Map<String, Object?> changes = const {}]) => {
  ...sheetJson,
  ...changes,
};

/// Ana, an admin, searched [sheet] (the lookup's answer) and reads it;
/// [support] answers the sheet's actions, [api] wraps the whole.
Future<Harness> sheetOf(
  WidgetTester tester, {
  Map<String, Object?>? sheet,
  FutureOr<http.Response> Function(http.Request)? support,
  FutureOr<http.Response>? Function(http.Request)? answer,
  Size size = const Size(390, 844),
}) async {
  final admin = adminApi(
    lookup: (_) => json(200, sheet ?? sheetJson),
    support: support,
  );
  final h =
      Harness(signedIn: true, api: (req) => answer?.call(req) ?? admin(req))
        ..family = ownerFamily
        ..roles = ['admin'];
  await h.pump(tester, initial: '/admin/contas', size: size);
  await fill(tester);
  await press(tester);
  return h;
}

Finder quiet(String label) => find.widgetWithText(QuietAction, label);

DateTime at(String iso) => DateTime.parse(iso);

/// A second device, linked a day after d1.
const d2 = {
  'id': 'd2',
  'linked_at': '2026-10-03T12:00:00Z',
  'last_seen_at': '2026-10-07T11:00:00Z',
};

/// A sheet tall enough to put Sessões below the first viewport: two
/// devices and three sessions.
Map<String, Object?> tallSheet() {
  final session = (sheetJson['sessions']! as List).single;
  return sheetWith({
    'family': {'role': 'owner', 'minors': 2, 'devices': 2},
    'devices': [(sheetJson['devices']! as List).single, d2],
    'sessions': [session, session, session],
  });
}

/// Expects [outcome] on screen, below the header [section] and above
/// [next] (null for the last section).
void expectBeside(
  WidgetTester tester,
  Finder outcome, {
  required String section,
  String? next,
}) {
  expect(outcome.hitTestable(), findsOneWidget, reason: '$outcome on screen');
  final top = tester.getTopLeft(outcome).dy;
  expect(top, greaterThan(tester.getBottomLeft(find.text(section)).dy));
  if (next != null) {
    expect(top, lessThan(tester.getTopLeft(find.text(next)).dy));
  }
}

void main() {
  testWidgets('"Conta", the masked email, then Acesso, Família, '
      'Aparelhos, Sessões and Ações da equipe, each a header, in that '
      'order, with their content', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await sheetOf(tester);
    final now = clock.now();

    expect(h.location(tester), '/admin/contas/a2');
    expect(find.text('Conta'), findsWidgets);
    final email = find.text(addressBreaks(masked));
    expect(tester.getSemantics(email), isSemantics(label: masked));
    final order = [
      email,
      find.text('Acesso'),
      find.text('E-\u2060mail confirmado'),
      find.text('Entra com Senha${CurationWords.dot}Google'),
      find.text(AccountWords.created(at('2026-10-01T12:00:00Z'))),
      find.text('Verificação em duas etapas não ativada'),
      find.widgetWithText(DoorRow, 'Na equipe'),
      quiet('Enviar redefinição de senha'),
      find.text('Família'),
      find.text('Responsável principal'),
      find.text('2 crianças${CurationWords.dot}1 aparelho ativo'),
      find.text('Aparelhos'),
      find.text(AccountWords.linked(at('2026-10-02T12:00:00Z'), now)),
      find.text(AccountWords.seen(at('2026-10-08T11:00:00Z'), now)),
      quiet('Desvincular'),
      find.text('Sessões'),
      find.text('Navegador'),
      find.text(AccountWords.started(at('2026-10-08T10:00:00Z'), now)),
      find.text(sessionLastUse(at('2026-10-08T11:30:00Z'), now)),
      quiet('Encerrar todas as sessões'),
      find.text('Ações da equipe'),
      find.byType(AuditActionRow),
    ];
    for (final f in order) {
      expect(f, findsOneWidget, reason: '$f');
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    for (final header in [
      'Acesso',
      'Família',
      'Aparelhos',
      'Sessões',
      'Ações da equipe',
    ]) {
      expect(
        tester.getSemantics(find.text(header)),
        isSemantics(label: header, isHeader: true),
      );
    }
    expect(
      find.descendant(
        of: find.widgetWithText(DoorRow, 'Na equipe'),
        matching: find.text('Curadoria'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<QuietAction>(quiet('Enviar redefinição de senha')),
      isA<QuietAction>().having((q) => q.destructive, 'destructive', false),
    );
    for (final clay in ['Desvincular', 'Encerrar todas as sessões']) {
      expect(tester.widget<QuietAction>(quiet(clay)).destructive, isTrue);
    }
    expect(
      find.text('Suas sessões e aparelhos ficam em Sua conta.'),
      findsNothing,
    );
    // Nothing on it but the masked address.
    expect(find.textContaining('bia@example.com'), findsNothing);
    // The answer was all the sheet needed.
    expect(directory(h), hasLength(1));
    semantics.dispose();
  });

  testWidgets('"Na equipe" opens the member\'s sheet; back finds the '
      'account\'s sheet as it was, no lookup again', (tester) async {
    final h = await sheetOf(tester);

    await tester.ensureVisible(find.text('Na equipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Na equipe'));
    await tester.pumpAndSettle();

    // Pushed over the sheet: the member's sheet on top.
    expect(find.byType(MemberScreen), findsOneWidget);
    expect(h.actions, contains('GET /v1/admin/staff'));
    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(find.byType(MemberScreen), findsNothing);
    expect(h.location(tester), '/admin/contas/a2');
    expect(find.text('Acesso'), findsOneWidget);
    expect(find.text(addressBreaks(masked)), findsOneWidget);
    expect(directory(h), hasLength(1));
  });

  testWidgets('the roles held read joined by the dot', (tester) async {
    await sheetOf(
      tester,
      sheet: sheetWith({
        'roles': ['admin', 'curator'],
      }),
    );

    expect(
      find.text(CurationWords.joined(['Administração', 'Curadoria'])),
      findsOneWidget,
    );
  });

  testWidgets('every line of Acesso and Sessões reads body-large, the '
      'last use muted', (tester) async {
    await sheetOf(tester);
    final now = clock.now();
    final text = Theme.of(tester.element(find.text('Acesso'))).textTheme;

    for (final line in [
      'E-\u2060mail confirmado',
      'Entra com Senha${CurationWords.dot}Google',
      AccountWords.created(at('2026-10-01T12:00:00Z')),
      'Verificação em duas etapas não ativada',
      'Navegador',
      AccountWords.started(at('2026-10-08T10:00:00Z'), now),
    ]) {
      expect(
        tester.widget<Text>(find.text(line)).style?.fontSize,
        text.bodyLarge?.fontSize,
        reason: line,
      );
    }
    expect(
      tester
          .widget<Text>(
            find.text(sessionLastUse(at('2026-10-08T11:30:00Z'), now)),
          )
          .style
          ?.fontSize,
      text.bodyMedium?.fontSize,
    );
  });

  testWidgets('each "Desvincular" reads which device it unlinks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await sheetOf(tester, sheet: tallSheet());
    final now = clock.now();

    final buttons = find.descendant(
      of: quiet('Desvincular'),
      matching: find.byType(TextButton),
    );
    expect(buttons, findsNWidgets(2));
    for (final (i, linked) in [
      '2026-10-02T12:00:00Z',
      '2026-10-03T12:00:00Z',
    ].indexed) {
      expect(
        tester.getSemantics(buttons.at(i)),
        isSemantics(
          label:
              'Desvincular o aparelho vinculado em '
              '${AccountWords.moment(at(linked), now)}',
          isButton: true,
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets('without a role, a family, sessions or actions: no door, '
      '"Sem família." and no Aparelhos, "Nenhuma sessão ativa." with no '
      'action, "Nenhuma ação da equipe sobre esta conta."', (tester) async {
    await sheetOf(
      tester,
      sheet: sheetWith({
        'email_verified': false,
        'mfa_enrolled': true,
        'roles': <Object>[],
        'family': null,
        'devices': <Object>[],
        'sessions': <Object>[],
        'actions': <Object>[],
      }),
    );

    expect(find.text('E-\u2060mail não confirmado'), findsOneWidget);
    expect(find.text('Verificação em duas etapas ativada'), findsOneWidget);
    expect(find.text('Na equipe'), findsNothing);
    expect(find.text('Sem família.'), findsOneWidget);
    expect(find.text('Aparelhos'), findsNothing);
    expect(find.text('Nenhuma sessão ativa.'), findsOneWidget);
    expect(find.text('Encerrar todas as sessões'), findsNothing);
    expect(
      find.text('Nenhuma ação da equipe sobre esta conta.'),
      findsOneWidget,
    );
    expect(find.byType(AuditActionRow), findsNothing);
    expect(quiet('Enviar redefinição de senha'), findsOneWidget);
  });

  testWidgets('a family with no device says so', (tester) async {
    await sheetOf(tester, sheet: sheetWith({'devices': <Object>[]}));

    expect(find.text('Aparelhos'), findsOneWidget);
    expect(find.text('Nenhum aparelho vinculado.'), findsOneWidget);
    expect(find.text('Desvincular'), findsNothing);
  });

  testWidgets('every action about the account, newest first, as Auditoria '
      'rows', (tester) async {
    await sheetOf(
      tester,
      sheet: sheetWith({
        'actions': [
          {...actionJson, 'id': 2, 'event': 'account_sessions_revoked'},
          actionJson,
        ],
      }),
    );

    expect(find.byType(AuditActionRow), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Sessões encerradas')).dy,
      lessThan(tester.getTopLeft(find.text('Conta buscada')).dy),
    );
  });

  testWidgets('the caller\'s own sheet offers no support action and says '
      'where they live', (tester) async {
    await sheetOf(tester, sheet: sheetWith({'account_id': 'a'}));

    expect(
      find.text('Suas sessões e aparelhos ficam em Sua conta.'),
      findsOneWidget,
    );
    for (final action in [
      'Enviar redefinição de senha',
      'Desvincular',
      'Encerrar todas as sessões',
    ]) {
      expect(find.text(action), findsNothing, reason: action);
    }
    expect(find.text('Navegador'), findsOneWidget);
  });

  group('the support actions', () {
    const reset = '/v1/admin/accounts/a2/password-reset';
    const unlink = '/v1/admin/accounts/a2/devices/d1/unlink';
    const revoke = '/v1/admin/accounts/a2/sessions/revoke';

    // Each action: its quiet action, the confirmation's title (as shown
    // and as read), its consequence, its primary, the route, and the
    // notice after.
    final actions = [
      (
        quiet: 'Enviar redefinição de senha',
        title: 'Enviar uma redefinição de senha para ${addressBreaks(masked)}?',
        read: 'Enviar uma redefinição de senha para $masked?',
        body:
            'Chega um link válido por 30 minutos no e-\u2060mail da conta. A '
            'senha só muda se a pessoa usar o link.',
        path: reset,
        done: 'Redefinição de senha enviada.',
      ),
      (
        quiet: 'Desvincular',
        title: 'Desvincular este aparelho?',
        read: 'Desvincular este aparelho?',
        body:
            'Ele deixa de ser um aparelho da família e sai do modo criança na '
            'próxima vez que for usado. Para usar de novo, a família gera '
            'outro código.',
        path: unlink,
        done: 'Aparelho desvinculado.',
      ),
      (
        quiet: 'Encerrar todas as sessões',
        title: 'Encerrar a sessão desta conta?',
        read: 'Encerrar a sessão desta conta?',
        body:
            'A pessoa sai da conta em todos os aparelhos e precisa entrar de '
            'novo. Os aparelhos vinculados das crianças continuam '
            'funcionando.',
        path: revoke,
        done: 'Sessões encerradas.',
      ),
    ];

    for (final a in actions) {
      testWidgets('"${a.quiet}" confirms full screen with its consequence '
          'and Motivo, then sends the reason and shows the refreshed sheet '
          'with "${a.done}"', (tester) async {
        final h = await sheetOf(tester);

        await tapOn(tester, quiet(a.quiet));
        final confirmation = tester.widget<DestructiveConfirmation>(
          find.byType(DestructiveConfirmation),
        );
        expect(confirmation.title, a.title);
        expect(confirmation.titleSemanticsLabel ?? a.title, a.read);
        expect(confirmation.body, [a.body]);
        expect(confirmation.askReason, isTrue);
        expect(confirmation.action, a.quiet);
        expect(
          tester.widget<FilledButton>(confirming(a.quiet)).onPressed,
          isNull,
        );

        await confirmWith(tester, a.quiet);

        expect(directory(h).skip(1), ['POST ${a.path} {"reason":"$why"}']);
        expect(find.byType(DestructiveConfirmation), findsNothing);
        expect(find.widgetWithText(Notice, a.done), findsOneWidget);
        expect(h.location(tester), '/admin/contas/a2');
        expect(find.byType(ErrorNote), findsNothing);
      });

      testWidgets('"${a.quiet}" cancelled changes nothing', (tester) async {
        final h = await sheetOf(tester);

        await tapOn(tester, quiet(a.quiet));
        await tapOn(tester, find.text('Cancelar'));

        expect(find.byType(DestructiveConfirmation), findsNothing);
        expect(directory(h), hasLength(1));
        expect(find.byType(Notice), findsNothing);
        expect(quiet(a.quiet), findsOneWidget);
      });

      testWidgets('"${a.quiet}" refused with reauth_required asks to confirm '
          'it is you, then sends it once more with the same reason', (
        tester,
      ) async {
        var confirmed = false;
        final h = await sheetOf(
          tester,
          answer: (req) {
            if (req.url.path == '/v1/session/reauth') {
              confirmed = true;
              return http.Response('', 204);
            }
            if (req.url.path == a.path && !confirmed) {
              return problem(403, 'reauth_required');
            }
            return null;
          },
        );

        await tapOn(tester, quiet(a.quiet));
        await confirmWith(tester, a.quiet);
        expect(find.byType(ReauthPrompt), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'uma senha longa');
        await tester.pumpAndSettle();
        await tapOn(tester, find.text('Confirmar'));

        expect(
          [
            for (final c in h.actions)
              if (c.startsWith('POST ${a.path}') ||
                  c.startsWith('POST /v1/session/reauth'))
                c.split(' {').first,
          ],
          ['POST ${a.path}', 'POST /v1/session/reauth', 'POST ${a.path}'],
        );
        expect(directory(h).skip(1).toSet(), {
          'POST ${a.path} {"reason":"$why"}',
        });
        expect(find.widgetWithText(Notice, a.done), findsOneWidget);
      });
    }

    for (final (label, section, next, after) in [
      (
        'Enviar redefinição de senha',
        'Acesso',
        'Família',
        'Redefinição de senha enviada.',
      ),
      (
        'Encerrar todas as sessões',
        'Sessões',
        'Ações da equipe',
        'Sessões encerradas.',
      ),
    ]) {
      testWidgets('"$label"\'s outcome shows under it, where it was pressed', (
        tester,
      ) async {
        await sheetOf(tester, sheet: tallSheet());

        await tapOn(tester, quiet(label));
        await confirmWith(tester, label);

        expectBeside(
          tester,
          find.widgetWithText(Notice, after),
          section: section,
          next: next,
        );
      });
    }

    testWidgets('an unlink\'s outcome shows where that device stood', (
      tester,
    ) async {
      final sheet = tallSheet();
      await sheetOf(
        tester,
        sheet: sheet,
        support: (_) => json(200, {
          ...sheet,
          'devices': [(sheetJson['devices']! as List).single],
        }),
      );

      await tapOn(tester, quiet('Desvincular').last);
      await confirmWith(tester, 'Desvincular');

      expectBeside(
        tester,
        find.widgetWithText(Notice, 'Aparelho desvinculado.'),
        section: 'Aparelhos',
        next: 'Sessões',
      );
    });

    testWidgets('an unlink\'s outcome stands in its own row, a hairline '
        'apart from the next device', (tester) async {
      final sheet = tallSheet();
      await sheetOf(
        tester,
        sheet: sheet,
        support: (_) => json(200, {
          ...sheet,
          'devices': [d2],
        }),
      );

      await tapOn(tester, quiet('Desvincular').first);
      await confirmWith(tester, 'Desvincular');

      final notice = find.widgetWithText(Notice, 'Aparelho desvinculado.');
      expect(notice.hitTestable(), findsOneWidget);
      final noticeBottom = tester.getBottomLeft(notice).dy;
      final nextTop = tester
          .getTopLeft(find.textContaining('Vinculado em').first)
          .dy;
      final dividers = find.byType(Divider);
      final hairlines = [
        for (var i = 0; i < dividers.evaluate().length; i++)
          tester.getTopLeft(dividers.at(i)).dy,
      ];
      expect(
        hairlines.any((y) => y > noticeBottom && y < nextTop),
        isTrue,
        reason: 'a hairline between the notice and the device left',
      );
    });

    testWidgets('a failed write\'s note shows under the action that failed', (
      tester,
    ) async {
      await sheetOf(
        tester,
        sheet: tallSheet(),
        support: (_) => throw http.ClientException('offline'),
      );

      await tapOn(tester, quiet('Encerrar todas as sessões'));
      await confirmWith(tester, 'Encerrar todas as sessões');

      expectBeside(
        tester,
        find.byType(ErrorNote),
        section: 'Sessões',
        next: 'Ações da equipe',
      );
    });

    testWidgets('a cancelled re-authentication changes nothing', (
      tester,
    ) async {
      final h = await sheetOf(
        tester,
        support: (_) => problem(403, 'reauth_required'),
      );

      await tapOn(tester, quiet('Encerrar todas as sessões'));
      await confirmWith(tester, 'Encerrar todas as sessões');
      expect(find.byType(ReauthPrompt), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(directory(h), hasLength(2));
      expect(find.byType(ErrorNote), findsNothing);
      expect(find.byType(Notice), findsNothing);
      expect(find.text('Navegador'), findsOneWidget);
      expect(h.location(tester), '/admin/contas/a2');
    });

    testWidgets('ending 3 sessions says how many; the sheet comes back '
        'without them', (tester) async {
      final session = (sheetJson['sessions']! as List).single;
      await sheetOf(
        tester,
        sheet: sheetWith({
          'sessions': [session, session, session],
        }),
      );

      await tapOn(tester, quiet('Encerrar todas as sessões'));
      expect(
        tester
            .widget<DestructiveConfirmation>(
              find.byType(DestructiveConfirmation),
            )
            .title,
        'Encerrar as 3 sessões desta conta?',
      );
      await confirmWith(tester, 'Encerrar todas as sessões');

      expect(find.text('Navegador'), findsNothing);
      expect(find.text('Nenhuma sessão ativa.'), findsOneWidget);
      expect(find.text('Encerrar todas as sessões'), findsNothing);
    });

    testWidgets('account_not_found goes to the search with "Essa conta não '
        'existe mais."', (tester) async {
      final h = await sheetOf(
        tester,
        support: (_) => problem(404, 'account_not_found'),
      );

      await tapOn(tester, quiet('Desvincular'));
      await confirmWith(tester, 'Desvincular');

      expect(h.location(tester), '/admin/contas');
      expect(
        find.widgetWithText(Notice, 'Essa conta não existe mais.'),
        findsOneWidget,
      );
    });

    testWidgets('device_not_found keeps the sheet with its notice, that '
        'device gone from it without a lookup again', (tester) async {
      final h = await sheetOf(
        tester,
        sheet: tallSheet(),
        support: (_) => problem(404, 'device_not_found'),
      );
      final now = clock.now();

      await tapOn(tester, quiet('Desvincular').first);
      await confirmWith(tester, 'Desvincular');

      expect(h.location(tester), '/admin/contas/a2');
      final notice = find.widgetWithText(
        Notice,
        'Esse aparelho já não está nessa família.',
      );
      expect(notice, findsOneWidget);
      expect(find.byType(ErrorNote), findsNothing);
      expect(
        find.text(AccountWords.linked(at('2026-10-02T12:00:00Z'), now)),
        findsNothing,
      );
      expect(
        find.text(AccountWords.linked(at('2026-10-03T12:00:00Z'), now)),
        findsOneWidget,
      );
      expect(quiet('Desvincular'), findsOneWidget);
      expect(
        find.text('2 crianças${CurationWords.dot}1 aparelho ativo'),
        findsOneWidget,
      );
      expectBeside(tester, notice, section: 'Aparelhos', next: 'Sessões');
      expect(directory(h).skip(1), ['POST $unlink {"reason":"$why"}']);
    });

    testWidgets('the reset\'s rate_limited keeps the sheet with the refusal '
        'naming the minutes, under the reset', (tester) async {
      final h = await sheetOf(
        tester,
        support: (_) => problem(429, 'rate_limited', retryAfterBody: 2390),
      );

      await tapOn(tester, quiet('Enviar redefinição de senha'));
      await confirmWith(tester, 'Enviar redefinição de senha');

      expect(h.location(tester), '/admin/contas/a2');
      final refusal = find.widgetWithText(
        ErrorNote,
        'Já foram 3 redefinições nesta hora. Tente de novo em 40\u00A0min.',
      );
      expect(refusal, findsOneWidget);
      expect(find.byType(Notice), findsNothing);
      expectBeside(tester, refusal, section: 'Acesso', next: 'Família');
      expect(
        tester
            .widget<QuietAction>(quiet('Enviar redefinição de senha'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('not_admin goes home with today\'s notice', (tester) async {
      final h = await sheetOf(
        tester,
        support: (_) => problem(403, 'not_admin'),
      );

      await tapOn(tester, quiet('Encerrar todas as sessões'));
      await confirmWith(tester, 'Encerrar todas as sessões');

      expect(h.location(tester), '/');
      expect(
        find.text('Você não tem mais acesso à administração.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed request shows the error note, the sheet as it '
        'was', (tester) async {
      final h = await sheetOf(
        tester,
        support: (_) => throw http.ClientException('offline'),
      );

      await tapOn(tester, quiet('Desvincular'));
      await confirmWith(tester, 'Desvincular');

      expect(h.location(tester), '/admin/contas/a2');
      expect(find.byType(ErrorNote), findsOneWidget);
      expect(quiet('Desvincular'), findsOneWidget);
      expect(find.byType(Notice), findsNothing);
    });

    testWidgets('while an action runs, its control shows the progress and '
        'the others wait', (tester) async {
      final answer = Completer<http.Response>();
      await sheetOf(tester, support: (_) => answer.future);

      await tapOn(tester, quiet('Desvincular'));
      await tester.enterText(find.widgetWithText(TextField, 'Motivo'), why);
      await tester.pump();
      // The progress turns until the answer: no settling before it.
      await tester.tap(confirming('Desvincular'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.widget<QuietAction>(quiet('Desvincular')).busy, isTrue);
      for (final other in [
        'Enviar redefinição de senha',
        'Encerrar todas as sessões',
      ]) {
        final q = tester.widget<QuietAction>(quiet(other));
        expect(q.busy, isFalse, reason: other);
        expect(q.onPressed, isNull, reason: other);
      }
      answer.complete(json(200, sheetJson));
      await tester.pumpAndSettle();
      expect(tester.widget<QuietAction>(quiet('Desvincular')).busy, isFalse);
    });
  });
}
