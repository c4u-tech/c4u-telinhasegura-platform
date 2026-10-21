import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import 'adult_window.dart';
import 'curation.dart';
import 'role_gate.dart';
import 'video_heading.dart';
import 'words.dart';

/// An approval with every answer "ok", and one from before the list.
const nothingMarked = 'Nada marcado';
const beforeTheList = 'Aprovado antes da lista de perguntas';

/// In the marks' place when the questions could not be read.
const marksFailed = 'Não foi possível ler as respostas.';

/// Back on the sample.
const auditGone = 'Essa aprovação já foi conferida.';
const auditOwn = 'Você revisou esse vídeo e não pode conferi\u2011lo.';
const auditChanged = 'Esse vídeo mudou desde a amostra.';
String agreedWith(String title) =>
    'Você concordou com a aprovação de “$title”.';
String disagreedWith(String title) =>
    'Registramos sua discordância sobre “$title”. Ele continua no app.';
String heldByAudit(String title) => 'Tiramos “$title” do app.';

/// `/moderacao/auditoria/:id`: one sampled video: its title, each approval
/// by displayed role with what it marked, the player, then "De acordo",
/// "Discordo" and, in clay, "Discordo e tirar do app". Each verdict goes
/// through [ReauthWrite]; a disagreement confirms full screen with
/// "Motivo".
class AuditVideoScreen extends StatefulWidget {
  const AuditVideoScreen({super.key, required this.candidate});

  final AuditCandidate candidate;

  @override
  State<AuditVideoScreen> createState() => _AuditVideoScreenState();
}

class _AuditVideoScreenState extends State<AuditVideoScreen> with AdultWindow {
  late final ReauthWrite _write;
  bool _started = false;
  Checklist? _checklist;
  bool _checklistFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    scheduleMicrotask(_readChecklist);
    openPlayer(widget.candidate.video.youtubeId);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  /// The marks are worded with the list; without it the approvals still
  /// show, by role, and a line says the answers could not be read.
  Future<void> _readChecklist() async {
    if (!mounted) return;
    setState(() => _checklistFailed = false);
    try {
      final list = await AppScope.of(context).curation.checklist();
      if (mounted) setState(() => _checklist = list);
    } on Object catch (e) {
      if (!mounted || takeLostRole(context, e)) return;
      setState(() => _checklistFailed = true);
    }
  }

  void _leave(String notice) => context.go(Routes.auditSample, extra: notice);

  bool _handle(ApiError e) {
    if (takeLostRole(context, e)) return true;
    switch (e.code) {
      case 'already_audited':
        _leave(auditGone);
        return true;
      case 'own_review':
        _leave(auditOwn);
        return true;
      case 'state_conflict' || 'not_found':
        _leave(auditChanged);
        return true;
    }
    return false;
  }

  Future<void> _verdict({
    required bool agree,
    String? reason,
    bool hold = false,
    required String notice,
  }) async {
    final api = AppScope.of(context).staff;
    final c = widget.candidate;
    final ok = await _write.write(
      () => api.auditApproval(
        videoId: c.video.id,
        round: c.round,
        agree: agree,
        reason: reason,
        hold: hold,
      ),
      handle: _handle,
    );
    if (ok && mounted) _leave(notice);
  }

  Future<void> _disagree({required bool hold}) async {
    final v = widget.candidate.video;
    unawaited(playback?.pause());
    final reason = await confirmWithReason(
      context,
      title: hold ? 'Tirar este vídeo do app?' : 'Discordar desta aprovação?',
      body: [
        if (hold)
          '“${v.title}” sai das prateleiras e fica retido para a moderação.'
        else
          '“${v.title}” continua no app. Sua discordância fica registrada.',
      ],
      action: hold ? 'Tirar do app' : 'Discordo',
    );
    if (reason == null || !mounted) return;
    await _verdict(
      agree: false,
      reason: reason,
      hold: hold,
      notice: hold ? heldByAudit(v.title) : disagreedWith(v.title),
    );
  }

  /// What an approval marked, one question per line; "Nada marcado" when
  /// every answer is "ok"; nothing while the list is read.
  String _marks(Review r) {
    if (r.answers == null) return beforeTheList;
    final list = _checklist;
    if (list == null) return '';
    final lines = CurationWords.marked(r, list);
    return lines.isEmpty ? nothingMarked : lines.join('\n');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) => FieldLayout(
      title: 'Conferir aprovação',
      onBack: () => context.go(Routes.auditSample),
      children: _body(),
    ),
  );

  List<Widget> _body() {
    final text = Theme.of(context).textTheme;
    final c = widget.candidate;
    final idle = !_write.blocked;
    return [
      VideoHeading(c.video),
      const SizedBox(height: Space.xl),
      Semantics(
        header: true,
        child: Text('Aprovações', style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      Doors(
        children: [
          for (final r in c.approvals)
            if ((CurationWords.review(r), _marks(r)) case (
              final who,
              final marks,
            ))
              // The row reads as one: who approved, then what was marked.
              DoorRow(
                title: who,
                semanticsLabel: marks.isEmpty ? who : '$who\n$marks',
                onTap: null,
                child: Text(marks, style: text.bodyMedium),
              ),
        ],
      ),
      if (_checklistFailed) ...[
        const SizedBox(height: Space.md),
        Semantics(
          liveRegion: true,
          child: Text(marksFailed, style: text.bodyLarge),
        ),
        QuietAction(label: 'Tentar de novo', onPressed: _readChecklist),
      ],
      const SizedBox(height: Space.xl),
      playerWindow(failed: 'Esse vídeo não abriu aqui.'),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'De acordo',
        busy: _write.busy,
        onPressed: idle
            ? () => _verdict(agree: true, notice: agreedWith(c.video.title))
            : null,
      ),
      const SizedBox(height: Space.lg),
      QuietAction(
        label: 'Discordo',
        onPressed: idle ? () => _disagree(hold: false) : null,
      ),
      const SizedBox(height: Space.xxl),
      QuietAction(
        label: 'Discordo e tirar do app',
        destructive: true,
        onPressed: idle ? () => _disagree(hold: true) : null,
      ),
    ];
  }
}
