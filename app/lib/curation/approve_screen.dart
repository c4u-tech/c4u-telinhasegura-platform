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
import '../family/profile_fields.dart' show AgeBandChoice, SelectableRow;
import '../family/widgets.dart' show FamilyPlaceholder;
import '../legal/legal_links.dart' show kCurationUrl;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'answer_choice.dart';
import 'approval_draft.dart';
import 'curation.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'video_heading.dart';
import 'words.dart';

/// "Antes de começar": what the app checked when the video was suggested.
const checkedByApp =
    '✓ Já conferido pelo app: feito para crianças no YouTube, pode ser '
    'exibido aqui, não é ao vivo e cabe no tempo máximo.';

/// The primaries: of "Antes de começar", of a step, and of the last step
/// when the video can be approved.
const watchAndAnswer = 'Assistir e responder';
const nextStep = 'Próxima etapa';
const chooseTopic = 'Escolher tema e idade';

/// A step's shortcut, and the line that parts it from the questions.
const noneHappens = 'Nada disso acontece no vídeo';
const orOneByOne = 'ou responda uma a uma';

/// Under a page's primary until it can go on.
const stepHint = 'Responda todas as perguntas desta etapa.';
const approveHint = 'Escolha um tema e uma idade acima.';

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

/// Under the bands when the pace rules out the youngest.
const fastPaceLine = 'Ritmo agitado não serve para 2 a 4 anos.';

/// The done state's notices.
const approved = 'Sua aprovação foi registrada.';
const doubtSent = 'Sua dúvida foi enviada para a equipe da Coding4u.';

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

/// "Etapa 2 de 5".
String stepLabel(int step, int of) => 'Etapa $step de $of';

/// `/curadoria/:id/aprovar`: the checklist the server holds, one page at
/// a time. "Antes de começar" (the list's first group, under what the app
/// already checked), then one step per remaining group, each going on only
/// once every question is answered; then the theme and band, only when
/// the answers approve; then "Confira antes de enviar", whose final button
/// says what happens: "Aprovar", "Recusar" (the refusal, with the
/// questions ticked) or "Enviar para a equipe" (an approval the server
/// holds as a doubt). A tie to the channel ends on the first page. Back,
/// on screen or from the system, goes one page back; leaving drops the
/// answers.
class ApproveScreen extends StatefulWidget {
  const ApproveScreen({super.key, required this.id, this.video});

  final String id;

  /// The video as the review read it; opened directly, it is read here.
  final Video? video;

  @override
  State<ApproveScreen> createState() => _ApproveScreenState();
}

class _ApproveScreenState extends State<ApproveScreen> {
  final _send = Submission();
  final _note = TextEditingController();
  bool _started = false;
  Video? _video;
  ApprovalDraft? _draft;
  bool _checklistFailed = false;
  bool _refused = false;
  String? _done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    _video = widget.video;
    if (_video == null) scheduleMicrotask(_readVideo);
    scheduleMicrotask(_readChecklist);
  }

  /// Opened directly: the video is read to be named. A video gone from
  /// the queue goes back to it; any other failure leaves the flow as is,
  /// since the decision does not need the name to be sent.
  Future<void> _readVideo() async {
    if (!mounted) return;
    try {
      final detail = await AppScope.of(context).curation.video(widget.id);
      if (mounted) setState(() => _video = detail.video);
    } on Object catch (e) {
      if (mounted) leaveForQueue(context, e);
    }
  }

  /// The list is read on every arrival, and again when the server says it
  /// changed; a new list starts over on its first page, unanswered. The
  /// old answers go first, so a failed read offers to try again rather
  /// than the outdated list.
  Future<void> _readChecklist() async {
    if (!mounted) return;
    setState(() {
      _draft = null;
      _checklistFailed = false;
    });
    try {
      final list = await AppScope.of(context).curation.checklist();
      if (mounted) setState(() => _draft = ApprovalDraft(list));
    } on Object catch (e) {
      if (!mounted || leaveForQueue(context, e)) return;
      setState(() => _checklistFailed = true);
    }
  }

  @override
  void dispose() {
    _send.dispose();
    _note.dispose();
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

  void _toRefusal(ApprovalDraft d) =>
      context.go(Routes.refuse(widget.id, items: d.refusing), extra: _video);

  /// Sends the answers: an approval with its theme and band, or, for the
  /// team, without them and with the optional note.
  Future<void> _submit(ApprovalDraft d) async {
    final api = AppScope.of(context).curation;
    final team = d.outcome == ApprovalOutcome.team;
    final note = _note.text.trim();
    final ok = await _send.run(
      () => api.approve(
        widget.id,
        theme: team ? null : d.theme,
        minAgeBand: team ? null : d.band,
        version: d.checklist.version,
        answers: d.answers,
        note: team && note.isNotEmpty ? note : null,
      ),
      handle: (e) => _handle(e, d),
    );
    if (ok && mounted) setState(() => _done = team ? doubtSent : approved);
  }

  bool _handle(ApiError e, ApprovalDraft d) {
    if (leaveForQueue(context, e)) return true;
    switch (e.code) {
      case 'validation' when d.outcome == ApprovalOutcome.approve:
        setState(() {
          _refused = true;
          d
            ..theme = null
            ..band = null
            ..change(d.topicPage);
        });
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
        return false;
      case 'checklist_outdated':
        unawaited(_readChecklist());
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
        title: 'Aprovar',
        onBack: _back,
        children: [
          if (_video case final video?) ...[
            VideoHeading(video),
            const SizedBox(height: Space.xl),
          ],
          ...(switch (_done) {
            final done? => [
              Notice(done),
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: 'Voltar para a fila',
                onPressed: () => context.go(Routes.curation),
              ),
            ],
            null => _form(),
          }),
        ],
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
        PrimaryButton(label: 'Tentar de novo', onPressed: _readChecklist),
      ];
    }
    final g = d.group;
    if (g != null) return d.page == 0 ? _before(d, g) : _step(d, g);
    return d.page == d.topicPage ? _topic(d) : _review(d);
  }

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
        onChanged: _idle ? (a) => _update(() => d.answer(item, a)) : null,
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
          label: watchAndAnswer,
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
      OutlinedButton(
        onPressed: _idle ? () => _update(() => d.noneOf(g)) : null,
        child: const Text(noneHappens),
      ),
      const SizedBox(height: Space.md),
      Text(
        orOneByOne,
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xl),
      ..._questions(d, g),
      ..._foot(
        label: d.nextIsTopic ? chooseTopic : nextStep,
        onPressed: d.canGoOn ? _forward : null,
        hint: stepHint,
      ),
    ];
  }

  List<Widget> _topic(ApprovalDraft d) {
    final text = Theme.of(context).textTheme;
    final barred = d.youngestBarred;
    return [
      Text('Tema', style: text.titleMedium),
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
            label: t.label,
            selected: t == d.theme,
            onTap: _idle ? () => _update(() => d.theme = t) : null,
          ),
        ],
      const SizedBox(height: Space.xl),
      Text('A partir de', style: text.titleMedium),
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
      const SizedBox(height: Space.md),
      AgeBandChoice(
        value: d.band,
        disabled: barred ? const {AgeBand.upTo4} : const {},
        onChanged: _idle ? (b) => _update(() => d.band = b) : null,
      ),
      if (barred) ...[
        const SizedBox(height: Space.sm),
        Text(fastPaceLine, style: text.bodyMedium),
      ],
      ..._foot(
        label: nextStep,
        onPressed: d.canGoOn ? _forward : null,
        hint: approveHint,
      ),
    ];
  }

  List<Widget> _review(ApprovalDraft d) {
    final text = Theme.of(context).textTheme;
    final outcome = d.outcome;
    final team = outcome == ApprovalOutcome.team;
    VoidCallback? changeTo(int page) =>
        _idle ? () => _update(() => d.change(page)) : null;
    return [
      Semantics(
        header: true,
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
        onPressed: outcome == ApprovalOutcome.refuse
            ? () => _toRefusal(d)
            : () => _submit(d),
      ),
    ];
  }
}

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                const SizedBox(height: Space.xs),
                for (final line in lines) Text(line, style: style),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          QuietAction(
            label: changeLabel,
            // The same word on every line: say which step it changes.
            semanticsLabel: '$changeLabel: $title',
            inline: true,
            onPressed: onChange,
          ),
        ],
      ),
    );
  }
}
