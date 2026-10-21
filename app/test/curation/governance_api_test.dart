import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/curation_api.dart';
import 'package:telinha_segura/curation/words.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/staff/staff_api.dart';

import '../auth/fakes.dart';
import 'curation_api_test.dart' show pendingJson, rejectionJson;
import 'fixtures.dart';

http.Response contract(http.Request req) =>
    switch ('${req.method} ${req.url.path}') {
      'GET /v1/curation/checklist' => json(200, checklistJson),
      'GET /v1/curation/declaration' => json(200, termsJson()),
      'POST /v1/curation/declaration' => json(200, termsJson(accepted: true)),
      'GET /v1/moderation/videos' => json(200, {
        'videos': [
          heldOf(pendingJson, reason: 'doubt', doubts: [doubtJson]),
        ],
      }),
      'GET /v1/moderation/audit-sample' => json(200, {
        'videos': [
          candidateOf(
            {...pendingJson, 'state': 'approved'},
            approvals: [
              {...doubtJson, 'decision': 'approve', 'reason': null},
              {...rejectionJson, 'decision': 'approve', 'reason': null},
            ],
          ),
        ],
      }),
      _ => http.Response('', 204),
    };

void main() {
  test('the checklist parses into groups and questions', () async {
    final list = await CurationApi(build(ClientKind.mobile, contract).client)
        .checklist();
    expect(list.version, '2026-10-21');
    expect(list.groups.map((g) => g.title), [
      'Antes de começar',
      'Violência e medo',
      'Linguagem e respeito',
      'Consumo e publicidade',
      'Saúde e segurança',
      'Ritmo e canal',
    ]);
    expect(list.items.map((i) => i.id), [
      'c25',
      'c03',
      'c04',
      'c07',
      'c08',
      'c15',
      'c12',
      'c22',
      'c23',
      'c24',
    ]);
    expect(list.item('c25')!.rule, ChecklistRule.conflict);
    expect(list.item('c99'), isNull);
    expect(ChecklistRule.parse('new_rule'), ChecklistRule.unknown);
    expect(ChecklistAnswer.parse('maybe'), ChecklistAnswer.unknown);
  });

  test('the curator terms are read and accepted by version', () async {
    final t = build(ClientKind.mobile, contract);
    final api = CurationApi(t.client);
    final terms = await api.declaration();
    expect(terms.version, '2026-10-20');
    expect(terms.accepted, isFalse);
    expect(terms.text, startsWith('Ao fazer parte da curadoria'));
    expect((await api.acceptDeclaration(terms.version)).accepted, isTrue);
    expect(t.calls, [
      'GET /v1/curation/declaration',
      'POST /v1/curation/declaration {"version":"2026-10-20"}',
    ]);
  });

  test('a held doubt carries its answers and note; old reviews none', () {
    final held = HeldVideo.fromJson(
      heldOf(pendingJson, reason: 'doubt', doubts: [doubtJson]),
    );
    expect(held.heldReason, HeldReason.doubt);
    final doubt = held.doubts.single;
    expect(doubt.decision, ReviewDecision.doubt);
    expect(doubt.reason, 'Não sei se a tristeza pesa.');
    expect(doubt.checklistVersion, '2026-10-21');
    expect(doubt.answers!['c07'], ChecklistAnswer.appears);
    expect(doubt.answers!['c22'], ChecklistAnswer.doubt);
    expect(doubt.failedItems, isNull);
    final old = Review.fromJson(rejectionJson);
    expect(old.answers, isNull);
    expect(old.failedItems, isNull);
    expect(old.checklistVersion, isNull);
    expect(HeldReason.parse('audit'), HeldReason.audit);
    expect(
      HeldVideo.fromJson(heldOf(pendingJson)).doubts,
      isEmpty,
      reason: 'an older server sends no doubts',
    );
  });

  test('a review is worded by what it marked, in the list order', () {
    final list = Checklist.fromJson(checklistJson);
    final doubt = Review.fromJson(doubtJson);
    expect(CurationWords.marked(doubt, list), [
      'Aparece: Algum personagem fica triste?',
      'Tenho dúvida: Tem ritmo agitado?',
    ]);
    expect(CurationWords.marked(Review.fromJson(rejectionJson), list), isEmpty);
    expect(
      CurationWords.review(doubt),
      'Mãe ou pai teve dúvida\u00A0· Bichos\u00A0· 5 a 8 anos',
      reason: 'a doubt names the theme and band its curator chose',
    );
  });

  test('a held video carries the audit that held it', () {
    final held = HeldVideo.fromJson(
      heldOf(pendingJson, reason: 'audit', audit: auditJson),
    );
    expect(held.heldReason, HeldReason.audit);
    expect(held.audit!.verdict, AuditVerdict.disagree);
    expect(held.audit!.reason, 'Tem publi.');
    expect(held.audit!.auditedAt, DateTime.utc(2026, 10, 10, 9, 30));
    expect(HeldVideo.fromJson(heldOf(pendingJson)).audit, isNull);
    final agreed = HeldVideo.fromJson(
      heldOf(
        pendingJson,
        audit: {...auditJson, 'verdict': 'agree', 'reason': null},
      ),
    );
    expect(agreed.audit!.reason, isNull);
    final blank = HeldVideo.fromJson(
      heldOf(pendingJson, audit: {...auditJson, 'reason': ''}),
    );
    expect(blank.audit!.reason, isNull);
    expect(AuditVerdict.parse('x'), AuditVerdict.unknown);
  });

  test('the moderation contract: decide, sample, audit', () async {
    final t = build(ClientKind.mobile, contract);
    final api = StaffApi(t.client);
    await api.decideDoubt(
      'v1',
      publish: true,
      theme: VideoTheme.natureza,
      minAgeBand: AgeBand.upTo4,
      reason: 'Sem risco.',
    );
    await api.decideDoubt('v1', publish: false, reason: 'Desafio perigoso.');
    final sample = await api.auditSample();
    await api.auditApproval(videoId: 'v1', round: 1, agree: true);
    await api.auditApproval(
      videoId: 'v1',
      round: 1,
      agree: false,
      reason: 'Tem publi.',
      hold: true,
    );
    expect(t.calls, [
      'POST /v1/moderation/videos/v1/decide {"decision":"approve","theme":"natureza","min_age_band":"ate-4","reason":"Sem risco."}',
      'POST /v1/moderation/videos/v1/decide {"decision":"reject","reason":"Desafio perigoso."}',
      'GET /v1/moderation/audit-sample',
      'POST /v1/moderation/audits {"video_id":"v1","round":1,"verdict":"agree"}',
      'POST /v1/moderation/audits {"video_id":"v1","round":1,"verdict":"disagree","reason":"Tem publi.","hold":true}',
    ]);
    final c = sample.single;
    expect(c.round, 1);
    expect(c.video.state, VideoState.approved);
    expect(c.approvals.map((r) => r.displayRole), [
      DisplayRole.maePai,
      DisplayRole.cuidador,
    ]);
    expect(c.approvals.last.answers, isNull);
  });

  test('the new problem codes are worded', () {
    for (final code in [
      'checklist_outdated',
      'checklist_refuses',
      'checklist_band',
      'checklist_invalid_reason',
      'conflict_of_interest',
      'declaration_required',
      'declaration_outdated',
      'already_audited',
      'own_review',
    ]) {
      final words = Copy.forError(ApiError(status: 409, code: code));
      expect(words, isNot(Copy.genericRetry), reason: code);
      expect(words, isNot(contains('!')), reason: code);
    }
  });
}
