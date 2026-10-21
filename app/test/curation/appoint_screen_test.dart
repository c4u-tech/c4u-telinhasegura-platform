import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/appoint_screen.dart';
import 'package:telinha_segura/curation/curator_form.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

const caio = 'caio@example.com';
const why = 'Entrou na equipe de revisão.';

Future<Harness> appointing(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? grant,
  String initial = '/admin/equipe/nova',
}) async {
  final h = Harness(signedIn: true, api: adminApi(grant: grant))
    ..family = ownerFamily
    ..roles = ['admin'];
  await h.pump(tester, initial: initial);
  return h;
}

Finder get emailField => find.widgetWithText(TextField, 'E-⁠mail');
Finder get proceed => find.widgetWithText(FilledButton, 'Continuar');
Finder get declaration => find.byType(DeclarationRow);
Finder row(String label) => find.widgetWithText(SelectableRow, label);

bool waits(WidgetTester tester) =>
    tester.widget<FilledButton>(proceed).onPressed == null;

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The confirmation's own [label] action, apart from the screen's.
Finder confirming(String label) => find.descendant(
  of: find.byType(DestructiveConfirmation),
  matching: find.widgetWithText(FilledButton, label),
);

/// Gives the open confirmation a reason (padded, to be sent trimmed) and
/// confirms it with [label].
Future<void> confirmWith(WidgetTester tester, String label) async {
  await tester.enterText(find.widgetWithText(TextField, 'Motivo'), '  $why ');
  await tester.pump();
  await tapOn(tester, confirming(label));
}

/// Fills the form: [email], the [papel] and, for the curation, the role
/// labelled [role] and, when [verified], the declaration.
Future<void> fill(
  WidgetTester tester, {
  String email = caio,
  String papel = 'Curadoria',
  String role = 'Mãe ou pai',
  bool verified = false,
}) async {
  await tester.enterText(emailField, email);
  await tester.pumpAndSettle();
  await tapOn(tester, row(papel));
  if (papel != 'Curadoria') return;
  await tapOn(tester, row(role));
  if (verified) await tapOn(tester, declaration);
}

/// Fills the form, continues and confirms with a reason.
Future<void> appoint(
  WidgetTester tester, {
  String papel = 'Curadoria',
  String role = 'Mãe ou pai',
  bool verified = false,
}) async {
  await fill(tester, papel: papel, role: role, verified: verified);
  await tapOn(tester, proceed);
  await confirmWith(tester, 'Nomear');
}

String fieldError(WidgetTester tester) =>
    tester.widget<TextField>(emailField).decoration!.errorText ?? '';

List<String> writes(Harness h) =>
    h.actions.where((a) => a.startsWith('POST /v1/admin')).toList();

void main() {
  testWidgets('asks for the email and "Papel" with "Curadoria" and '
      '"Moderação", none chosen; "Continuar" waits', (tester) async {
    await appointing(tester);

    expect(find.text('Nomear alguém'), findsOneWidget);
    expect(emailField, findsOneWidget);
    expect(find.text('Papel'), findsOneWidget);
    final rows = tester.widgetList<SelectableRow>(find.byType(SelectableRow));
    expect(
      [for (final r in rows) (r.label, r.detail)],
      [('Curadoria', curatorDetail), ('Moderação', moderatorDetail)],
    );
    expect(rows.where((r) => r.selected), isEmpty);
    expect(waits(tester), isTrue);
  });

  testWidgets('"Curadoria" shows the six displayed roles; a professional '
      'one asks the affirmation, which "Continuar" waits on', (tester) async {
    await appointing(tester);

    await fill(tester, role: 'Psicólogo(a)');
    final rows = tester.widgetList<SelectableRow>(find.byType(SelectableRow));
    expect(
      [for (final r in rows) r.label],
      [
        'Curadoria',
        'Moderação',
        'Mãe ou pai',
        'Cuidador(a)',
        'Pedagogo(a)',
        'Psicólogo(a)',
        'Educador(a)',
        'Pediatra',
      ],
    );
    expect(find.text(verifiedDeclaration), findsOneWidget);
    expect(waits(tester), isTrue);
    expect(find.text(affirmHint), findsOneWidget);

    await tapOn(tester, declaration);
    expect(waits(tester), isFalse);
  });

  testWidgets('"Continuar" waits on a valid email, and on a displayed role '
      'for the curation', (tester) async {
    await appointing(tester);

    await tapOn(tester, row('Moderação'));
    expect(waits(tester), isTrue, reason: 'no email');
    await tester.enterText(emailField, 'caio');
    await tester.pumpAndSettle();
    expect(waits(tester), isTrue, reason: 'not an email');
    await tester.enterText(emailField, caio);
    await tester.pumpAndSettle();
    expect(waits(tester), isFalse);

    await tapOn(tester, row('Curadoria'));
    expect(waits(tester), isTrue, reason: 'no displayed role');
    expect(find.text(chooseRoleHint), findsOneWidget);
  });

  testWidgets('"Moderação" is confirmed full screen with its consequence and '
      '"Motivo", then granted once with the reason trimmed; the done state '
      'goes back to the team', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await appointing(tester);

    await fill(tester, papel: 'Moderação');
    expect(find.byType(DeclarationRow), findsNothing);
    await tapOn(tester, proceed);

    final confirm = tester.widget<DestructiveConfirmation>(
      find.byType(DestructiveConfirmation),
    );
    expect(confirm.askReason, isTrue);
    expect(confirm.title, 'Nomear ${addressBreaks(caio)} para a moderação?');
    expect(confirm.titleSemanticsLabel, 'Nomear $caio para a moderação?');
    expect(confirm.body.join(' '), contains('vídeos retidos'));
    expect(confirm.bodySemanticsLabels!.join(' '), contains(caio));
    expect(writes(h), isEmpty);
    await confirmWith(tester, 'Nomear');

    expect(writes(h), [
      'POST /v1/admin/staff {"email":"$caio","role":"moderator",'
          '"reason":"$why"}',
    ]);
    expect(
      find.widgetWithText(Notice, joined(addressBreaks(caio))),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(joined(caio)), findsOneWidget);
    expect(emailField, findsNothing);
    await tapOn(tester, find.text('Voltar para a equipe'));
    expect(h.location(tester), '/admin/equipe');
    semantics.dispose();
  });

  testWidgets('"Curadoria" is granted with the displayed role and the '
      'affirmation', (tester) async {
    final h = await appointing(tester);

    await fill(tester, role: 'Pediatra', verified: true);
    await tapOn(tester, proceed);
    final confirm = tester.widget<DestructiveConfirmation>(
      find.byType(DestructiveConfirmation),
    );
    expect(confirm.title, 'Nomear ${addressBreaks(caio)} para a curadoria?');
    expect(confirm.body.join(' '), contains('pediatra'));
    await confirmWith(tester, 'Nomear');

    expect(writes(h), [
      'POST /v1/admin/staff {"email":"$caio","role":"curator",'
          '"display_role":"pediatra","verified_professional":true,'
          '"reason":"$why"}',
    ]);
  });

  testWidgets('a parent or caregiver is granted unverified', (tester) async {
    final h = await appointing(tester);

    await appoint(tester, role: 'Cuidador(a)');

    expect(writes(h).single, contains('"verified_professional":false'));
  });

  testWidgets('leaving a professional role takes the affirmation with it', (
    tester,
  ) async {
    await appointing(tester);

    await fill(tester, role: 'Pediatra', verified: true);
    await tapOn(tester, row('Educador(a)'));
    expect(tester.widget<DeclarationRow>(declaration).value, isFalse);
  });

  testWidgets('cancelling the confirmation sends nothing, the form kept', (
    tester,
  ) async {
    final h = await appointing(tester);

    await fill(tester, papel: 'Moderação');
    await tapOn(tester, proceed);
    await tapOn(tester, find.text('Cancelar'));

    expect(find.byType(DestructiveConfirmation), findsNothing);
    expect(writes(h), isEmpty);
    expect(find.text(caio), findsOneWidget);
  });

  testWidgets('opened with ?email=&papel= the form starts filled in', (
    tester,
  ) async {
    await appointing(
      tester,
      initial: '/admin/equipe/nova?email=bia%40example.com&papel=moderacao',
    );

    expect(find.text('bia@example.com'), findsOneWidget);
    expect(tester.widget<SelectableRow>(row('Moderação')).selected, isTrue);
    expect(waits(tester), isFalse);
  });

  for (final (code, status, papel, words) in [
    ('account_not_found', 404, 'Curadoria', noAccount),
    ('email_unverified', 409, 'Curadoria', accountUnverified),
    ('already_has_role', 409, 'Curadoria', alreadyCurator),
    ('already_has_role', 409, 'Moderação', alreadyModerator),
    ('self_appointment', 422, 'Moderação', selfAppointment),
    ('validation', 422, 'Moderação', emailInvalid),
    ('account_suspended', 409, 'Curadoria', accountSuspended),
    ('account_suspended', 409, 'Moderação', accountSuspended),
  ]) {
    testWidgets('$code ($papel) shows the form again, worded on the email '
        'field, the entries kept', (tester) async {
      await appointing(tester, grant: (_) => problem(status, code));

      await appoint(tester, papel: papel);

      expect(fieldError(tester), words);
      expect(find.text(caio), findsOneWidget);
      expect(tester.widget<SelectableRow>(row(papel)).selected, isTrue);
      expect(find.byType(ErrorNote), findsNothing);

      await tester.enterText(emailField, 'duda@example.com');
      await tester.pumpAndSettle();
      expect(fieldError(tester), isEmpty, reason: 'typing clears it');
    });
  }

  testWidgets('reauth_required asks to confirm it is you, then retries once '
      'for a staff write', (tester) async {
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
                grant: (_) => confirmed
                    ? json(201, memberOf('a3', caio, [moderatorRole()]))
                    : problem(403, 'reauth_required'),
              )(req);
            },
          )
          ..family = ownerFamily
          ..roles = ['admin'];
    await h.pump(tester, initial: '/admin/equipe/nova');

    await appoint(tester, papel: 'Moderação');
    expect(find.byType(ReauthPrompt), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'uma senha longa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    // The MFA gate's status read aside.
    final writes = h.actions.where((a) => a != 'GET /v1/staff/mfa');
    expect(writes.map((a) => a.split(' {').first), [
      'POST /v1/admin/staff',
      'POST /v1/session/reauth',
      'POST /v1/admin/staff',
    ]);
    expect(find.text('Voltar para a equipe'), findsOneWidget);
  });

  testWidgets('not_admin goes home with a notice', (tester) async {
    final h = await appointing(tester, grant: (_) => problem(403, 'not_admin'));

    await appoint(tester, papel: 'Moderação');

    expect(h.location(tester), '/');
    expect(
      find.text('Você não tem mais acesso à administração.'),
      findsOneWidget,
    );
  });
}
