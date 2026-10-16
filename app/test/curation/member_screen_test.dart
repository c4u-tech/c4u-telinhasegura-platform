import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/curator_form.dart';
import 'package:telinha_segura/curation/member_screen.dart';
import 'package:telinha_segura/curation/team_words.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'appoint_screen_test.dart' show confirmWith, declaration, tapOn, why;
import 'fixtures.dart';

const bia = 'bia@example.com';

/// bia holding [roles], the curator's by default.
Map<String, Object?> biaWith([List<Map<String, Object?>>? roles]) =>
    memberOf('a2', bia, roles ?? [curatorRole()]);

Future<Harness> sheet(
  WidgetTester tester, {
  Map<String, Object?>? who,
  FutureOr<http.Response> Function()? list,
  FutureOr<http.Response> Function(http.Request)? revise,
  FutureOr<http.Response> Function(http.Request)? revoke,
  String id = 'a2',
  List<String> roles = const ['admin'],
}) async {
  final h =
      Harness(
          signedIn: true,
          api: adminApi(
            staff: list ?? () => staffList([selfMember, who ?? biaWith()]),
            revise: revise,
            revoke: revoke,
          ),
        )
        ..family = ownerFamily
        ..roles = roles;
  await h.pump(tester, initial: '/admin/equipe/$id');
  return h;
}

Finder get save => find.widgetWithText(FilledButton, 'Salvar alterações');
Finder quiet(String label) => find.widgetWithText(QuietAction, label);
Finder role(String label) => find.widgetWithText(SelectableRow, label);

bool waits(WidgetTester tester) =>
    tester.widget<FilledButton>(save).onPressed == null;

bool chosen(WidgetTester tester, String label) =>
    tester.widget<SelectableRow>(role(label)).selected;

String since(String at) => TeamWords.since(DateTime.parse(at), clock.now());

List<String> writes(Harness h) => h.actions
    .where((a) => a.startsWith('PATCH') || a.startsWith('POST'))
    .toList();

int teamReads(Harness h) =>
    h.actions.where((a) => a == 'GET /v1/admin/staff').length;

void main() {
  testWidgets('titled by the email, read plain; one section per role held '
      'with since when, in order: the curation with its roles, the '
      'checkbox, "Salvar alterações" waiting and the clay "Tirar da '
      'curadoria"; the moderation with the clay "Tirar da moderação"; the '
      'administration read-only', (tester) async {
    final semantics = tester.ensureSemantics();
    await sheet(
      tester,
      who: biaWith([adminRole(), curatorRole(), moderatorRole()]),
    );

    final layout = tester.widget<FieldLayout>(find.byType(FieldLayout));
    expect(layout.title, addressBreaks(bia));
    expect(layout.titleSemanticsLabel, bia);
    final order = [
      find.text('Curadoria'),
      find.text(since('2026-03-03T12:00:00Z')),
      role('Pedagogo(a)'),
      declaration,
      save,
      quiet('Tirar da curadoria'),
      find.text('Moderação'),
      find.text(since('2026-04-10T12:00:00Z')),
      quiet('Tirar da moderação'),
      find.text('Administração'),
      find.text(since('2026-01-01T12:00:00Z')),
      find.text(cliOnly),
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    expect(
      tester.getSemantics(find.text('Moderação')),
      isSemantics(label: 'Moderação', isHeader: true),
    );
    expect(chosen(tester, 'Pedagogo(a)'), isTrue);
    expect(tester.widget<DeclarationRow>(declaration).value, isTrue);
    expect(waits(tester), isTrue);
    expect(
      tester.widget<QuietAction>(quiet('Tirar da curadoria')).destructive,
      isTrue,
    );
    expect(
      tester.widget<QuietAction>(quiet('Tirar da moderação')).destructive,
      isTrue,
    );
    expect(find.textContaining('Nomear para'), findsNothing);
    semantics.dispose();
  });

  testWidgets('each role is a section like the held video\'s: its header '
      'a hairline above "Desde …", a whole xxl apart from the role before; '
      'the six roles under a muted, non-header "Papel na curadoria"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await sheet(
      tester,
      who: biaWith([adminRole(), curatorRole(), moderatorRole()]),
    );

    final hairlines = [
      for (final i in [
        for (var i = 0; i < find.byType(Divider).evaluate().length; i++) i,
      ])
        tester.getTopLeft(find.byType(Divider).at(i)).dy,
    ];
    for (final (area, at) in [
      ('Curadoria', '2026-03-03T12:00:00Z'),
      ('Moderação', '2026-04-10T12:00:00Z'),
      ('Administração', '2026-01-01T12:00:00Z'),
    ]) {
      final header = tester.getBottomLeft(find.text(area)).dy;
      final sinceTop = tester.getTopLeft(find.text(since(at))).dy;
      expect(
        hairlines.where((y) => y > header && y < sinceTop),
        hasLength(1),
        reason: 'a hairline under "$area"',
      );
    }
    for (final (before, area) in [
      (quiet('Tirar da curadoria'), 'Moderação'),
      (quiet('Tirar da moderação'), 'Administração'),
    ]) {
      expect(
        tester.getTopLeft(find.text(area)).dy - tester.getBottomLeft(before).dy,
        greaterThanOrEqualTo(Space.xxl),
        reason: '"$area" stands apart from the section before',
      );
    }

    final label = find.text('Papel na curadoria');
    expect(label, findsOneWidget);
    expect(find.text('Papel'), findsNothing);
    expect(
      tester.getTopLeft(label).dy,
      greaterThan(
        tester.getTopLeft(find.text(since('2026-03-03T12:00:00Z'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(label).dy,
      lessThan(tester.getTopLeft(role('Mãe ou pai')).dy),
    );
    expect(tester.getSemantics(label), isSemantics(isHeader: false));
    final style = tester.widget<Text>(label).style!;
    final heading = tester.widget<Text>(find.text('Curadoria')).style!;
    expect(style.fontSize!, lessThan(heading.fontSize!));
    final context = tester.element(label);
    expect(style.color, context.palette.muted);
    semantics.dispose();
  });

  for (final (held, lacking, papel) in [
    ('curator', 'Nomear para a moderação', 'moderacao'),
    ('moderator', 'Nomear para a curadoria', 'curadoria'),
  ]) {
    testWidgets('holding only $held, the sheet offers "$lacking", opening '
        'the appoint form filled in', (tester) async {
      final h = await sheet(
        tester,
        who: biaWith([held == 'curator' ? curatorRole() : moderatorRole()]),
      );

      expect(find.widgetWithText(DoorRow, lacking), findsOneWidget);
      await tapOn(tester, find.text(lacking));

      expect(
        h.location(tester),
        '/admin/equipe/nova?email=bia%40example.com&papel=$papel',
      );
      expect(find.text(bia), findsOneWidget, reason: 'the email filled in');
    });
  }

  testWidgets('the caller\'s own sheet shows the roles read-only, with no '
      'write and no appoint door', (tester) async {
    await sheet(
      tester,
      id: 'a',
      list: () => staffList([
        memberOf('a', 'ana@example.com', [
          adminRole(),
          curatorRole(role: 'pediatra'),
          moderatorRole(),
        ]),
      ]),
      roles: ['admin', 'curator', 'moderator'],
    );

    expect(find.text(ownRoles), findsOneWidget);
    expect(find.text('Curadoria'), findsOneWidget);
    expect(find.text('Pediatra, formação verificada'), findsOneWidget);
    expect(find.text('Moderação'), findsOneWidget);
    expect(find.text('Administração'), findsOneWidget);
    expect(find.byType(SelectableRow), findsNothing);
    expect(find.byType(DeclarationRow), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(QuietAction), findsNothing);
    expect(find.byType(DoorRow), findsNothing);
  });

  testWidgets('"Salvar alterações" to a parent or caregiver confirms with '
      '"Motivo", sends only the role and the reason, and shows the sheet '
      'again with a notice', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await sheet(
      tester,
      revise: (_) =>
          json(200, biaWith([curatorRole(role: 'cuidador', verified: false)])),
    );

    await tapOn(tester, role('Cuidador(a)'));
    expect(declaration, findsNothing);
    expect(waits(tester), isFalse);
    await tapOn(tester, save);

    final confirm = tester.widget<DestructiveConfirmation>(
      find.byType(DestructiveConfirmation),
    );
    expect(confirm.askReason, isTrue);
    expect(confirm.titleSemanticsLabel, contains(bia));
    expect(confirm.body.join(' '), contains('cuidador(a)'));
    expect(writes(h), isEmpty);
    await confirmWith(tester, 'Salvar alterações');

    expect(writes(h), [
      'PATCH /v1/admin/staff/a2/curator '
          '{"display_role":"cuidador","reason":"$why"}',
    ]);
    expect(h.location(tester), '/admin/equipe/a2');
    expect(
      find.widgetWithText(Notice, saved(addressBreaks(bia), 'cuidador(a)')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(saved(bia, 'cuidador(a)')), findsOneWidget);
    expect(chosen(tester, 'Cuidador(a)'), isTrue);
    expect(waits(tester), isTrue, reason: 'as saved, nothing to save');
    semantics.dispose();
  });

  testWidgets('to another professional role, the affirmation is asked '
      'again and sent in the same save', (tester) async {
    final h = await sheet(
      tester,
      revise: (_) => json(200, biaWith([curatorRole(role: 'psicologo')])),
    );

    await tapOn(tester, role('Psicólogo(a)'));
    expect(tester.widget<DeclarationRow>(declaration).value, isFalse);
    expect(waits(tester), isTrue);
    expect(find.text(affirmHint), findsOneWidget);
    await tapOn(tester, declaration);
    await tapOn(tester, save);
    await confirmWith(tester, 'Salvar alterações');

    expect(writes(h), [
      'PATCH /v1/admin/staff/a2/curator {"display_role":"psicologo",'
          '"verified_professional":true,"reason":"$why"}',
    ]);
    expect(
      find.widgetWithText(
        Notice,
        saved(addressBreaks(bia), 'psicólogo(a)', verified: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('back to the role as it stands, nothing is left to save', (
    tester,
  ) async {
    await sheet(tester);

    await tapOn(tester, role('Pediatra'));
    await tapOn(tester, role('Pedagogo(a)'));

    expect(tester.widget<DeclarationRow>(declaration).value, isTrue);
    expect(waits(tester), isTrue);
    expect(find.text(unchangedHint), findsOneWidget);
  });

  testWidgets('a professional not yet verified sends only the affirmation', (
    tester,
  ) async {
    final h = await sheet(
      tester,
      who: biaWith([curatorRole(role: 'pediatra', verified: false)]),
    );

    expect(waits(tester), isTrue);
    await tapOn(tester, declaration);
    await tapOn(tester, save);
    await confirmWith(tester, 'Salvar alterações');

    expect(writes(h), [
      'PATCH /v1/admin/staff/a2/curator '
          '{"verified_professional":true,"reason":"$why"}',
    ]);
  });

  testWidgets('a displayed role the app does not know is no choice, and is '
      'never sent back', (tester) async {
    await sheet(tester, who: biaWith([curatorRole(role: 'astronauta')]));

    final rows = tester.widgetList<SelectableRow>(find.byType(SelectableRow));
    expect(rows.where((r) => r.selected), isEmpty);
    expect(waits(tester), isTrue);
    expect(find.text(chooseRoleHint), findsOneWidget);
  });

  testWidgets('"Tirar da curadoria" confirms with today\'s consequence and '
      '"Motivo", revokes once with the reason trimmed; with a role left, '
      'the sheet shows again with a notice', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await sheet(
      tester,
      who: biaWith([curatorRole(), moderatorRole()]),
      revoke: (_) => json(200, biaWith([moderatorRole()])),
    );

    await tapOn(tester, quiet('Tirar da curadoria'));

    final confirm = tester.widget<DestructiveConfirmation>(
      find.byType(DestructiveConfirmation),
    );
    expect(confirm.askReason, isTrue);
    expect(confirm.title, 'Tirar ${addressBreaks(bia)} da curadoria?');
    expect(confirm.titleSemanticsLabel, 'Tirar $bia da curadoria?');
    expect(confirm.body.join(' '), contains('deixam de contar'));
    expect(confirm.body.join(' '), contains('continuam no histórico'));
    expect(writes(h), isEmpty);
    await confirmWith(tester, 'Tirar da curadoria');

    expect(writes(h), [
      'POST /v1/admin/staff/a2/roles/curator/revoke {"reason":"$why"}',
    ]);
    expect(h.location(tester), '/admin/equipe/a2');
    expect(
      find.widgetWithText(Notice, leftArea(addressBreaks(bia), 'curadoria')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(leftArea(bia, 'curadoria')), findsOneWidget);
    expect(save, findsNothing);
    expect(
      find.widgetWithText(DoorRow, 'Nomear para a curadoria'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('"Tirar da moderação" confirms that videos are no longer '
      'removed or reopened; the last role gone, the list says "saiu da '
      'equipe"', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await sheet(
      tester,
      who: biaWith([moderatorRole()]),
      revoke: (_) => json(200, biaWith([])),
    );

    await tapOn(tester, quiet('Tirar da moderação'));

    final confirm = tester.widget<DestructiveConfirmation>(
      find.byType(DestructiveConfirmation),
    );
    expect(confirm.title, 'Tirar ${addressBreaks(bia)} da moderação?');
    expect(confirm.body.join(' '), contains('vídeos retidos'));
    await confirmWith(tester, 'Tirar da moderação');

    expect(writes(h), [
      'POST /v1/admin/staff/a2/roles/moderator/revoke {"reason":"$why"}',
    ]);
    expect(h.location(tester), '/admin/equipe');
    expect(
      find.widgetWithText(Notice, leftTeam(addressBreaks(bia))),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(leftTeam(bia)), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    final h = await sheet(tester);

    await tapOn(tester, quiet('Tirar da curadoria'));
    await tapOn(tester, find.text('Cancelar'));

    expect(find.byType(DestructiveConfirmation), findsNothing);
    expect(writes(h), isEmpty);
    expect(h.location(tester), '/admin/equipe/a2');
  });

  testWidgets('reauth_required asks to confirm it is you, then retries the '
      'removal once (staff screens Security)', (tester) async {
    var confirmed = false;
    final h =
        Harness(
            signedIn: true,
            api: (req) {
              if (req.url.path == '/v1/session/reauth') {
                confirmed = true;
                return http.Response('', 204);
              }
              return adminApi(
                staff: () => staffList([biaWith()]),
                revoke: (_) => confirmed
                    ? json(200, biaWith([]))
                    : problem(403, 'reauth_required'),
              )(req);
            },
          )
          ..family = ownerFamily
          ..roles = ['admin'];
    await h.pump(tester, initial: '/admin/equipe/a2');

    await tapOn(tester, quiet('Tirar da curadoria'));
    await confirmWith(tester, 'Tirar da curadoria');
    expect(find.byType(ReauthPrompt), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'uma senha longa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(writes(h).map((a) => a.split(' {').first), [
      'POST /v1/admin/staff/a2/roles/curator/revoke',
      'POST /v1/session/reauth',
      'POST /v1/admin/staff/a2/roles/curator/revoke',
    ]);
    expect(h.location(tester), '/admin/equipe');
  });

  testWidgets('someone no longer on the team goes back to the list with a '
      'notice', (tester) async {
    final h = await sheet(tester, list: () => staffList([selfMember]));

    expect(h.location(tester), '/admin/equipe');
    expect(find.widgetWithText(Notice, memberGone), findsOneWidget);
  });

  for (final (what, call) in [('saving', 'revise'), ('removing', 'revoke')]) {
    testWidgets('not_found while $what goes back to the list, read again, '
        'with a notice', (tester) async {
      final gone = problem(404, 'not_found');
      final h = await sheet(
        tester,
        revise: call == 'revise' ? (_) => gone : null,
        revoke: call == 'revoke' ? (_) => gone : null,
      );

      if (call == 'revise') {
        await tapOn(tester, role('Mãe ou pai'));
        await tapOn(tester, save);
        await confirmWith(tester, 'Salvar alterações');
      } else {
        await tapOn(tester, quiet('Tirar da curadoria'));
        await confirmWith(tester, 'Tirar da curadoria');
      }

      expect(h.location(tester), '/admin/equipe');
      expect(find.widgetWithText(Notice, memberGone), findsOneWidget);
      expect(teamReads(h), 2);
    });
  }

  testWidgets('while it loads, the placeholder says what is loading; a '
      'failed read offers "Tentar de novo"', (tester) async {
    final semantics = tester.ensureSemantics();
    final answer = Completer<http.Response>();
    var fail = true;
    await sheet(
      tester,
      list: () => answer.isCompleted
          ? (fail ? problem(503, 'unavailable') : staffList([biaWith()]))
          : answer.future,
    );

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando essa pessoa'), findsOneWidget);
    answer.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(save, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('back goes to the team', (tester) async {
    final h = await sheet(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/admin/equipe');
  });

  testWidgets('not_admin goes home with a notice', (tester) async {
    final h = await sheet(tester, revise: (_) => problem(403, 'not_admin'));

    await tapOn(tester, role('Mãe ou pai'));
    await tapOn(tester, save);
    await confirmWith(tester, 'Salvar alterações');

    expect(h.location(tester), '/');
    expect(
      find.text('Você não tem mais acesso à administração.'),
      findsOneWidget,
    );
  });
}
