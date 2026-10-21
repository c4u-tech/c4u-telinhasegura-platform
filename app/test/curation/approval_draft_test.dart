import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/approval_draft.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/family/family.dart' show AgeBand;

/// "Antes de começar" and two steps: one question of each rule.
const list = Checklist(
  version: '2026-10-21',
  groups: [
    ChecklistGroup(
      id: 'antes',
      title: 'Antes de começar',
      items: [
        ChecklistItem(
          id: 'c25',
          text: 'Vínculo?',
          rule: ChecklistRule.conflict,
        ),
        ChecklistItem(id: 'c03', text: 'Publi?', rule: ChecklistRule.refuses),
      ],
    ),
    ChecklistGroup(
      id: 'violencia',
      title: 'Violência e medo',
      items: [
        ChecklistItem(id: 'c04', text: 'Bate?', rule: ChecklistRule.refuses),
        ChecklistItem(id: 'c07', text: 'Triste?', rule: ChecklistRule.doubt),
      ],
    ),
    ChecklistGroup(
      id: 'ritmo',
      title: 'Ritmo e canal',
      items: [
        ChecklistItem(id: 'c22', text: 'Agitado?', rule: ChecklistRule.band),
        ChecklistItem(
          id: 'c23',
          text: 'Falta fim?',
          rule: ChecklistRule.refuses,
        ),
      ],
    ),
  ],
);

ChecklistItem item(String id) => list.item(id)!;
ChecklistGroup group(int i) => list.groups[i];

/// Every group answered "Não", standing on the last step.
ApprovalDraft atLastStep() {
  final d = ApprovalDraft(list);
  for (final g in list.groups) {
    d.noneOf(g);
  }
  d
    ..forward()
    ..forward();
  return d;
}

void main() {
  test('starts on "Antes de começar"; a page goes on only once every '
      'question is answered', () {
    final d = ApprovalDraft(list);
    expect(d.page, 0);
    expect(d.stepCount, 2);
    expect(d.topicPage, 3);
    expect(d.reviewPage, 4);
    expect(d.group, group(0));
    expect(d.canGoOn, isFalse);
    d.answer(item('c25'), ChecklistAnswer.ok);
    expect(d.canGoOn, isFalse);
    d.answer(item('c03'), ChecklistAnswer.ok);
    expect(d.canGoOn, isTrue);
    d.forward();
    expect(d.page, 1);
    expect(d.group, group(1));
    expect(d.answerOf(item('c04')), isNull);
  });

  test('a tie to the channel stops the flow on its first page', () {
    final d = ApprovalDraft(list)
      ..answer(item('c25'), ChecklistAnswer.appears)
      ..answer(item('c03'), ChecklistAnswer.ok);
    expect(d.conflict, isTrue);
    expect(d.canGoOn, isFalse);
  });

  test('"Nada disso acontece" answers Não to every question of the group, '
      'each still open to change', () {
    final d = ApprovalDraft(list)..noneOf(group(1));
    expect(d.answered(group(1)), isTrue);
    expect(d.answerOf(item('c04')), ChecklistAnswer.ok);
    d.answer(item('c04'), ChecklistAnswer.appears);
    expect(d.answerOf(item('c04')), ChecklistAnswer.appears);
    expect(d.refusing, ['c04']);
  });

  test('the outcome: a Sim that refuses wins, then a Não sei or a Sim the '
      'team decides, else an approval', () {
    final d = ApprovalDraft(list);
    for (final g in list.groups) {
      d.noneOf(g);
    }
    expect(d.outcome, ApprovalOutcome.approve);
    d.answer(item('c07'), ChecklistAnswer.appears);
    expect(d.outcome, ApprovalOutcome.team);
    d
      ..answer(item('c07'), ChecklistAnswer.ok)
      ..answer(item('c23'), ChecklistAnswer.doubt);
    expect(d.outcome, ApprovalOutcome.team);
    d.answer(item('c03'), ChecklistAnswer.appears);
    expect(d.outcome, ApprovalOutcome.refuse);
    expect(d.refusing, ['c03']);
    expect(d.answers, {
      'c25': ChecklistAnswer.ok,
      'c03': ChecklistAnswer.appears,
      'c04': ChecklistAnswer.ok,
      'c07': ChecklistAnswer.ok,
      'c22': ChecklistAnswer.ok,
      'c23': ChecklistAnswer.doubt,
    });
    expect(d.marked(group(0)), [(item('c03'), ChecklistAnswer.appears)]);
    expect(d.marked(group(1)), isEmpty);
  });

  test('the last step leads to the theme and band when the video can be '
      'approved, else straight to the review', () {
    final approving = atLastStep();
    expect(approving.nextIsTopic, isTrue);
    approving.forward();
    expect(approving.page, approving.topicPage);
    expect(approving.group, isNull);
    expect(approving.canGoOn, isFalse);
    approving
      ..theme = VideoTheme.musica
      ..band = AgeBand.from5To8;
    expect(approving.canGoOn, isTrue);
    approving.forward();
    expect(approving.page, approving.reviewPage);

    final team = atLastStep()..answer(item('c22'), ChecklistAnswer.doubt);
    expect(team.nextIsTopic, isFalse);
    team.forward();
    expect(team.page, team.reviewPage);
  });

  test('back goes one page back, the review to the theme and band only '
      'when it approves; on the first page it does nothing', () {
    final d = atLastStep()
      ..forward()
      ..theme = VideoTheme.musica
      ..band = AgeBand.from5To8
      ..forward();
    expect(d.back(), isTrue);
    expect(d.page, d.topicPage);
    expect(d.back(), isTrue);
    expect(d.page, 2);
    final team = atLastStep()
      ..answer(item('c07'), ChecklistAnswer.appears)
      ..forward();
    expect(team.back(), isTrue);
    expect(team.page, 2);
    final first = ApprovalDraft(list);
    expect(first.back(), isFalse);
    expect(first.page, 0);
  });

  test('a page changed from the review returns to the review', () {
    final d = atLastStep()
      ..answer(item('c07'), ChecklistAnswer.appears)
      ..forward();
    expect(d.page, d.reviewPage);
    d.change(0);
    expect(d.page, 0);
    expect(d.nextIsTopic, isFalse);
    d.forward();
    expect(d.page, d.reviewPage);
    d
      ..change(1)
      ..back();
    expect(d.page, d.reviewPage, reason: 'back returns to the review too');
  });

  test('back on "Antes de começar" changed from the review returns to the '
      'review', () {
    final d = atLastStep()
      ..answer(item('c07'), ChecklistAnswer.appears)
      ..forward()
      ..change(0);
    expect(d.back(), isTrue);
    expect(d.page, d.reviewPage);
  });

  test('back from a changed page that cannot go on is a plain back, never '
      'the review', () {
    final d = atLastStep()
      ..answer(item('c07'), ChecklistAnswer.appears)
      ..forward()
      ..change(0)
      ..answer(item('c25'), ChecklistAnswer.appears);
    expect(d.back(), isFalse, reason: 'the first page leaves the flow');
    expect(d.page, 0);

    final topic = atLastStep()
      ..forward()
      ..theme = VideoTheme.musica
      ..band = AgeBand.from5To8
      ..forward()
      ..band = null
      ..change(atLastStep().topicPage);
    expect(topic.back(), isTrue);
    expect(topic.page, topic.stepCount);
    expect(topic.nextIsTopic, isTrue, reason: 'no longer returning');
  });

  test('a change that now approves asks the theme and band before the '
      'review', () {
    final d = atLastStep()
      ..answer(item('c07'), ChecklistAnswer.appears)
      ..forward()
      ..change(1)
      ..answer(item('c07'), ChecklistAnswer.ok);
    expect(d.nextIsTopic, isTrue);
    d.forward();
    expect(d.page, d.topicPage);
    d
      ..theme = VideoTheme.bichos
      ..band = AgeBand.from9To12
      ..forward();
    expect(d.page, d.reviewPage);
  });

  test('a fast pace takes back "2 a 4 anos" and keeps any other band', () {
    final d = atLastStep()..band = AgeBand.upTo4;
    d.answer(item('c22'), ChecklistAnswer.appears);
    expect(d.youngestBarred, isTrue);
    expect(d.band, isNull);
    d.band = AgeBand.from5To8;
    d.answer(item('c22'), ChecklistAnswer.appears);
    expect(d.band, AgeBand.from5To8);
  });
}
