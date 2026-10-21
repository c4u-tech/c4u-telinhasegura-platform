import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
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
import 'audit_video_screen.dart' show marksFailed;
import 'curation.dart';
import 'role_gate.dart';
import 'video_heading.dart';
import 'words.dart';

/// In the window's place when the player could not play the video:
/// the actions stay.
const heldPlayerFailed =
    'Esse vídeo não abriu aqui. Se ele não passa mais, você pode removê\u2011lo '
    'de vez.';

/// Back on the list when the video is no longer held (`state_conflict`, `not_found`).
const heldGone = 'Esse vídeo não está mais retido.';

/// Over the curators' doubts, with what each one marked.
const doubtsHeading = 'Dúvidas';

/// Over the families' notes, apart from the counts.
const notesHeading = 'O que as famílias escreveram';

/// Back on the list after "Reabrir para revisão".
String reopened(String title) =>
    '“$title” voltou para a fila da curadoria, numa nova rodada.';

/// Back on the list after "Remover de vez".
String removedForGood(String title) => 'Removemos “$title” de vez.';

/// What the audit that held the video said: "Auditoria: discordou — motivo".
String auditLine(HeldAudit audit) {
  final verdict = switch (audit.verdict) {
    AuditVerdict.agree => 'concordou',
    AuditVerdict.disagree => 'discordou',
    AuditVerdict.unknown => null,
  };
  final head = verdict == null ? 'Auditoria' : 'Auditoria: $verdict';
  final reason = audit.reason;
  return reason == null ? head : '$head \u2014 $reason';
}

/// One reason's reports: "Assustador · 2 denúncias".
String reportLine(ReportReason reason, int n) => CurationWords.joined([
  reason.label,
  n == 1 ? '1 denúncia' : '$n denúncias',
]);

/// `/moderacao/retidos/:id`: the held video's title and why it is held;
/// each refusal by displayed role with its reason; the reports by reason
/// with their counts, then, under their own heading, the families' notes
/// quoted, never who; the player, as on the review; then the primary
/// "Reabrir para revisão" and, quiet in clay at the foot, "Remover de
/// vez". Both confirm full screen with
/// "Motivo", sent with the write; only the removal goes through
/// [ReauthWrite]. There is no read of one held
/// video: the list is read and it found.
class HeldVideoScreen extends StatefulWidget {
  const HeldVideoScreen({super.key, required this.id});

  final String id;

  @override
  State<HeldVideoScreen> createState() => _HeldVideoScreenState();
}

class _HeldVideoScreenState extends State<HeldVideoScreen> with AdultWindow {
  late final ReauthWrite _write;
  bool _started = false;
  bool _failed = false;
  HeldVideo? _held;
  Checklist? _checklist;
  bool _marksFailed = false;

  /// The write running is the removal, whose action shows the progress.
  bool _removing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    final scope = AppScope.of(context);
    try {
      final all = await scope.staff.heldVideos();
      if (!mounted) return;
      final held = all.where((h) => h.video.id == widget.id).firstOrNull;
      if (held == null) return _leave(heldGone);
      setState(() => _held = held);
      openPlayer(held.video.youtubeId);
      if (held.heldReason == HeldReason.doubt) unawaited(_readMarks());
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  /// A doubt's marks are worded with the list the server holds. Without
  /// it the doubts still show, by role, with their theme, band and note.
  Future<void> _readMarks() async {
    if (!mounted) return;
    setState(() => _marksFailed = false);
    try {
      final list = await AppScope.of(context).curation.checklist();
      if (mounted) setState(() => _checklist = list);
    } on Object catch (e) {
      if (!mounted || takeLostRole(context, e)) return;
      setState(() => _marksFailed = true);
    }
  }

  void _leave(String notice) => context.go(Routes.heldVideos, extra: notice);

  /// Takes a write's [e]: a lost role goes home; a video no longer held,
  /// back to the list.
  bool _handle(ApiError e) {
    if (takeLostRole(context, e)) return true;
    if (e.code != 'state_conflict' && e.code != 'not_found') return false;
    _leave(heldGone);
    return true;
  }

  Future<void> _reopen(Video v) async {
    final api = AppScope.of(context).staff;
    // The video waits, paused, beneath the confirmation.
    unawaited(playback?.pause());
    final reason = await confirmWithReason(
      context,
      title: 'Reabrir este vídeo para revisão?',
      body: [
        '“${v.title}” sai dos retidos e volta para a fila da curadoria, '
            'numa nova rodada.',
      ],
      action: 'Reabrir para revisão',
    );
    if (reason == null || !mounted) return;
    // Reopening asks no re-authentication, but the
    // second factor as every moderation route.
    final ok = await _write.write(
      () => api.reopenVideo(v.id, reason: reason),
      handle: _handle,
    );
    if (ok && mounted) _leave(reopened(v.title));
  }

  Future<void> _remove(Video v) async {
    final api = AppScope.of(context).staff;
    // The video waits, paused, beneath the confirmation.
    unawaited(playback?.pause());
    final reason = await confirmWithReason(
      context,
      title: 'Remover este vídeo de vez?',
      body: [
        '“${v.title}” sai da curadoria e não volta para o catálogo.',
        'Ele também não pode mais ser sugerido por nenhuma família.',
      ],
      action: 'Remover de vez',
    );
    if (reason == null || !mounted) return;
    setState(() => _removing = true);
    final ok = await _write.write(
      () => api.removeVideo(v.id, reason: reason),
      handle: _handle,
    );
    if (!mounted) return;
    setState(() => _removing = false);
    if (ok) _leave(removedForGood(v.title));
  }

  /// A doubt is settled by the team: removing it goes through the
  /// decision, with its reason.
  Future<void> _removeDoubt(Video v) async {
    final api = AppScope.of(context).staff;
    unawaited(playback?.pause());
    final reason = await confirmWithReason(
      context,
      title: 'Remover este vídeo de vez?',
      body: [
        '“${v.title}” sai da curadoria e não volta para o catálogo.',
        'A dúvida da curadoria fica decidida assim.',
      ],
      action: 'Remover de vez',
    );
    if (reason == null || !mounted) return;
    setState(() => _removing = true);
    final ok = await _write.write(
      () => api.decideDoubt(v.id, publish: false, reason: reason),
      handle: _handle,
    );
    if (!mounted) return;
    setState(() => _removing = false);
    if (ok) _leave(removedForGood(v.title));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) => FieldLayout(
      title: 'Vídeo retido',
      onBack: () => context.go(Routes.heldVideos),
      children: _body(),
    ),
  );

  List<Widget> _body() {
    final held = _held;
    if (held == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o vídeo')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    final v = held.video;
    final idle = !_write.blocked;
    final reports = [
      for (final r in ReportReason.values)
        if (held.reports.byReason[r] case final n? when n > 0) reportLine(r, n),
    ];
    // The notes stand apart from the counts: not tied to a reason, and
    // never with who wrote them.
    final notes = [
      for (final note in held.reports.notes)
        if (note.trim() case final n when n.isNotEmpty) n,
    ];
    return [
      VideoHeading(v),
      const SizedBox(height: Space.lg),
      Text(held.heldReason.label, style: text.bodyLarge),
      if (held.rejections.isNotEmpty)
        ..._section('Recusas', [
          for (final r in held.rejections) CurationWords.rejection(r),
        ]),
      if (held.doubts.isNotEmpty) ...[
        ..._section(doubtsHeading, [
          for (final d in held.doubts) ...[
            CurationWords.review(d),
            if (d.reason?.trim() case final note? when note.isNotEmpty)
              '“$note”',
            if (_checklist case final list?) ...CurationWords.marked(d, list),
          ],
        ]),
        if (_marksFailed) ...[
          const SizedBox(height: Space.md),
          Semantics(
            liveRegion: true,
            child: Text(marksFailed, style: text.bodyLarge),
          ),
          QuietAction(label: 'Tentar de novo', onPressed: _readMarks),
        ],
      ],
      if (held.audit case final audit?) ...[
        const SizedBox(height: Space.sm),
        Text(auditLine(audit), style: text.bodyLarge),
      ],
      if (reports.isNotEmpty) ..._section('Denúncias', reports),
      if (notes.isNotEmpty)
        ..._section(notesHeading, [for (final n in notes) '“$n”']),
      const SizedBox(height: Space.xl),
      playerWindow(failed: heldPlayerFailed),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      if (held.heldReason == HeldReason.doubt) ...[
        PrimaryButton(
          label: 'Publicar',
          onPressed: idle
              ? () => context.go(Routes.publishDoubt(v.id), extra: held)
              : null,
        ),
        const SizedBox(height: Space.xxl),
        QuietAction(
          label: 'Remover de vez',
          destructive: true,
          busy: _write.busy && _removing,
          onPressed: idle ? () => _removeDoubt(v) : null,
        ),
      ] else ...[
        PrimaryButton(
          label: 'Reabrir para revisão',
          busy: _write.busy && !_removing,
          onPressed: idle ? () => _reopen(v) : null,
        ),
        const SizedBox(height: Space.xxl),
        QuietAction(
          label: 'Remover de vez',
          destructive: true,
          busy: _write.busy && _removing,
          onPressed: idle ? () => _remove(v) : null,
        ),
      ],
    ];
  }

  /// A heading in title-medium and its read lines between hairlines.
  List<Widget> _section(String title, List<String> lines) => [
    const SizedBox(height: Space.xl),
    Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
    const SizedBox(height: Space.md),
    Doors(children: [for (final line in lines) _Line(line)]),
  ];
}

/// One line of what was said, read and never a target.
class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}
