import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/audit_sample_screen.dart';
import 'package:telinha_segura/curation/audit_video_screen.dart';
import 'package:telinha_segura/family/confirm.dart' show reasonHint;
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'appoint_screen_test.dart' show tapOn;
import 'fixtures.dart';
import 'held_video_screen_test.dart' show confirming;

Map<String, Object?> approvalOf(String role, Map<String, String>? answers) => {
  'display_role': role,
  'decision': 'approve',
  'theme': 'bichos',
  'min_age_band': '5-8',
  'reason': null,
  'checklist_version': answers == null ? null : '2026-10-21',
  'answers': answers,
  'failed_items': null,
  'reviewed_at': '2026-10-04T12:00:00Z',
};

const cleanAnswers = {
  'c25': 'ok',
  'c03': 'ok',
  'c04': 'ok',
  'c07': 'ok',
  'c08': 'ok',
  'c15': 'ok',
  'c12': 'ok',
  'c22': 'ok',
  'c23': 'ok',
  'c24': 'ok',
};

final sampled = candidateOf(
  {
    ...queuedJson('v1', 'Baby Shark', channel: 'Canal Baby Shark'),
    'state': 'approved',
  },
  approvals: [
    approvalOf('pedagogo', cleanAnswers),
    approvalOf('mae-pai', {...cleanAnswers, 'c22': 'appears'}),
    approvalOf('cuidador', null),
  ],
);

Future<Harness> auditing(
  WidgetTester tester, {
  List<Map<String, Object?>>? sample,
  FutureOr<http.Response> Function(http.Request)? verdict,
  FutureOr<http.Response> Function()? checklist,
  String initial = '/moderacao/auditoria',
}) async {
  final h =
      Harness(
          signedIn: true,
          api: adminApi(
            sample: () => json(200, {
              'videos': sample ?? [sampled],
            }),
            verdict: verdict,
            checklist: checklist,
          ),
        )
        ..family = ownerFamily
        ..roles = ['moderator'];
  await h.pump(tester, initial: initial);
  return h;
}

List<String> verdicts(Harness h) =>
    h.actions.where((a) => a.startsWith('POST /v1/moderation/audits')).toList();

Object? body(String call) => jsonDecode(call.split(' ').skip(2).join(' '));

Future<void> open(WidgetTester tester) =>
    tapOn(tester, find.widgetWithText(DoorRow, 'Baby Shark'));

void main() {
  testWidgets('the held videos open the audit', (tester) async {
    final h = await auditing(tester, initial: '/moderacao/retidos');

    await tapOn(tester, find.widgetWithText(DoorRow, auditDoor));

    expect(h.location(tester), '/moderacao/auditoria');
    expect(find.text(sampleLead), findsOneWidget);
  });

  testWidgets('the sample lists each video as a door', (tester) async {
    await auditing(tester);
    expect(find.widgetWithText(DoorRow, 'Baby Shark'), findsOneWidget);
  });

  testWidgets('an empty sample says there is nothing to check', (tester) async {
    await auditing(tester, sample: []);
    expect(find.text(noSample), findsOneWidget);
  });

  testWidgets('a video shows each approval by role with what it marked, '
      'nothing marked, or approved before the list', (tester) async {
    final h = await auditing(tester);

    await open(tester);

    expect(h.location(tester), '/moderacao/auditoria/v1');
    for (final line in [
      nb('Pedagogo(a) aprovou · Bichos · 5 a 8 anos'),
      nb('Mãe ou pai aprovou · Bichos · 5 a 8 anos'),
      nb('Cuidador(a) aprovou · Bichos · 5 a 8 anos'),
      'Aparece: Tem ritmo agitado?',
      beforeTheList,
    ]) {
      expect(find.textContaining(line), findsOneWidget, reason: line);
    }
    expect(find.textContaining(nothingMarked), findsOneWidget);
  });

  testWidgets('each approval is announced with what it marked', (tester) async {
    final semantics = tester.ensureSemantics();
    await auditing(tester);

    await open(tester);

    for (final (role, marks) in [
      ('Pedagogo(a)', nothingMarked),
      ('Mãe ou pai', 'Aparece: Tem ritmo agitado?'),
      ('Cuidador(a)', beforeTheList),
    ]) {
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^${RegExp.escape(role)} aprovou.*${RegExp.escape(marks)}',
            dotAll: true,
          ),
        ),
        findsOneWidget,
        reason: role,
      );
    }
    semantics.dispose();
  });

  testWidgets('a failed read of the questions says so and retries', (
    tester,
  ) async {
    var reads = 0;
    await auditing(
      tester,
      checklist: () =>
          ++reads == 1 ? problem(500, 'internal') : json(200, checklistJson),
    );

    await open(tester);

    expect(find.text(marksFailed), findsOneWidget);
    expect(find.textContaining(nothingMarked), findsNothing);
    await tapOn(tester, find.widgetWithText(QuietAction, 'Tentar de novo'));

    expect(find.text(marksFailed), findsNothing);
    expect(find.textContaining(nothingMarked), findsOneWidget);
    expect(find.textContaining('Aparece: Tem ritmo agitado?'), findsOneWidget);
  });

  testWidgets('"De acordo" records once and goes back to the sample', (
    tester,
  ) async {
    final h = await auditing(tester);

    await open(tester);
    await tapOn(tester, find.widgetWithText(FilledButton, 'De acordo'));

    expect(verdicts(h), hasLength(1));
    expect(body(verdicts(h).single), {
      'video_id': 'v1',
      'round': 1,
      'verdict': 'agree',
    });
    expect(h.location(tester), '/moderacao/auditoria');
    expect(find.text(agreedWith('Baby Shark')), findsOneWidget);
  });

  testWidgets('"Discordo" asks the reason and keeps the video', (tester) async {
    final h = await auditing(tester);

    await open(tester);
    // The action spans the row; its button sits at the start.
    await tapOn(
      tester,
      find.descendant(
        of: find.widgetWithText(QuietAction, 'Discordo'),
        matching: find.byType(TextButton),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      '  Faixa errada. ',
    );
    await tester.pump();
    await tapOn(tester, confirming('Discordo'));

    expect(body(verdicts(h).single), {
      'video_id': 'v1',
      'round': 1,
      'verdict': 'disagree',
      'reason': 'Faixa errada.',
    });
    expect(find.text(disagreedWith('Baby Shark')), findsOneWidget);
  });

  testWidgets('"Discordo e tirar do app" holds the video', (tester) async {
    final h = await auditing(tester);

    await open(tester);
    await tapOn(
      tester,
      find.widgetWithText(QuietAction, 'Discordo e tirar do app'),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Motivo'),
      'Tem publi no fim.',
    );
    await tester.pump();
    await tapOn(tester, confirming('Tirar do app'));

    expect(body(verdicts(h).single), {
      'video_id': 'v1',
      'round': 1,
      'verdict': 'disagree',
      'reason': 'Tem publi no fim.',
      'hold': true,
    });
    expect(find.text(heldByAudit('Baby Shark')), findsOneWidget);
  });

  testWidgets('already_audited goes back to the sample with a notice', (
    tester,
  ) async {
    final h = await auditing(
      tester,
      verdict: (_) => problem(409, 'already_audited'),
    );

    await open(tester);
    await tapOn(tester, find.widgetWithText(FilledButton, 'De acordo'));

    expect(h.location(tester), '/moderacao/auditoria');
    expect(find.text(auditGone), findsOneWidget);
  });

  testWidgets('own_review goes back to the sample with its notice', (
    tester,
  ) async {
    final h = await auditing(
      tester,
      verdict: (_) => problem(409, 'own_review'),
    );

    await open(tester);
    await tapOn(tester, find.widgetWithText(FilledButton, 'De acordo'));

    expect(h.location(tester), '/moderacao/auditoria');
    expect(find.text(auditOwn), findsOneWidget);
  });

  testWidgets('state_conflict goes back to the sample with a notice', (
    tester,
  ) async {
    final h = await auditing(
      tester,
      verdict: (_) => problem(409, 'state_conflict'),
    );

    await open(tester);
    await tapOn(tester, find.widgetWithText(FilledButton, 'De acordo'));

    expect(h.location(tester), '/moderacao/auditoria');
    expect(find.text(auditChanged), findsOneWidget);
  });

  testWidgets('a disagreement reason of one or two characters is not sent '
      'and asks for 3 to 200', (tester) async {
    final h = await auditing(tester);

    await open(tester);
    for (final short in ['a', ' ab ']) {
      await tapOn(
        tester,
        find.descendant(
          of: find.widgetWithText(QuietAction, 'Discordo'),
          matching: find.byType(TextButton),
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Motivo'), short);
      await tester.pump();

      expect(
        tester.widget<FilledButton>(confirming('Discordo')).onPressed,
        isNull,
        reason: short,
      );
      expect(find.text(reasonHint), findsOneWidget, reason: short);
      await tapOn(
        tester,
        find.descendant(
          of: find.widgetWithText(QuietAction, 'Cancelar'),
          matching: find.byType(TextButton),
        ),
      );
    }

    expect(verdicts(h), isEmpty);
  });

  testWidgets('opened without the sample (a reload) goes back to it', (
    tester,
  ) async {
    final h = await auditing(tester, initial: '/moderacao/auditoria/v1');
    expect(h.location(tester), '/moderacao/auditoria');
  });
}
