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
/// the review ([reviewPage]). It lives as long as the screen; the server
/// keeps a copy, which [restore] picks up on coming back to the video.
/// The list is the one a video of [length] is asked: a
/// short video has no long-video step and sends none of its answers.
///
/// The band is stated, not chosen: the curator confirms the one the
/// answers give ([computedBand]), or says the video is for older children
/// and picks one of the [olderBands] with a reason. A younger band is never
/// offered.
class ApprovalDraft {
  ApprovalDraft(Checklist list, {required this.length})
    : checklist = list.askedOf(length);

  final Checklist checklist;

  /// The video's length.
  final Duration length;
  final _answers = <String, ChecklistAnswer>{};
  int _page = 0;

  /// Where going on returns to from a page "mudar" opened: the review, or
  /// the theme and band; null on the way through.
  int? _returnTo;

  /// Whether the curator said the video is for older children.
  bool _olderAsked = false;

  VideoTheme? theme;
  AgeBand? band;

  /// The note sent with a doubt; kept with the rest of the review.
  String? note;

  /// Why the video is for older children than the answers say. It lives
  /// only as long as the screen: the kept draft has no place for it.
  String? bandReason;

  /// The longest [bandReason] the server takes.
  static const bandReasonMax = 200;

  int get page => _page;
  int get stepCount => checklist.groups.length - 1;
  int get topicPage => stepCount + 1;
  int get reviewPage => stepCount + 2;

  /// The group the page asks; null on the theme and band and on the
  /// review.
  ChecklistGroup? get group =>
      _page <= stepCount ? checklist.groups[_page] : null;

  /// The page that asks [item].
  int pageOf(ChecklistItem item) =>
      checklist.groups.indexWhere((g) => g.items.any((i) => i.id == item.id));

  /// Null until answered.
  ChecklistAnswer? answerOf(ChecklistItem item) => _answers[item.id];

  /// Answers [item]. A band the answers or the length now bar is taken
  /// back, and so is a band confirmed that the answers no longer give, so
  /// the band is asked again; an older band stated stays.
  void answer(ChecklistItem item, ChecklistAnswer a) {
    final confirmed = band != null && band == computedBand;
    _answers[item.id] = a;
    if (confirmed && band != computedBand) band = null;
    _dropBarredBand();
  }

  void _dropBarredBand() {
    if (barredBands.contains(band)) band = null;
  }

  /// Picks up a review kept from before: the answers to this list's
  /// questions only, the theme, the band unless the answers bar it, and the
  /// note. An answer, theme or band this build does not know is asked
  /// again, since the server would refuse every later save that sent it.
  void restore(ReviewDraft d) {
    for (final i in checklist.items) {
      if (d.answers[i.id] case final a? when a != ChecklistAnswer.unknown) {
        _answers[i.id] = a;
      }
    }
    theme = d.theme == VideoTheme.unknown ? null : d.theme;
    band = d.minAgeBand == AgeBand.unknown ? null : d.minAgeBand;
    note = d.note;
    _dropBarredBand();
  }

  /// Picks up a review kept from before beneath what was given here since,
  /// which wins: for a draft read only after the curator began answering.
  void restoreBeneath(ReviewDraft d) {
    final given = snapshot;
    restore(d);
    _answers.addAll(given.answers);
    theme = given.theme ?? theme;
    band = given.band ?? band;
    note = given.note ?? note;
    _dropBarredBand();
  }

  /// What a saved draft keeps: the answers in the list's order, the theme,
  /// the band and the note.
  ({
    Map<String, ChecklistAnswer> answers,
    VideoTheme? theme,
    AgeBand? band,
    String? note,
  })
  get snapshot => (answers: answers, theme: theme, band: band, note: note);

  /// The shortcut at the foot of a group: "Não" to every question of [g]
  /// still open, never changing an answer given; each stays open to
  /// change.
  void noneOf(ChecklistGroup g) {
    for (final i in g.items) {
      _answers.putIfAbsent(i.id, () => ChecklistAnswer.ok);
    }
  }

  /// How many questions of [g] are still open.
  int openIn(ChecklistGroup g) =>
      g.items.where((i) => !_answers.containsKey(i.id)).length;

  /// The first group, in the list's order, with a question still open:
  /// where a review in progress stopped. Null once every question is
  /// answered.
  ChecklistGroup? get stoppedAt =>
      checklist.groups.where((g) => openIn(g) > 0).firstOrNull;

  /// Coming back to a review in progress: the first page with an open
  /// question; once every one is answered, the theme and band when the
  /// answers approve, else the review. A tie to the channel stays on the
  /// first page, which says so.
  void resume() {
    _returnTo = null;
    final stopped = stoppedAt;
    _page = conflict
        ? 0
        : stopped != null
        ? checklist.groups.indexOf(stopped)
        : outcome == ApprovalOutcome.approve
        ? topicPage
        : reviewPage;
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

  /// The youngest band the answers allow: the oldest a Sim or a "Não sei"
  /// on a band question allows, "2 a 4 anos" with none. A band is not
  /// offered over what the curator could not affirm.
  AgeBand get answersBand => checklist.items
      .where(
        (i) =>
            i.rule == ChecklistRule.band &&
            (_answers[i.id] == ChecklistAnswer.appears ||
                _answers[i.id] == ChecklistAnswer.doubt),
      )
      .map((i) => i.allowsFrom)
      .fold(AgeBand.upTo4, _older);

  static AgeBand _older(AgeBand a, AgeBand b) => b.index > a.index ? b : a;

  /// A video longer than the youngest band allows: "2 a 4 anos" is not
  /// offered.
  bool get tooLongForYoungest => length > checklist.youngestMax;

  /// The youngest band the video may be approved for: the answers' band,
  /// at least "5 a 8 anos" for a video too long for the youngest.
  AgeBand get computedBand =>
      tooLongForYoungest ? _older(answersBand, AgeBand.from5To8) : answersBand;

  /// The bands not offered: every band younger than [computedBand].
  Set<AgeBand> get barredBands => {
    for (final b in AgeBand.values)
      if (b != AgeBand.unknown && b.index < computedBand.index) b,
  };

  /// The bands older than [computedBand], youngest first: what "É para
  /// mais velhos" offers; none when the answers give the oldest.
  List<AgeBand> get olderBands => [
    for (final b in AgeBand.values)
      if (b != AgeBand.unknown && b.index > computedBand.index) b,
  ];

  /// The band questions answered Sim or "Não sei", in the list's order:
  /// the answers that moved the band.
  List<(ChecklistItem, ChecklistAnswer)> get bandAnswers => [
    for (final i in checklist.items)
      if (i.rule == ChecklistRule.band)
        if (_answers[i.id] case final a?
            when a == ChecklistAnswer.appears || a == ChecklistAnswer.doubt)
          (i, a),
  ];

  /// Whether the band stated is older than the answers give.
  bool get statesOlder => band != null && band!.index > computedBand.index;

  /// Whether the older bands and the reason are open: asked for, or an
  /// older band already stated (a kept draft).
  bool get olderOpen => _olderAsked || statesOlder;

  String? get _reason {
    final r = bandReason?.trim();
    return r == null || r.isEmpty || r.length > bandReasonMax ? null : r;
  }

  /// The reason the approval carries: only with an older band.
  String? get reasonToSend => statesOlder ? _reason : null;

  /// "É para mais velhos": the older bands open, the only one chosen.
  void askOlder() {
    _olderAsked = true;
    if (!statesOlder) {
      final older = olderBands;
      band = older.length == 1 ? older.single : null;
    }
  }

  /// "Ficar com": back to confirming the band the answers give.
  void keepComputed() {
    _olderAsked = false;
    band = null;
  }

  /// "Confirmar": states the band the answers give and goes on.
  void confirmBand() {
    _olderAsked = false;
    band = computedBand;
    forward();
  }

  /// Whether the theme and band are stated as the server takes them: a
  /// theme and a band, an older one with its reason.
  bool get topicReady =>
      theme != null && band != null && (!statesOlder || _reason != null);

  /// The team decides: a "Não sei", or a Sim on a question that asks for
  /// it. A question only kept for the team decides nothing, whatever its
  /// answer.
  bool get doubt =>
      checklist.items.any(
        (i) =>
            i.rule != ChecklistRule.notes &&
            _answers[i.id] == ChecklistAnswer.doubt,
      ) ||
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
  /// answered (and no tie); the theme and band, confirming, once a theme
  /// is chosen, and stating an older band, once [topicReady].
  bool get canGoOn {
    final g = group;
    if (g != null) return answered(g) && !conflict;
    if (_page == topicPage) return olderOpen ? topicReady : theme != null;
    return true;
  }

  /// Where going on leads. An approval passes through the theme and band
  /// before the review, also after a change from the review made it one.
  int get _next {
    final approve = outcome == ApprovalOutcome.approve;
    if (_returnTo == topicPage) return approve ? topicPage : reviewPage;
    if (_returnTo != null) {
      return approve && !topicReady && _page != topicPage
          ? topicPage
          : reviewPage;
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
    _returnTo = null;
  }

  /// One page back: the review goes back to the theme and band when it
  /// approves, else to the last step; a page changed from the review
  /// returns to it, even the first page, as long as the page can still go
  /// on (a tie to the channel just marked cannot). Otherwise false on the
  /// first page, which the screen leaves.
  bool back() {
    if (_returnTo != null) {
      // Back never states a band: the theme and band go back only once
      // stated as the server takes them.
      if (_page == topicPage ? topicReady : canGoOn) {
        forward();
        return true;
      }
      _returnTo = null;
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
    _returnTo = reviewPage;
  }

  /// "mudar" beside an answer on the theme and band: [page] again, then
  /// back to the theme and band (or to the review, when the answers no
  /// longer approve).
  void changeFromTopic(int page) {
    _page = page;
    _returnTo = topicPage;
  }
}
