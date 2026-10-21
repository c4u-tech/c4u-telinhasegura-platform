import 'curation.dart';

/// A curator's answers to the checklist while they give them. A group is
/// answered by "nada disso aparece" or by marking at least one of its
/// questions; a question not marked is [ChecklistAnswer.ok].
class ChecklistDraft {
  ChecklistDraft(this.checklist);

  final Checklist checklist;
  final _cleared = <String>{};
  final _marks = <String, ChecklistAnswer>{};

  bool cleared(ChecklistGroup g) => _cleared.contains(g.id);

  bool answered(ChecklistGroup g) =>
      cleared(g) || g.items.any((i) => _marks.containsKey(i.id));

  bool get complete => checklist.groups.every(answered);

  /// "Nada disso aparece": every question of the group is "ok".
  void clear(ChecklistGroup g) {
    _cleared.add(g.id);
    for (final i in g.items) {
      _marks.remove(i.id);
    }
  }

  /// Marks [item] with [answer]; marking it again takes the mark back.
  void mark(ChecklistGroup g, ChecklistItem item, ChecklistAnswer answer) {
    _cleared.remove(g.id);
    if (_marks[item.id] == answer) {
      _marks.remove(item.id);
    } else {
      _marks[item.id] = answer;
    }
  }

  ChecklistAnswer answerOf(ChecklistItem item) =>
      _marks[item.id] ?? ChecklistAnswer.ok;

  /// Every question's answer, in the list's order: what the server takes.
  Map<String, ChecklistAnswer> get answers => {
    for (final i in checklist.items) i.id: answerOf(i),
  };

  Iterable<ChecklistItem> _appearing(ChecklistRule rule) => checklist.items
      .where((i) => i.rule == rule && answerOf(i) == ChecklistAnswer.appears);

  /// The questions marked as appearing that refuse the video.
  List<String> get refusing => [
    for (final i in _appearing(ChecklistRule.refuses)) i.id,
  ];

  /// A tie to the channel: this curator does not review the video.
  bool get conflict => _appearing(ChecklistRule.conflict).isNotEmpty;

  /// A reason the criteria never accept.
  bool get invalidReason => _appearing(ChecklistRule.invalidReason).isNotEmpty;

  /// A pace that rules out "2 a 4 anos".
  bool get youngestBarred => _appearing(ChecklistRule.band).isNotEmpty;

  /// The team decides: a "Tenho dúvida", or a question that asks for it.
  bool get doubt =>
      checklist.items.any((i) => answerOf(i) == ChecklistAnswer.doubt) ||
      _appearing(ChecklistRule.doubt).isNotEmpty;
}
