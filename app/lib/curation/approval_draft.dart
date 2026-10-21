import '../family/family.dart' show AgeBand;
import 'curation.dart';

/// Where an approval's answers lead, as the review's final button says.
enum ApprovalOutcome {
  /// Every answer keeps the video: "Aprovar".
  approve,

  /// A Sim on a question that refuses: "Recusar".
  refuse,

  /// A "Não sei", or a Sim on a question the team decides: "Enviar para a
  /// equipe".
  team,
}

/// A curator's answers to the checklist and where they stand in it, page
/// by page: page 0 is the list's first group ("Antes de começar"), pages 1
/// to [stepCount] are the steps, one per remaining group, then the theme
/// and band ([topicPage]), asked only when the video can be approved, and
/// the review ([reviewPage]). It lives as long as the screen: leaving the
/// flow drops it.
class ApprovalDraft {
  ApprovalDraft(this.checklist);

  final Checklist checklist;
  final _answers = <String, ChecklistAnswer>{};
  int _page = 0;

  /// Sent back to a page by the review: going on returns to the review.
  bool _returning = false;

  VideoTheme? theme;
  AgeBand? band;

  int get page => _page;
  int get stepCount => checklist.groups.length - 1;
  int get topicPage => stepCount + 1;
  int get reviewPage => stepCount + 2;

  /// The group the page asks; null on the theme and band and on the
  /// review.
  ChecklistGroup? get group =>
      _page <= stepCount ? checklist.groups[_page] : null;

  /// Null until answered.
  ChecklistAnswer? answerOf(ChecklistItem item) => _answers[item.id];

  /// Answers [item]. A fast pace takes back "2 a 4 anos" if it was
  /// chosen, so the band is asked again.
  void answer(ChecklistItem item, ChecklistAnswer a) {
    _answers[item.id] = a;
    if (youngestBarred && band == AgeBand.upTo4) band = null;
  }

  /// "Nada disso acontece no vídeo": every question of [g] answered "Não",
  /// each still open to change.
  void noneOf(ChecklistGroup g) {
    for (final i in g.items) {
      _answers[i.id] = ChecklistAnswer.ok;
    }
  }

  bool answered(ChecklistGroup g) =>
      g.items.every((i) => _answers.containsKey(i.id));

  Iterable<ChecklistItem> _yes(ChecklistRule rule) => checklist.items.where(
    (i) => i.rule == rule && _answers[i.id] == ChecklistAnswer.appears,
  );

  /// A tie to the channel: this curator does not review the video.
  bool get conflict => _yes(ChecklistRule.conflict).isNotEmpty;

  /// The questions answered Sim that refuse the video, in the list's order.
  List<String> get refusing => [
    for (final i in _yes(ChecklistRule.refuses)) i.id,
  ];

  /// A fast pace: "2 a 4 anos" is not offered.
  bool get youngestBarred => _yes(ChecklistRule.band).isNotEmpty;

  /// The team decides: a "Não sei", or a Sim on a question that asks for
  /// it.
  bool get doubt =>
      _answers.containsValue(ChecklistAnswer.doubt) ||
      _yes(ChecklistRule.doubt).isNotEmpty;

  ApprovalOutcome get outcome => refusing.isNotEmpty
      ? ApprovalOutcome.refuse
      : doubt
      ? ApprovalOutcome.team
      : ApprovalOutcome.approve;

  /// The answers given, in the list's order: what the server takes once
  /// every group is answered.
  Map<String, ChecklistAnswer> get answers => {
    for (final i in checklist.items) i.id: ?_answers[i.id],
  };

  /// What [g] answered other than "Não", in the list's order.
  List<(ChecklistItem, ChecklistAnswer)> marked(ChecklistGroup g) => [
    for (final i in g.items)
      if (_answers[i.id] case final a? when a != ChecklistAnswer.ok) (i, a),
  ];

  /// Whether the page's primary may go on: a group once every question is
  /// answered (and no tie), the theme and band once both are chosen.
  bool get canGoOn {
    final g = group;
    if (g != null) return answered(g) && !conflict;
    if (_page == topicPage) return theme != null && band != null;
    return true;
  }

  /// Where going on leads. An approval passes through the theme and band
  /// before the review, also after a change from the review made it one.
  int get _next {
    final needsTopic =
        outcome == ApprovalOutcome.approve && (theme == null || band == null);
    if (_returning) {
      return needsTopic && _page != topicPage ? topicPage : reviewPage;
    }
    if (_page < stepCount) return _page + 1;
    if (_page == stepCount) {
      return outcome == ApprovalOutcome.approve ? topicPage : reviewPage;
    }
    return reviewPage;
  }

  /// Whether going on opens the theme and band.
  bool get nextIsTopic => _next == topicPage;

  /// Whether going on opens the review.
  bool get nextIsReview => _next == reviewPage;

  void forward() {
    _page = _next;
    _returning = false;
  }

  /// One page back: the review goes back to the theme and band when it
  /// approves, else to the last step; a page changed from the review
  /// returns to it, even the first page, as long as the page can still go
  /// on (a tie to the channel just marked cannot). Otherwise false on the
  /// first page, which the screen leaves.
  bool back() {
    if (_returning) {
      if (canGoOn) {
        forward();
        return true;
      }
      _returning = false;
    }
    if (_page == 0) return false;
    if (_page == reviewPage) {
      _page = outcome == ApprovalOutcome.approve ? topicPage : stepCount;
    } else {
      _page--;
    }
    return true;
  }

  /// "mudar" on the review: [page] again, then back to the review.
  void change(int page) {
    _page = page;
    _returning = true;
  }
}
