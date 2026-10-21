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
import 'checklist_draft.dart';
import 'checklist_form.dart';
import 'curation.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'video_heading.dart';
import 'words.dart';

/// Over the list: how to answer it.
const checklistLead = 'Assista ao vídeo até o fim e responda, grupo por grupo.';

/// Under the primary until every group is answered.
const checklistHint = 'Responda cada grupo de perguntas acima.';

/// Under the primary until a theme and a band are chosen.
const approveHint = 'Escolha um tema e uma idade acima.';

/// The done state's notices.
const approved = 'Sua aprovação foi registrada.';
const doubtSent = 'Sua dúvida foi enviada para a equipe da Coding4u.';

/// `validation` on an approval: the choices are marked, and
/// cleared to choose again.
const approvalRefused =
    'Essa escolha não foi aceita. Escolha o tema e a idade de novo.';

/// What the marks mean, said over the primary.
const refusingLine =
    'Com o que você marcou, o vídeo não pode ser aprovado. Siga para a recusa.';
const conflictLine =
    'Você tem vínculo com este canal, então a revisão dele fica com outros '
    'curadores.';
const invalidReasonLine =
    'Família, religião, cor ou deficiência diferente da sua não é motivo '
    'para recusar. Desmarque essa resposta.';
const bandLine =
    'Com o ritmo que você marcou, o vídeo não serve para 2 a 4 anos.';

/// A doubt on a video still waiting for its first decision, and on one
/// already in the app, revisited.
const doubtLine =
    'Sua dúvida vai para a equipe da Coding4u, que decide. O vídeo fica '
    'esperando a decisão da equipe.';
const doubtRevisitLine =
    'Sua dúvida vai para a equipe da Coding4u, que decide. O vídeo sai do '
    'app até lá.';

/// The doubt's optional note.
const doubtNoteLabel = 'Conte sua dúvida (opcional)';

/// Over the bands: the rating every video must have.
const curationRule = 'Todo vídeo precisa ser Livre.';

/// The link to the criteria of each band, on the site.
const curationCriteriaLink = 'Veja os critérios de cada idade';

/// `/curadoria/:id/aprovar`: the checklist the server holds, group by
/// group, then one theme of six and a band of three. What the curator
/// marks decides the primary: a question that refuses leads to the
/// refusal with it marked; a tie to the channel back to the queue; a
/// doubt sends the review to the team with an optional note; otherwise
/// "Aprovar". Each is sent once, then the done state back to the queue.
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
  ChecklistDraft? _draft;
  bool _checklistFailed = false;
  VideoTheme? _theme;
  AgeBand? _band;
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
  /// the queue goes back to it; any other failure leaves the form as is,
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
  /// changed; a new list starts unanswered. The old answers go first, so a
  /// failed read offers to try again rather than the outdated list.
  Future<void> _readChecklist() async {
    if (!mounted) return;
    setState(() {
      _draft = null;
      _checklistFailed = false;
    });
    try {
      final list = await AppScope.of(context).curation.checklist();
      if (mounted) setState(() => _draft = ChecklistDraft(list));
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

  void _changed() {
    _send.clearMessage();
    setState(() => _refused = false);
  }

  void _toRefusal(ChecklistDraft draft) => context.go(
    Routes.refuse(widget.id, items: draft.refusing),
    extra: _video,
  );

  Future<void> _approve(
    ChecklistDraft draft,
    VideoTheme theme,
    AgeBand band,
  ) async {
    final api = AppScope.of(context).curation;
    final note = _note.text.trim();
    final doubt = draft.doubt;
    final ok = await _send.run(
      () => api.approve(
        widget.id,
        theme: theme,
        minAgeBand: band,
        version: draft.checklist.version,
        answers: draft.answers,
        note: doubt && note.isNotEmpty ? note : null,
      ),
      handle: (e) => _handle(e, draft),
    );
    if (ok && mounted) setState(() => _done = doubt ? doubtSent : approved);
  }

  bool _handle(ApiError e, ChecklistDraft draft) {
    if (leaveForQueue(context, e)) return true;
    switch (e.code) {
      case 'validation':
        setState(() {
          _refused = true;
          _theme = null;
          _band = null;
        });
        return true;
      case 'checklist_refuses':
        _toRefusal(draft);
        return true;
      case 'checklist_outdated':
        unawaited(_readChecklist());
        return false;
    }
    return false;
  }

  /// A video already in the app leaves it while the team decides a doubt;
  /// one waiting for its first decision just keeps waiting.
  bool get _revisit =>
      _video?.revisit == true || _video?.state == VideoState.approved;

  void _openCriteria() => AppScope.of(context).links.open(kCurationUrl);

  void _pick(void Function() pick) {
    _send.clearMessage();
    setState(() {
      _refused = false;
      pick();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _send,
    builder: (context, _) => FieldLayout(
      title: 'Aprovar',
      onBack: () => context.go(
        _done != null ? Routes.curation : Routes.review(widget.id),
      ),
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
  );

  List<Widget> _form() {
    final draft = _draft;
    if (draft == null) {
      if (!_checklistFailed) {
        return const [FamilyPlaceholder(label: 'Carregando as perguntas')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _readChecklist),
      ];
    }
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final idle = !_send.blocked;
    final theme = _theme;
    final band = _band;
    final refusing = draft.refusing.isNotEmpty;
    final barred = draft.youngestBarred && band == AgeBand.upTo4;
    final choosing = !draft.conflict && !refusing;
    final String label;
    VoidCallback? action;
    if (draft.conflict) {
      label = 'Voltar para a fila';
      action = () => context.go(Routes.curation);
    } else if (refusing) {
      label = 'Ir para a recusa';
      action = idle ? () => _toRefusal(draft) : null;
    } else {
      label = draft.doubt ? 'Enviar dúvida' : 'Aprovar';
      action =
          idle &&
              draft.complete &&
              !draft.invalidReason &&
              !barred &&
              theme != null &&
              band != null
          ? () => _approve(draft, theme, band)
          : null;
    }
    Widget line(String words) =>
        Semantics(liveRegion: true, child: Text(words, style: text.bodyLarge));
    return [
      Text(checklistLead, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      ChecklistForm(draft: draft, onChanged: idle ? _changed : null),
      const SizedBox(height: Space.xxl),
      if (draft.conflict) ...[
        line(conflictLine),
        const SizedBox(height: Space.lg),
      ] else if (refusing) ...[
        line(refusingLine),
        const SizedBox(height: Space.lg),
      ],
      // Said whatever else is marked: the answer must be taken back.
      if (draft.invalidReason) ...[
        line(invalidReasonLine),
        const SizedBox(height: Space.lg),
      ],
      if (choosing) ...[
        Text('Tema', style: text.titleMedium),
        if (_refused) ...[
          const SizedBox(height: Space.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              approvalRefused,
              style: text.bodySmall?.copyWith(color: p.error),
            ),
          ),
        ],
        const SizedBox(height: Space.md),
        for (final (i, t) in VideoTheme.values.indexed)
          if (t != VideoTheme.unknown) ...[
            if (i > 0) const SizedBox(height: Space.sm),
            SelectableRow(
              label: t.label,
              selected: t == theme,
              onTap: idle ? () => _pick(() => _theme = t) : null,
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
          value: band,
          onChanged: idle ? (b) => _pick(() => _band = b) : null,
        ),
        if (barred) ...[const SizedBox(height: Space.sm), line(bandLine)],
        if (draft.doubt) ...[
          const SizedBox(height: Space.xl),
          line(_revisit ? doubtRevisitLine : doubtLine),
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
      ],
      const SizedBox(height: Space.xl),
      if (_send.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(label: label, busy: _send.busy, onPressed: action),
      SubmitHint(
        draft.complete ? approveHint : checklistHint,
        visible: choosing && (!draft.complete || theme == null || band == null),
        reserve: true,
      ),
    ];
  }
}
