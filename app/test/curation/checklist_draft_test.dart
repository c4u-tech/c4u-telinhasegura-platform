import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/checklist_draft.dart';
import 'package:telinha_segura/curation/curation.dart';

import 'fixtures.dart';

void main() {
  late Checklist list;
  late ChecklistDraft draft;
  ChecklistGroup group(String id) => list.groups.firstWhere((g) => g.id == id);

  setUp(() {
    list = Checklist.fromJson(checklistJson);
    draft = ChecklistDraft(list);
  });

  test('a group is answered by "nada disso aparece" or by a mark', () {
    expect(draft.complete, isFalse);
    draft.clear(group('antes'));
    expect(draft.answered(group('antes')), isTrue);
    draft.mark(group('violencia'), list.item('c07')!, ChecklistAnswer.doubt);
    expect(draft.answered(group('violencia')), isTrue);
    expect(draft.cleared(group('violencia')), isFalse);
    draft
      ..clear(group('linguagem'))
      ..clear(group('faixa'));
    expect(draft.complete, isTrue);
    expect(draft.answers, {
      'c01': ChecklistAnswer.ok,
      'c25': ChecklistAnswer.ok,
      'c04': ChecklistAnswer.ok,
      'c07': ChecklistAnswer.doubt,
      'c21': ChecklistAnswer.ok,
      'c22': ChecklistAnswer.ok,
    });
    expect(draft.doubt, isTrue);
  });

  test('marking twice takes the mark back; clearing drops the marks', () {
    final g = group('violencia');
    draft.mark(g, list.item('c04')!, ChecklistAnswer.appears);
    expect(draft.refusing, ['c04']);
    draft.mark(g, list.item('c04')!, ChecklistAnswer.appears);
    expect(draft.refusing, isEmpty);
    expect(draft.answered(g), isFalse);
    draft
      ..mark(g, list.item('c04')!, ChecklistAnswer.appears)
      ..clear(g);
    expect(draft.refusing, isEmpty);
    expect(draft.cleared(g), isTrue);
  });

  test('each rule shows in its own flag', () {
    draft
      ..mark(group('antes'), list.item('c25')!, ChecklistAnswer.appears)
      ..mark(group('linguagem'), list.item('c21')!, ChecklistAnswer.appears)
      ..mark(group('faixa'), list.item('c22')!, ChecklistAnswer.appears)
      ..mark(group('violencia'), list.item('c07')!, ChecklistAnswer.appears);
    expect(draft.conflict, isTrue);
    expect(draft.invalidReason, isTrue);
    expect(draft.youngestBarred, isTrue);
    expect(draft.doubt, isTrue);
    expect(draft.refusing, isEmpty);
    draft.mark(group('antes'), list.item('c01')!, ChecklistAnswer.appears);
    expect(draft.refusing, ['c01']);
  });
}
