import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/approval_draft.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/family/family.dart' show AgeBand;

/// "Antes de começar" and two steps: one question of each rule; then a
/// step asked only of a long video.
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
        ChecklistItem(
          id: 'c22',
          text: 'Agitado?',
          rule: ChecklistRule.band,
          minBand: AgeBand.from5To8,
        ),
        ChecklistItem(
          id: 'c35',
          text: 'Namoro?',
          rule: ChecklistRule.band,
          minBand: AgeBand.from9To12,
        ),
        ChecklistItem(
          id: 'c23',
          text: 'Falta fim?',
          rule: ChecklistRule.refuses,
        ),
      ],
    ),
    ChecklistGroup(
      id: 'longo',
      title: 'Vídeo longo',
      items: [
        ChecklistItem(
          id: 'c26',
          text: 'Canal não oficial?',
          rule: ChecklistRule.refuses,
          longOnly: true,
        ),
        ChecklistItem(
          id: 'c28',
          text: 'Anúncios?',
          rule: ChecklistRule.notes,
          longOnly: true,
        ),
      ],
    ),
  ],
);

/// Short of the list's long video, which runs past 20 minutes.
const short = Duration(minutes: 5);

ChecklistItem item(String id) => list.item(id)!;
ChecklistGroup group(int i) => list.groups[i];

/// Every group answered "Não", standing on the last step.
ApprovalDraft atLastStep() {
  final d = ApprovalDraft(list, length: short);
  for (final g in d.checklist.groups) {
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
    final d = ApprovalDraft(list, length: short);
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
    final d = ApprovalDraft(list, length: short)
      ..answer(item('c25'), ChecklistAnswer.appears)
      ..answer(item('c03'), ChecklistAnswer.ok);
    expect(d.conflict, isTrue);
    expect(d.canGoOn, isFalse);
  });

  test('"Nada disso acontece" answers Não to every question of the group, '
      'each still open to change', () {
    final d = ApprovalDraft(list, length: short)..noneOf(group(1));
    expect(d.answered(group(1)), isTrue);
    expect(d.answerOf(item('c04')), ChecklistAnswer.ok);
    d.answer(item('c04'), ChecklistAnswer.appears);
    expect(d.answerOf(item('c04')), ChecklistAnswer.appears);
    expect(d.refusing, ['c04']);
  });

  test('the shortcut answers Não only to the questions still open and '
      'never changes an answer given', () {
    final d = ApprovalDraft(list, length: short)
      ..answer(item('c22'), ChecklistAnswer.appears);
    expect(d.openIn(group(2)), 2);
    d.noneOf(group(2));
    expect(d.answerOf(item('c22')), ChecklistAnswer.appears);
    expect(d.answerOf(item('c35')), ChecklistAnswer.ok);
    expect(d.answerOf(item('c23')), ChecklistAnswer.ok);
    expect(d.openIn(group(2)), 0);
    expect(d.answerOf(item('c04')), isNull, reason: 'another group');
  });

  test('coming back opens on the first page with an open question, the '
      'theme and band once all are answered, the review when they do not '
      'approve', () {
    ReviewDraft kept(Map<String, ChecklistAnswer> answers) => ReviewDraft(
      version: '2026-10-21',
      answers: answers,
      beganAt: DateTime.utc(2026, 11, 20, 10),
    );
    const no = ChecklistAnswer.ok;
    final none = ApprovalDraft(list, length: short)..resume();
    expect(none.page, 0);
    expect(none.stoppedAt, group(0));

    final partway = ApprovalDraft(list, length: short)
      ..restore(kept({'c25': no, 'c03': no, 'c04': no, 'c07': no, 'c22': no}))
      ..resume();
    expect(partway.page, 2);
    expect(partway.stoppedAt, group(2));

    final gap = ApprovalDraft(list, length: short)
      ..restore(kept({'c25': no, 'c22': no, 'c35': no, 'c23': no}))
      ..resume();
    expect(gap.page, 0, reason: 'the first open question, in the order');

    final all = {
      'c25': no,
      'c03': no,
      'c04': no,
      'c07': no,
      'c22': no,
      'c35': no,
      'c23': no,
    };
    final done = ApprovalDraft(list, length: short)
      ..restore(kept(all))
      ..resume();
    expect(done.stoppedAt, isNull);
    expect(done.page, done.topicPage);

    final refused = ApprovalDraft(list, length: short)
      ..restore(kept({...all, 'c04': ChecklistAnswer.appears}))
      ..resume();
    expect(refused.page, refused.reviewPage);

    // The long-only questions are open only on a long video.
    final long = ApprovalDraft(list, length: const Duration(minutes: 25))
      ..restore(kept(all))
      ..resume();
    expect(long.stoppedAt?.title, 'Vídeo longo');
    expect(long.page, 3);
  });

  test('where a review resumes is one answer for every reader: the first '
      'page with a tie to the channel, though a later group is open', () {
    ReviewDraft kept(Map<String, ChecklistAnswer> answers) => ReviewDraft(
      version: '2026-10-21',
      answers: answers,
      beganAt: DateTime.utc(2026, 11, 20, 10),
    );
    final tie = ApprovalDraft(list, length: short)
      ..restore(
        kept({'c25': ChecklistAnswer.appears, 'c03': ChecklistAnswer.ok}),
      );
    expect(tie.stoppedAt, group(1));
    expect(tie.resumePage, 0);
    tie.resume();
    expect(tie.page, tie.resumePage);

    final partway = ApprovalDraft(list, length: short)
      ..restore(kept({'c25': ChecklistAnswer.ok, 'c03': ChecklistAnswer.ok}));
    expect(partway.resumePage, 1);
  });

  test('the outcome: a Sim that refuses wins, then a Não sei or a Sim the '
      'team decides, else an approval', () {
    final d = ApprovalDraft(list, length: short);
    for (final g in d.checklist.groups) {
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
      'c35': ChecklistAnswer.ok,
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
    approving.theme = VideoTheme.musica;
    expect(approving.canGoOn, isTrue);
    approving.confirmBand();
    expect(approving.band, AgeBand.upTo4);
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
      ..confirmBand();
    expect(d.back(), isTrue);
    expect(d.page, d.topicPage);
    expect(d.back(), isTrue);
    expect(d.page, 2);
    final team = atLastStep()
      ..answer(item('c07'), ChecklistAnswer.appears)
      ..forward();
    expect(team.back(), isTrue);
    expect(team.page, 2);
    final first = ApprovalDraft(list, length: short);
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
      ..confirmBand();
    expect(d.page, d.reviewPage);
  });

  test('back from a step changed from the review whose answer now '
      'approves goes on to the theme and band, then the review', () {
    final d = atLastStep()
      ..answer(item('c07'), ChecklistAnswer.appears)
      ..forward()
      ..change(1)
      ..answer(item('c07'), ChecklistAnswer.ok);

    expect(d.back(), isTrue);
    expect(d.page, d.topicPage);
    d
      ..theme = VideoTheme.bichos
      ..band = AgeBand.from9To12;
    expect(d.back(), isTrue);
    expect(d.page, d.stepCount, reason: 'no longer returning');
  });

  test('says when going on opens the review', () {
    final d = ApprovalDraft(list, length: short);
    expect(d.nextIsReview, isFalse);
    final team = atLastStep()..answer(item('c07'), ChecklistAnswer.doubt);
    expect(team.nextIsReview, isTrue);
    final refuse = atLastStep()..answer(item('c23'), ChecklistAnswer.appears);
    expect(refuse.nextIsReview, isTrue);
    final approve = atLastStep();
    expect(approve.nextIsReview, isFalse, reason: 'the theme and band first');
    team
      ..forward()
      ..change(1);
    expect(team.nextIsReview, isTrue, reason: 'changed from the review');
  });

  test('a fast pace takes back "2 a 4 anos" and keeps any other band', () {
    final d = atLastStep()..band = AgeBand.upTo4;
    d.answer(item('c22'), ChecklistAnswer.appears);
    expect(d.barredBands, {AgeBand.upTo4});
    expect(d.band, isNull);
    d.band = AgeBand.from5To8;
    d.answer(item('c22'), ChecklistAnswer.appears);
    expect(d.band, AgeBand.from5To8);
  });

  test('the computed band is the oldest a Sim allows, and the length bars '
      'the youngest', () {
    final d = atLastStep();
    expect(d.answersBand, AgeBand.upTo4);
    expect(d.computedBand, AgeBand.upTo4);
    expect(d.barredBands, isEmpty);
    d.answer(item('c22'), ChecklistAnswer.appears);
    expect(d.computedBand, AgeBand.from5To8);
    expect(d.barredBands, {AgeBand.upTo4});
    d.band = AgeBand.from5To8;
    d.answer(item('c35'), ChecklistAnswer.appears);
    expect(d.computedBand, AgeBand.from9To12);
    expect(d.barredBands, {AgeBand.upTo4, AgeBand.from5To8});
    expect(d.band, isNull, reason: 'the band chosen is now barred');

    final long = ApprovalDraft(list, length: const Duration(minutes: 61));
    expect(long.answersBand, AgeBand.upTo4);
    expect(long.computedBand, AgeBand.from5To8);
  });

  test('a "Não sei" on a band question bars the band as a Sim does', () {
    final d = atLastStep()..band = AgeBand.from5To8;
    d.answer(item('c35'), ChecklistAnswer.doubt);
    expect(d.answersBand, AgeBand.from9To12);
    expect(d.barredBands, {AgeBand.upTo4, AgeBand.from5To8});
    expect(d.band, isNull, reason: 'the band chosen is now barred');
    expect(d.outcome, ApprovalOutcome.team, reason: 'still a doubt');
  });

  test('a band question an older server did not qualify bars the youngest '
      'only', () {
    const old = ChecklistItem(id: 'c22', text: '?', rule: ChecklistRule.band);
    expect(old.allowsFrom, AgeBand.from5To8);
    expect(item('c35').allowsFrom, AgeBand.from9To12);
  });

  test('a band question with a band this build does not know bars the '
      'youngest only', () {
    final newer = ChecklistItem.fromJson({
      'id': 'c40',
      'text': '?',
      'rule': 'band',
      'min_band': '13-17',
    });
    expect(newer.minBand, AgeBand.unknown);
    expect(newer.allowsFrom, AgeBand.from5To8);
  });

  test('a draft whose band this build does not know asks the band '
      'again', () {
    final d = ApprovalDraft(list, length: short)
      ..restore(
        ReviewDraft(
          version: '2026-10-21',
          answers: const {},
          minAgeBand: AgeBand.unknown,
          beganAt: DateTime.utc(2026, 11, 20, 10),
        ),
      );
    expect(d.band, isNull);
  });

  test('a draft whose theme this build does not know asks the theme '
      'again', () {
    final d = ApprovalDraft(list, length: short)
      ..restore(
        ReviewDraft(
          version: '2026-10-21',
          answers: const {},
          theme: VideoTheme.unknown,
          minAgeBand: AgeBand.from5To8,
          beganAt: DateTime.utc(2026, 11, 20, 10),
        ),
      );
    expect(d.theme, isNull);
    expect(d.snapshot.theme, isNull);
    expect(d.band, AgeBand.from5To8);
  });

  test('a draft answer this build does not know asks the question '
      'again', () {
    final d = ApprovalDraft(list, length: short)
      ..restore(
        ReviewDraft(
          version: '2026-10-21',
          answers: const {
            'c04': ChecklistAnswer.unknown,
            'c07': ChecklistAnswer.ok,
          },
          beganAt: DateTime.utc(2026, 11, 20, 10),
        ),
      );
    expect(d.answers, {'c07': ChecklistAnswer.ok});
    expect(d.answerOf(item('c04')), isNull);
  });

  test('a draft restores the answers of this list, the theme, the band and '
      'the note', () {
    final d = ApprovalDraft(list, length: short)
      ..restore(
        ReviewDraft(
          version: '2026-10-21',
          answers: const {'c04': ChecklistAnswer.ok, 'c99': ChecklistAnswer.ok},
          theme: VideoTheme.bichos,
          minAgeBand: AgeBand.from5To8,
          note: 'n',
          beganAt: DateTime.utc(2026, 11, 20, 10),
        ),
      );
    expect(d.answers, {'c04': ChecklistAnswer.ok});
    expect(d.theme, VideoTheme.bichos);
    expect(d.band, AgeBand.from5To8);
    expect(d.note, 'n');
    final kept = d.snapshot;
    expect(kept.answers, {'c04': ChecklistAnswer.ok});
    expect(kept.theme, VideoTheme.bichos);
    expect(kept.band, AgeBand.from5To8);
    expect(kept.note, 'n');

    final barred = ApprovalDraft(list, length: short)
      ..restore(
        ReviewDraft(
          version: '2026-10-21',
          answers: const {'c35': ChecklistAnswer.appears},
          minAgeBand: AgeBand.from5To8,
          beganAt: DateTime.utc(2026, 11, 20, 10),
        ),
      );
    expect(barred.answers, {'c35': ChecklistAnswer.appears});
    expect(barred.band, isNull, reason: 'a restored band now barred');
  });

  test('a long video asks its own step before the theme and band; a short '
      'one has no such step and sends none of its answers', () {
    final long = ApprovalDraft(list, length: const Duration(minutes: 25));
    expect(long.stepCount, 3);
    expect(long.checklist.groups.last.title, 'Vídeo longo');
    for (final g in long.checklist.groups) {
      long.noneOf(g);
    }
    expect(long.answers.keys, contains('c28'));

    final shortOne = ApprovalDraft(list, length: short);
    expect(shortOne.stepCount, 2);
    expect(shortOne.checklist.groups.map((g) => g.id), [
      'antes',
      'violencia',
      'ritmo',
    ]);
    for (final g in list.groups) {
      shortOne.noneOf(g);
    }
    expect(shortOne.answers.keys, isNot(contains('c26')));
    expect(shortOne.answers.keys, isNot(contains('c28')));
  });

  test('exactly 20 minutes is not long', () {
    final d = ApprovalDraft(list, length: const Duration(minutes: 20));
    expect(d.stepCount, 2);
  });

  test('a question kept for the team never changes the outcome, even '
      'answered Sim or Não sei', () {
    final d = ApprovalDraft(list, length: const Duration(minutes: 25));
    for (final g in d.checklist.groups) {
      d.noneOf(g);
    }
    d.answer(item('c28'), ChecklistAnswer.doubt);
    expect(d.outcome, ApprovalOutcome.approve);
    d.answer(item('c28'), ChecklistAnswer.appears);
    expect(d.outcome, ApprovalOutcome.approve);
    expect(d.answers['c28'], ChecklistAnswer.appears);
  });

  test('a video past 60 minutes keeps "2 a 4 anos" out, as a fast pace '
      'does; up to 60 minutes it does not', () {
    final long = ApprovalDraft(list, length: const Duration(minutes: 61));
    expect(long.tooLongForYoungest, isTrue);
    expect(long.computedBand, AgeBand.from5To8);
    expect(long.answersBand, AgeBand.upTo4, reason: 'the pace is not marked');
    long.band = AgeBand.upTo4;
    long.answer(item('c25'), ChecklistAnswer.ok);
    expect(long.band, isNull);
    expect(
      ApprovalDraft(list, length: const Duration(minutes: 60)).computedBand,
      AgeBand.upTo4,
    );
  });

  test('the limits come from the list', () {
    const strict = Checklist(
      version: 'v',
      longFrom: Duration(minutes: 1),
      youngestMax: Duration(minutes: 2),
      groups: [],
    );
    final d = ApprovalDraft(strict, length: const Duration(minutes: 3));
    expect(d.tooLongForYoungest, isTrue);
  });

  // Stating the band: the one the answers give, or an older one.
  {
    /// On the theme and band with every answer "Não" but [changed].
    ApprovalDraft atTopic([Map<String, ChecklistAnswer> changed = const {}]) {
      final d = atLastStep();
      for (final MapEntry(:key, :value) in changed.entries) {
        d.answer(item(key), value);
      }
      return d..forward();
    }

    test('lists the band questions answered Sim or Não sei, in the list\'s '
        'order, and nothing else', () {
      expect(atTopic().bandAnswers, isEmpty);
      final d = atTopic({
        'c35': ChecklistAnswer.doubt,
        'c22': ChecklistAnswer.appears,
        'c28': ChecklistAnswer.appears,
      });
      expect(d.bandAnswers, [
        (item('c22'), ChecklistAnswer.appears),
        (item('c35'), ChecklistAnswer.doubt),
      ]);
    });

    test('offers only the bands older than the answers give', () {
      expect(atTopic().olderBands, [AgeBand.from5To8, AgeBand.from9To12]);
      expect(atTopic({'c22': ChecklistAnswer.appears}).olderBands, [
        AgeBand.from9To12,
      ]);
      expect(atTopic({'c35': ChecklistAnswer.appears}).olderBands, isEmpty);
      final long = ApprovalDraft(list, length: const Duration(minutes: 61));
      expect(long.olderBands, [AgeBand.from9To12]);
    });

    test('confirming waits for a theme only, states the band the answers '
        'give and goes on to the review', () {
      final d = atTopic({'c22': ChecklistAnswer.appears});
      expect(d.olderOpen, isFalse);
      expect(d.canGoOn, isFalse);
      d.theme = VideoTheme.musica;
      expect(d.canGoOn, isTrue);
      d.confirmBand();
      expect(d.band, AgeBand.from5To8);
      expect(d.statesOlder, isFalse);
      expect(d.page, d.reviewPage);
    });

    test('"É para mais velhos" chooses the one older band there is, or none '
        'of two; going on waits for the theme, the band and a reason of 1 '
        'to 200 characters', () {
      final one = atTopic({'c22': ChecklistAnswer.appears})..askOlder();
      expect(one.olderOpen, isTrue);
      expect(one.band, AgeBand.from9To12);

      final d = atTopic()
        ..theme = VideoTheme.bichos
        ..askOlder();
      expect(d.band, isNull);
      expect(d.canGoOn, isFalse);
      d.band = AgeBand.from5To8;
      expect(d.statesOlder, isTrue);
      expect(d.canGoOn, isFalse, reason: 'no reason yet');
      d.bandReason = '   ';
      expect(d.canGoOn, isFalse, reason: 'blanks are no reason');
      d.bandReason = 'x' * 201;
      expect(d.canGoOn, isFalse);
      d.bandReason = ' Fala rápida. ';
      expect(d.canGoOn, isTrue);
      expect(d.reasonToSend, 'Fala rápida.');
      d.forward();
      expect(d.page, d.reviewPage);
    });

    test('the reason is counted in characters, as the field and the server '
        'count it: 200 with an emoji is taken', () {
      final d = atTopic()
        ..theme = VideoTheme.bichos
        ..askOlder()
        ..band = AgeBand.from5To8;
      final reason = '${'x' * 199}😀';
      expect(reason.length, 201, reason: 'the emoji is two code units');
      d.bandReason = reason;
      expect(d.canGoOn, isTrue);
      expect(d.reasonToSend, reason);
      d.bandReason = '${'x' * 200}😀';
      expect(d.canGoOn, isFalse);
    });

    test('"Ficar com" goes back to confirming, the older band let go', () {
      final d = atTopic()
        ..askOlder()
        ..band = AgeBand.from9To12
        ..keepComputed();
      expect(d.olderOpen, isFalse);
      expect(d.band, isNull);
      expect(d.reasonToSend, isNull);
    });

    test('a reason travels only with an older band', () {
      final d = atTopic()
        ..theme = VideoTheme.bichos
        ..bandReason = 'Mais velho.'
        ..confirmBand();
      expect(d.reasonToSend, isNull);
    });

    test('a band confirmed that the answers no longer give is asked again; '
        'an older band stays, needing its reason', () {
      final d = atTopic({'c22': ChecklistAnswer.appears})
        ..theme = VideoTheme.musica
        ..confirmBand();
      d.answer(item('c22'), ChecklistAnswer.ok);
      expect(d.band, isNull);

      final older = atTopic()
        ..theme = VideoTheme.musica
        ..askOlder()
        ..band = AgeBand.from9To12
        ..bandReason = 'Ironia.';
      older.answer(item('c22'), ChecklistAnswer.appears);
      expect(older.band, AgeBand.from9To12);
      expect(older.canGoOn, isTrue);
    });

    test('a page changed from the review whose answer now gives a younger '
        'band than the one stated goes back to the band, not to the '
        'review', () {
      final d = atTopic({'c22': ChecklistAnswer.appears})
        ..theme = VideoTheme.musica
        ..confirmBand()
        ..change(2)
        ..answer(item('c22'), ChecklistAnswer.ok);
      expect(d.nextIsTopic, isTrue);
    });

    test('"mudar" from the band page returns to the band page', () {
      final d = atTopic({'c22': ChecklistAnswer.appears})
        ..theme = VideoTheme.musica
        ..changeFromTopic(2);
      expect(d.page, 2);
      expect(d.nextIsTopic, isTrue);
      d.answer(item('c35'), ChecklistAnswer.appears);
      d.forward();
      expect(d.page, d.topicPage);
      expect(d.olderBands, isEmpty);

      final team = atTopic({'c22': ChecklistAnswer.appears})
        ..changeFromTopic(2)
        ..answer(item('c22'), ChecklistAnswer.doubt);
      team.answer(item('c07'), ChecklistAnswer.doubt);
      expect(team.nextIsReview, isTrue, reason: 'a doubt has no band');
    });

    test('a kept older band comes back open, asking its reason again: the '
        'reason is not kept', () {
      final d = ApprovalDraft(list, length: short)
        ..restore(
          ReviewDraft(
            version: '2026-10-21',
            answers: const {},
            theme: VideoTheme.bichos,
            minAgeBand: AgeBand.from9To12,
            beganAt: DateTime.utc(2026, 11, 20, 10),
          ),
        );
      expect(d.band, AgeBand.from9To12);
      expect(d.olderOpen, isTrue);
      d.bandReason = 'Ironia.';
      expect(d.snapshot.band, AgeBand.from9To12);
      expect(d.snapshot.toString(), isNot(contains('Ironia')));
    });
  }
}
