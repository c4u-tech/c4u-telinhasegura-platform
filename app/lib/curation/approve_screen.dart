import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/profile_fields.dart' show SelectableRow;
import '../family/widgets.dart' show FamilyPlaceholder;
import '../legal/legal_links.dart' show kCurationUrl;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'adult_window.dart';
import 'answer_choice.dart';
import 'band_answer_row.dart';
import 'approval_draft.dart';
import 'curation.dart';
import 'curation_api.dart';
import 'draft_writer.dart';
import 'end_line.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'unheard_ends.dart';
import 'words.dart';

export 'end_line.dart' show notPlayedToEnd, playedToEnd;

/// "Antes de começar": what the app checked when the video was suggested.
const checkedByApp =
    '✓ Já conferido pelo app: feito para crianças no YouTube, pode ser '
    'exibido aqui, não é ao vivo e cabe no tempo máximo.';

/// The primaries: of "Antes de começar", of a step, and of the last step
/// when the video can be approved.
const startQuestions = 'Começar as perguntas';
const nextStep = 'Próxima etapa';
const chooseTopic = 'Ver a idade e escolher o tema';

/// The primary of a page that leads to the review: the theme and band, the
/// last step when the answers do not approve, and a page changed from the
/// review.
const seeSummary = 'Ver resumo';

/// The shortcut at the foot of a step: with nothing answered, then once
/// some questions are, with the line that says how many it answers.
const noneHappens = 'Nada disso acontece no vídeo';
const restHappens = 'O resto não acontece no vídeo';
String restLine(int n) => n == 1
    ? 'Marca Não na pergunta ainda sem resposta.'
    : 'Marca Não nas $n perguntas ainda sem resposta.';

/// Under a page's primary until it can go on.
const stepHint = 'Responda todas as perguntas desta etapa.';

/// The band page's hints, by what is missing: a theme, then, for an older
/// band, the band and why.
const themeHint = 'Escolha um tema acima.';
const olderBandHint = 'Escolha a idade acima.';
const olderReasonHint = 'Escreva por que é para mais velhos.';

/// The band page's ways on: confirming the band the answers give, or
/// saying the video is for older children, with why.
String confirmBandLabel(AgeBand band) => 'Confirmar ${band.label}';
const olderLabel = 'É para mais velhos';
const olderReasonLabel = 'Por que é para mais velhos';
const continueLabel = 'Continuar';

/// Back from the older bands to confirming the answers' band.
String stayWithLabel(AgeBand band) => 'Ficar com ${band.label}';

/// The band page's statement of the band the answers give.
String bandStatement(AgeBand from) =>
    'Pelas respostas, este vídeo serve a partir de ${from.label}';

/// Under "Aprovar" until the video has played to its end here.
const watchHint = 'Para aprovar, deixe o vídeo tocar até o fim.';

/// The review: its title, a step with nothing marked, the action back to
/// a step, and the line of the theme and band.
const reviewTitle = 'Confira antes de enviar';
const allNo = 'tudo Não';
const changeLabel = 'mudar';
const topicTitle = 'Tema e idade';

/// The review's final button, by what the answers lead to.
const approveLabel = 'Aprovar';
const refuseLabel = 'Recusar';
const teamLabel = 'Enviar para a equipe';

/// When the video's length, not an answer, rules out the youngest band.
const tooLongForYoungestLine =
    'Vídeos com mais de 60 minutos não vão para a faixa de '
    '2\u00A0a\u00A04\u00A0anos.';

/// The done state's notices.
const approved = 'Sua aprovação foi registrada.';
const doubtSent = 'Enviamos o vídeo para a equipe da Coding4u decidir.';

/// In the player's place when it could not play the video.
const flowPlayerFailed = 'Esse vídeo não abriu aqui.';

/// `validation` on an approval: the theme and band are asked again.
const approvalRefused =
    'Essa escolha não foi aceita. Escolha o tema e a idade de novo.';

/// A tie to the channel, said on "Antes de começar".
const conflictLine =
    'Você tem vínculo com este canal, então a revisão dele fica com outros '
    'curadores.';

/// What the team's decision means for a video still waiting for its first
/// decision, and for one already in the app, revisited.
const doubtLine =
    'Sua dúvida vai para a equipe da Coding4u, que decide. O vídeo fica '
    'esperando a decisão da equipe.';
const doubtRevisitLine =
    'Sua dúvida vai para a equipe da Coding4u, que decide. O vídeo sai do '
    'app até lá.';

/// The note sent to the team, optional.
const doubtNoteLabel = 'Conte sua dúvida (opcional)';

/// Over the bands: the rating every video must have.
const curationRule = 'Todo vídeo precisa ser Livre.';

/// The link to the criteria of each band, on the site.
const curationCriteriaLink = 'Veja os critérios de cada idade';

/// What the band's arrow says it does: leave the questions for the video's
/// screen, the answers kept, from any page.
const leaveForVideo = 'Voltar para o vídeo';

/// "Etapa 2 de 5".
String stepLabel(int step, int of) => 'Etapa $step de $of';

/// `/curadoria/:id/aprovar`: the checklist the server holds, one page at
/// a time. "Antes de começar" (the list's first group, under what the app
/// already checked), then one step per remaining group, each going on only
/// once every question is answered; then the band page, only when the
/// answers approve: the band the answers give stated, with the answers that
/// moved it, and the theme to choose; the curator confirms that band or
/// says the video is for older children, choosing an older band and saying
/// why. Then "Confira antes de enviar", whose final button
/// says what happens: "Aprovar", "Recusar" (the refusal, with the
/// questions ticked) or "Enviar para a equipe" (an approval the server
/// holds as a doubt). A tie to the channel ends on the first page. Back,
/// from the foot or from the system, goes one page back; the band's arrow
/// leaves for the video's screen from any page. Every change is kept
/// by the server as the curator's draft, so leaving and coming back picks
/// up the answers, theme, band and note where they were (the reason for an
/// older band is asked again: the draft has no place for it). A band
/// younger than the answers give is never offered. The video's window stays in view on
/// every page, pinned above the questions on a phone and in a pane of its
/// own on a large window, in one player for the whole flow, so going from
/// page to page never reloads it; it goes when the flow does. A line under
/// it says whether the video has played to its end, which "Aprovar" waits
/// for; a refusal and a doubt do not.
class ApproveScreen extends StatefulWidget {
  const ApproveScreen({super.key, required this.id, this.video});

  final String id;

  /// The video as the review read it; opened directly, it is read here.
  final Video? video;

  @override
  State<ApproveScreen> createState() => _ApproveScreenState();
}

class _ApproveScreenState extends State<ApproveScreen> with AdultWindow {
  final _send = Submission();
  final _note = TextEditingController();
  final _bandReason = TextEditingController();
  bool _started = false;
  Video? _video;
  Checklist? _list;
  ApprovalDraft? _draft;

  /// The draft the server kept, read with the list; null with none.
  ReviewDraft? _kept;

  /// Whether the kept draft was read, with a draft or with none. Until it
  /// is, nothing is written: a write would replace what it holds.
  bool _keptRead = false;

  /// A read of the kept draft in flight before the first write.
  bool _rereading = false;
  late final CurationApi _api;
  late final UnheardEnds _ends;
  late final _writer = DraftWriter<_Kept>(
    (k) => _api.saveDraft(
      widget.id,
      version: k.version,
      answers: k.answers,
      theme: k.theme,
      minAgeBand: k.band,
      note: k.note,
    ),
  );
  bool _checklistFailed = false;
  bool _refused = false;
  String? _done;

  /// Whether the video played to its end for this curator: told by the
  /// player here, by the kept draft, or by an end seen on the video's
  /// screen that the server has not heard yet. Once true it stays.
  bool _playedToEnd = false;

  /// Keeps the watched block (the one player's view and the line under
  /// it) across pages: each page is built anew, and a view built anew
  /// would load the video again, a line built anew be announced again.
  final _watched = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _api = AppScope.of(context).curation;
    _ends = AppScope.of(context).unheardEnds;
    _note.addListener(_noteChanged);
    _bandReason.addListener(_bandReasonChanged);
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    _video = widget.video;
    if (_video case final video?) {
      openPlayer(video.youtubeId, onEnded: _ended);
    } else {
      scheduleMicrotask(_readVideo);
    }
    scheduleMicrotask(_readChecklist);
  }

  /// Opened directly: the video is read to be named, and for its length,
  /// which decides the questions asked. A video gone from the queue goes
  /// back to it; any other failure offers to try again.
  Future<void> _readVideo() async {
    if (!mounted) return;
    try {
      final detail = await AppScope.of(context).curation.video(widget.id);
      if (!mounted) return;
      setState(() {
        _video = detail.video;
        _startDraft();
      });
      openPlayer(detail.video.youtubeId, onEnded: _ended);
    } on Object catch (e) {
      if (!mounted || leaveForQueue(context, e)) return;
      setState(() => _checklistFailed = true);
    }
  }

  /// Tells the draft the video played to its end, which an approval
  /// needs; a report that fails is kept for the approval to send again.
  void _ended() {
    if (mounted) setState(() => _playedToEnd = true);
    if (_video case final video?) {
      unawaited(_ends.report(widget.id, video.round));
    }
  }

  /// Picks up an end the kept draft or this device already knows of.
  void _knowEnd(ReviewDraft? kept) {
    if (kept?.playedToEndAt != null ||
        (_video != null && _ends.seen(widget.id, _video!.round))) {
      _playedToEnd = true;
    }
  }

  /// The questions depend on the video's length, so the answers start
  /// once both the list and the video are read, from the draft the server
  /// kept when there is one.
  void _startDraft() {
    if (_draft != null) return;
    if ((_list, _video) case (final list?, final video?)) {
      final d = ApprovalDraft(list, length: video.duration);
      if (_kept case final kept?) d.restore(kept);
      // Coming back opens where the answers stopped.
      d.resume();
      _knowEnd(_kept);
      _draft = d;
      _note.text = d.note ?? '';
      // A reason written before the list was read again still stands.
      d.bandReason = _bandReason.text;
    }
  }

  /// Hands the server the review as it stands; it never says when it
  /// could not, since the next change writes it all again. While the kept
  /// draft is unread, it is read first and picked up beneath the changes
  /// made here; a read that fails again writes nothing.
  void _keep(ApprovalDraft d) {
    if (_keptRead) return _write(d);
    if (!_rereading) unawaited(_rereadThenKeep(d));
  }

  Future<void> _rereadThenKeep(ApprovalDraft d) async {
    _rereading = true;
    try {
      final kept = await _api.draft(widget.id);
      if (!mounted || d != _draft) return;
      _keptRead = true;
      if (kept != null) {
        setState(() {
          d.restoreBeneath(kept);
          _knowEnd(kept);
        });
        // Set only when it changed: setting it moves the cursor of a
        // curator typing in it.
        if (_note.text != (d.note ?? '')) _note.text = d.note ?? '';
      }
      _write(d);
    } on Exception {
      // Still unread: the next change tries again.
    } finally {
      _rereading = false;
    }
  }

  void _write(ApprovalDraft d) {
    final s = d.snapshot;
    _writer.write((
      version: d.checklist.version,
      answers: s.answers,
      theme: s.theme,
      band: s.band,
      note: s.note,
    ));
  }

  void _noteChanged() {
    final d = _draft;
    if (d == null) return;
    final note = _note.text.trim().isEmpty ? null : _note.text;
    if (note == d.note) return;
    d.note = note;
    _keep(d);
  }

  /// The reason for an older band is not kept in the draft: it lets the
  /// page go on, and is sent with the approval.
  void _bandReasonChanged() {
    final d = _draft;
    if (d == null || d.bandReason == _bandReason.text) return;
    _update(() => d.bandReason = _bandReason.text);
  }

  /// Tries again what failed to read: the video, the list, or both.
  void _retry() {
    if (_video == null) unawaited(_readVideo());
    unawaited(_readChecklist());
  }

  /// The list and the draft are read on every arrival, and again when the
  /// server says the list changed; a new list starts over with the answers
  /// the server kept, those to questions left unchanged, on the first page
  /// with an open question. The old answers go first, so a failed read offers to try
  /// again rather than the outdated list. A draft that fails to read
  /// counts as none, and is read again before anything is written.
  Future<void> _readChecklist() async {
    if (!mounted) return;
    setState(() {
      _list = null;
      _draft = null;
      _checklistFailed = false;
      _keptRead = false;
    });
    var read = false;
    final kept = _api.draft(widget.id).then<ReviewDraft?>((d) {
      read = true;
      return d;
    }, onError: (Object _) => null);
    try {
      final list = await _api.checklist();
      final draft = await kept;
      if (!mounted) return;
      setState(() {
        _list = list;
        _kept = draft;
        _keptRead = read;
        _startDraft();
      });
    } on Object catch (e) {
      if (!mounted || leaveForQueue(context, e)) return;
      setState(() => _checklistFailed = true);
    }
  }

  @override
  void dispose() {
    _send.dispose();
    _note.dispose();
    _bandReason.dispose();
    super.dispose();
  }

  bool get _idle => !_send.blocked;

  /// Any change takes away the last error and the refused choices' line.
  void _update(void Function() change) {
    _send.clearMessage();
    setState(() {
      _refused = false;
      change();
    });
  }

  /// A change the server keeps in the draft.
  void _change(ApprovalDraft d, void Function() change) {
    _update(change);
    _keep(d);
  }

  void _forward() => _update(_draft!.forward);

  /// One page back; from the first page back to the video, and from the
  /// done state to the queue.
  void _back() {
    final d = _draft;
    if (_done != null) {
      context.go(Routes.curation);
    } else if (d == null || !d.back()) {
      context.go(Routes.review(widget.id));
    } else {
      _update(() {});
    }
  }

  /// The band's arrow: out of the questions to the video's screen in one
  /// step, wherever they stand, the draft kept as it is; from the done
  /// state, to the queue.
  void _leave() =>
      context.go(_done != null ? Routes.curation : Routes.review(widget.id));

  void _toRefusal(ApprovalDraft d) =>
      context.go(Routes.refuse(widget.id, items: d.refusing), extra: _video);

  /// Sends the answers: an approval with its theme and band, or, for the
  /// team, without them and with the optional note.
  ///
  /// An end report that failed, here or on the video's screen, is sent
  /// once more first, since the server refuses an approval it never heard
  /// the end of.
  Future<void> _submit(ApprovalDraft d) async {
    final team = d.outcome == ApprovalOutcome.team;
    final note = _note.text.trim();
    final ok = await _send.run(() async {
      await _ends.resend(widget.id, _video!.round);
      await _api.approve(
        widget.id,
        theme: team ? null : d.theme,
        minAgeBand: team ? null : d.band,
        version: d.checklist.version,
        answers: d.answers,
        note: team && note.isNotEmpty ? note : null,
        bandReason: team ? null : d.reasonToSend,
      );
    }, handle: (e) => _handle(e, d));
    if (!ok || !mounted) return;
    // Decided: nothing is left to watch.
    unawaited(closePlayer());
    setState(() => _done = team ? doubtSent : approved);
  }

  bool _handle(ApiError e, ApprovalDraft d) {
    if (leaveForQueue(context, e)) return true;
    switch (e.code) {
      case 'validation' when d.outcome == ApprovalOutcome.approve:
        setState(() {
          _refused = true;
          d
            ..theme = null
            ..keepComputed()
            ..change(d.topicPage);
        });
        _keep(d);
        return true;
      case 'checklist_refuses':
        _toRefusal(d);
        return true;
      case 'checklist_band':
        setState(() {
          d
            ..band = null
            ..change(d.topicPage);
        });
        _keep(d);
        return false;
      case 'checklist_outdated':
        unawaited(_readChecklist());
        return false;
      // The server heard no end in this round: the line and "Aprovar"
      // say so again, and the end seen here is forgotten.
      case 'not_watched':
        setState(() => _playedToEnd = false);
        if (_video case final video?) _ends.forget(widget.id, video.round);
        return false;
    }
    return false;
  }

  /// A video already in the app leaves it while the team decides; one
  /// waiting for its first decision just keeps waiting.
  bool get _revisit =>
      _video?.revisit == true || _video?.state == VideoState.approved;

  void _openCriteria() => AppScope.of(context).links.open(kCurationUrl);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: ListenableBuilder(
      listenable: _send,
      builder: (context, _) => FieldLayout(
        // A new page opens at its top, not where the last one was scrolled.
        key: ValueKey<Object?>(_done ?? _draft?.page),
        // The window stands for the video: no title over the questions.
        title: null,
        // Decided, the player is gone and nothing is left to watch.
        watch: _done == null && _video != null ? _watch() : null,
        onBack: _leave,
        backLabel: _done != null ? 'Voltar para a fila' : leaveForVideo,
        children: switch (_done) {
          final done? => [
            Notice(done),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Voltar para a fila',
              onPressed: () => context.go(Routes.curation),
            ),
          ],
          null => _form(),
        },
      ),
    ),
  );

  List<Widget> _form() {
    final d = _draft;
    if (d == null) {
      if (!_checklistFailed) {
        return const [FamilyPlaceholder(label: 'Carregando as perguntas')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _retry),
      ];
    }
    final g = d.group;
    if (g != null) return d.page == 0 ? _before(d, g) : _step(d, g);
    return d.page == d.topicPage ? _topic(d) : _review(d);
  }

  /// The video's window and, under it, whether it played to its end.
  Widget _watch() => KeyedSubtree(
    key: _watched,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        playerWindow(failed: flowPlayerFailed),
        const SizedBox(height: Space.md),
        EndLine(ended: _playedToEnd),
      ],
    ),
  );

  Widget _line(String words) => Semantics(
    liveRegion: true,
    child: Text(words, style: Theme.of(context).textTheme.bodyLarge),
  );

  List<Widget> _questions(ApprovalDraft d, ChecklistGroup g) => [
    for (final (i, item) in g.items.indexed) ...[
      if (i > 0) const SizedBox(height: Space.xl),
      AnswerChoice(
        question: item.text,
        value: d.answerOf(item),
        // A tie to the channel is a fact the curator knows: no "Não sei".
        unsure: item.rule != ChecklistRule.conflict,
        onChanged: _idle ? (a) => _change(d, () => d.answer(item, a)) : null,
      ),
    ],
  ];

  /// The last send's error, the primary with its hint, and "Voltar".
  List<Widget> _foot({
    required String label,
    required VoidCallback? onPressed,
    String? hint,
    bool back = true,
  }) => [
    const SizedBox(height: Space.xxl),
    if (_send.message case final message?) ...[
      ErrorNote(message),
      const SizedBox(height: Space.lg),
    ],
    PrimaryButton(
      label: label,
      busy: _send.busy,
      onPressed: _idle ? onPressed : null,
    ),
    if (hint != null)
      SubmitHint(hint, visible: onPressed == null, reserve: true),
    if (back) ...[
      const SizedBox(height: Space.sm),
      QuietAction(label: 'Voltar', onPressed: _back),
    ],
  ];

  List<Widget> _before(ApprovalDraft d, ChecklistGroup g) {
    final text = Theme.of(context).textTheme;
    return [
      Semantics(header: true, child: Text(g.title, style: text.titleMedium)),
      const SizedBox(height: Space.md),
      Text(
        checkedByApp,
        style: text.bodyMedium?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xl),
      ..._questions(d, g),
      if (d.conflict) ...[
        const SizedBox(height: Space.xl),
        _line(conflictLine),
        ..._foot(
          label: 'Voltar para a fila',
          onPressed: () => context.go(Routes.curation),
          back: false,
        ),
      ] else
        ..._foot(
          // Changed from the review, it goes back to the summary.
          label: d.nextIsReview ? seeSummary : startQuestions,
          onPressed: d.canGoOn ? _forward : null,
          hint: stepHint,
        ),
    ];
  }

  List<Widget> _step(ApprovalDraft d, ChecklistGroup g) {
    final text = Theme.of(context).textTheme;
    final step = d.page;
    final of = d.stepCount;
    return [
      // Announced as the page changes: "Etapa 2 de 5, Linguagem e respeito".
      Semantics(
        container: true,
        header: true,
        liveRegion: true,
        label: '${stepLabel(step, of)}, ${g.title}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StepMarks(step: step, of: of, word: 'Etapa'),
            const SizedBox(height: Space.sm),
            Text(g.title, style: text.titleMedium),
          ],
        ),
      ),
      const SizedBox(height: Space.xl),
      ..._questions(d, g),
      ..._shortcut(d, g),
      ..._foot(
        label: d.nextIsTopic
            ? chooseTopic
            : d.nextIsReview
            ? seeSummary
            : nextStep,
        onPressed: d.canGoOn ? _forward : null,
        hint: stepHint,
      ),
    ];
  }

  /// After a step's last question, the way to answer "Não" to the ones
  /// still open, read only once the questions are: with none answered,
  /// "Nada disso acontece no vídeo"; with some, "O resto…" and how many it
  /// marks; with none open, nothing.
  List<Widget> _shortcut(ApprovalDraft d, ChecklistGroup g) {
    final open = d.openIn(g);
    if (open == 0) return const [];
    final none = open == g.items.length;
    return [
      const SizedBox(height: Space.xl),
      OutlinedButton(
        onPressed: _idle ? () => _change(d, () => d.noneOf(g)) : null,
        // The count is read with the button, as its hint.
        child: Semantics(
          hint: none ? null : restLine(open),
          child: Text(
            none ? noneHappens : restHappens,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      if (!none) ...[
        const SizedBox(height: Space.sm),
        // Read with the button already.
        ExcludeSemantics(
          child: Text(
            restLine(open),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ),
      ],
    ];
  }

  /// The band page: the band the answers give, stated, with each answer
  /// that moved it (or the length, when only the length did); the rule and
  /// its criteria; the theme; then the ways on.
  List<Widget> _topic(ApprovalDraft d) {
    final text = Theme.of(context).textTheme;
    final moved = d.bandAnswers;
    return [
      Semantics(
        header: true,
        child: Text(bandStatement(d.computedBand), style: text.headlineSmall),
      ),
      const SizedBox(height: Space.xs),
      for (final (item, a) in moved)
        BandAnswerRow(
          question: item.text,
          word: a.word,
          onChange: _idle
              ? () => _update(() => d.changeFromTopic(d.pageOf(item)))
              : null,
        ),
      if (moved.isEmpty && d.computedBand != d.answersBand)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Text(tooLongForYoungestLine, style: text.bodyLarge),
        ),
      const SizedBox(height: Space.xs),
      Text(curationRule, style: text.bodyMedium),
      Semantics(
        link: true,
        label: curationCriteriaLink,
        excludeSemantics: true,
        onTap: _openCriteria,
        child: QuietAction(
          label: curationCriteriaLink,
          onPressed: _openCriteria,
        ),
      ),
      const SizedBox(height: Space.xl),
      Semantics(header: true, child: Text('Tema', style: text.titleMedium)),
      if (_refused) ...[
        const SizedBox(height: Space.xs),
        Semantics(
          liveRegion: true,
          child: Text(
            approvalRefused,
            style: text.bodySmall?.copyWith(color: context.palette.error),
          ),
        ),
      ],
      const SizedBox(height: Space.md),
      for (final (i, t) in VideoTheme.values.indexed)
        if (t != VideoTheme.unknown) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          SelectableRow(
            // Read with its meaning, as it is shown.
            label: '${t.label}, ${t.definition}',
            text: t.label,
            detail: t.definition,
            selected: t == d.theme,
            onTap: _idle ? () => _change(d, () => d.theme = t) : null,
          ),
        ],
      if (d.olderOpen) ..._older(d) else ..._confirm(d),
    ];
  }

  /// "Confirmar" the band the answers give, and, unless they give the
  /// oldest, "É para mais velhos".
  List<Widget> _confirm(ApprovalDraft d) => [
    ..._foot(
      label: confirmBandLabel(d.computedBand),
      onPressed: d.canGoOn ? () => _change(d, d.confirmBand) : null,
      hint: themeHint,
      back: false,
    ),
    if (d.olderBands.isNotEmpty) ...[
      const SizedBox(height: Space.sm),
      OutlinedButton(
        onPressed: _idle ? () => _change(d, d.askOlder) : null,
        child: const Text(olderLabel, textAlign: TextAlign.center),
      ),
    ],
    const SizedBox(height: Space.sm),
    QuietAction(label: 'Voltar', onPressed: _back),
  ];

  /// The older bands only, why, "Continuar", and the way back to
  /// confirming.
  List<Widget> _older(ApprovalDraft d) {
    final text = Theme.of(context).textTheme;
    return [
      const SizedBox(height: Space.xl),
      Semantics(
        header: true,
        child: Text('A partir de', style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      for (final (i, b) in d.olderBands.indexed) ...[
        if (i > 0) const SizedBox(height: Space.sm),
        SelectableRow(
          label: b.label,
          selected: b == d.band,
          onTap: _idle ? () => _change(d, () => d.band = b) : null,
        ),
      ],
      const SizedBox(height: Space.lg),
      ReasonField(
        controller: _bandReason,
        label: olderReasonLabel,
        enabled: _idle,
        maxLength: ApprovalDraft.bandReasonMax,
      ),
      ..._foot(
        label: continueLabel,
        onPressed: d.canGoOn ? _forward : null,
        hint: d.theme == null
            ? themeHint
            : d.band == null
            ? olderBandHint
            : olderReasonHint,
        back: false,
      ),
      const SizedBox(height: Space.sm),
      QuietAction(
        label: stayWithLabel(d.computedBand),
        onPressed: _idle ? () => _change(d, d.keepComputed) : null,
      ),
      // Apart, so the two never read as one block at large text.
      const SizedBox(height: Space.sm),
      QuietAction(label: 'Voltar', onPressed: _back),
    ];
  }

  List<Widget> _review(ApprovalDraft d) {
    final text = Theme.of(context).textTheme;
    final outcome = d.outcome;
    final team = outcome == ApprovalOutcome.team;
    VoidCallback? changeTo(int page) =>
        _idle ? () => _update(() => d.change(page)) : null;
    return [
      // Announced as the page opens, as a step's header is.
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(reviewTitle, style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      for (final (i, g) in d.checklist.groups.indexed)
        if (d.marked(g) case final marked)
          _SummaryLine(
            title: g.title,
            lines: marked.isEmpty
                ? const [allNo]
                : [for (final (item, a) in marked) '${a.word}: ${item.text}'],
            quiet: marked.isEmpty,
            onChange: changeTo(i),
          ),
      if (outcome == ApprovalOutcome.approve)
        _SummaryLine(
          title: topicTitle,
          lines: [
            CurationWords.joined([?d.theme?.label, ?d.band?.label]),
            // Why the band is older than the answers give.
            ?d.reasonToSend,
          ],
          onChange: changeTo(d.topicPage),
        ),
      const SizedBox(height: Space.xl),
      Text(differenceReminder, style: text.bodyMedium),
      if (team) ...[
        const SizedBox(height: Space.xl),
        _line(_revisit ? doubtRevisitLine : doubtLine),
        const SizedBox(height: Space.md),
        TextField(
          controller: _note,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 2,
          maxLines: null,
          maxLength: 500,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          decoration: const InputDecoration(
            labelText: doubtNoteLabel,
            alignLabelWithHint: true,
          ),
        ),
      ],
      ..._foot(
        label: switch (outcome) {
          ApprovalOutcome.approve => approveLabel,
          ApprovalOutcome.refuse => refuseLabel,
          ApprovalOutcome.team => teamLabel,
        },
        onPressed: switch (outcome) {
          ApprovalOutcome.refuse => () => _toRefusal(d),
          // The server takes no approval of a video not played to its end.
          ApprovalOutcome.approve when !_playedToEnd => null,
          _ => () => _submit(d),
        },
        hint: outcome == ApprovalOutcome.approve ? watchHint : null,
      ),
    ];
  }
}

/// What the draft keeps: the list version the answers were given to,
/// with the rest of the review.
typedef _Kept = ({
  String version,
  Map<String, ChecklistAnswer> answers,
  VideoTheme? theme,
  AgeBand? band,
  String? note,
});

/// One line of the review: a step's title, what it answered other than
/// "Não" (or, [quiet], "tudo Não"), and "mudar", which goes back to it.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.title,
    required this.lines,
    required this.onChange,
    this.quiet = false,
  });

  final String title;
  final List<String> lines;
  final VoidCallback? onChange;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = quiet
        ? text.bodyMedium?.copyWith(color: context.palette.muted)
        : text.bodyLarge;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.titleMedium),
        const SizedBox(height: Space.xs),
        for (final line in lines) Text(line, style: style),
      ],
    );
    final change = QuietAction(
      label: changeLabel,
      // The same word on every line: say which step it changes.
      semanticsLabel: '$changeLabel: $title',
      inline: true,
      onPressed: onChange,
    );
    // At large text a column beside the words would leave them a word or
    // two a line: "mudar" goes under them.
    final large = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [words, change],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: words),
                const SizedBox(width: Space.sm),
                change,
              ],
            ),
    );
  }
}
