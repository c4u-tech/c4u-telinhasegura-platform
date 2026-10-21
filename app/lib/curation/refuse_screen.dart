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
import '../family/widgets.dart' show FamilyPlaceholder;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'video_heading.dart';

/// What a refusal does, said first.
const refuseLead = 'Recusar tira o vídeo das prateleiras na mesma hora.';

/// Over the questions.
const refuseItemsLead =
    'Marque o que aparece no vídeo. Só recusamos pelos critérios publicados.';

/// Under the primary while nothing is ticked.
const refuseHint = 'Marque acima pelo menos uma coisa que aparece.';

/// The done state's notice.
const refused = 'Sua recusa foi registrada.';

/// `validation` on a refusal, on the note.
const noteInvalid = 'Escreva no máximo 500 caracteres.';

/// The optional note.
const refuseNoteLabel = 'Quer contar mais? (opcional)';

/// The longest note the server takes, in characters.
const reasonMax = 500;

/// From this many characters the field shows its count.
const _countFrom = 400;

/// `/curadoria/:id/recusar`: what a refusal does; every question that
/// refuses, by group, to tick; an optional note of up to 500 characters; and the ordinary ink
/// primary "Recusar" (the Quiet Loss Rule: never clay), waiting until one
/// question is ticked. [items] arrive ticked from an approval that marked
/// them. It sends the refusal once, then the done state back to the queue.
class RefuseScreen extends StatefulWidget {
  const RefuseScreen({
    super.key,
    required this.id,
    this.video,
    this.items = const [],
  });

  final String id;

  /// The video as the review read it; opened directly, it is read here.
  final Video? video;

  final List<String> items;

  @override
  State<RefuseScreen> createState() => _RefuseScreenState();
}

class _RefuseScreenState extends State<RefuseScreen> {
  final _note = TextEditingController();
  final _send = Submission();
  late final Set<String> _ticked = {...widget.items};
  bool _started = false;
  Video? _video;
  Checklist? _checklist;
  bool _checklistFailed = false;
  String? _fieldError;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _note.addListener(() {
      _send.clearMessage();
      setState(() => _fieldError = null);
    });
  }

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
  /// the queue goes back to it; any other failure leaves the form as is.
  Future<void> _readVideo() async {
    if (!mounted) return;
    try {
      final detail = await AppScope.of(context).curation.video(widget.id);
      if (mounted) setState(() => _video = detail.video);
    } on Object catch (e) {
      if (mounted) leaveForQueue(context, e);
    }
  }

  /// A ticked question the list does not hold as refusing is dropped: a
  /// link cannot tick anything else. The old list goes first, so a failed
  /// read after it changed offers to try again rather than the outdated
  /// list.
  Future<void> _readChecklist() async {
    if (!mounted) return;
    setState(() {
      _checklist = null;
      _checklistFailed = false;
    });
    try {
      final list = await AppScope.of(context).curation.checklist();
      if (!mounted) return;
      setState(() {
        _checklist = list;
        _ticked.retainWhere(
          (id) => list.item(id)?.rule == ChecklistRule.refuses,
        );
      });
    } on Object catch (e) {
      if (!mounted || leaveForQueue(context, e)) return;
      setState(() => _checklistFailed = true);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _send.dispose();
    super.dispose();
  }

  Future<void> _refuse(Checklist list) async {
    final note = _note.text.trim();
    final api = AppScope.of(context).curation;
    final ok = await _send.run(
      () => api.reject(
        widget.id,
        version: list.version,
        failedItems: [
          for (final i in list.items)
            if (_ticked.contains(i.id)) i.id,
        ],
        note: note.isEmpty ? null : note,
      ),
      handle: _handle,
    );
    if (ok && mounted) setState(() => _done = true);
  }

  bool _handle(ApiError e) {
    if (leaveForQueue(context, e)) return true;
    if (e.code == 'checklist_outdated') {
      unawaited(_readChecklist());
      return false;
    }
    if (e.code != 'validation') return false;
    setState(() => _fieldError = noteInvalid);
    return true;
  }

  void _toggle(String id, bool on) {
    _send.clearMessage();
    setState(() => on ? _ticked.add(id) : _ticked.remove(id));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _send,
    builder: (context, _) => FieldLayout(
      title: 'Recusar',
      onBack: () =>
          context.go(_done ? Routes.curation : Routes.review(widget.id)),
      children: [
        if (_video case final video?) ...[
          VideoHeading(video),
          const SizedBox(height: Space.xl),
        ],
        ...(_done
            ? [
                const Notice(refused),
                const SizedBox(height: Space.xl),
                PrimaryButton(
                  label: 'Voltar para a fila',
                  onPressed: () => context.go(Routes.curation),
                ),
              ]
            : _form()),
      ],
    ),
  );

  List<Widget> _form() {
    final text = Theme.of(context).textTheme;
    final list = _checklist;
    if (list == null) {
      return [
        Text(refuseLead, style: text.bodyLarge),
        const SizedBox(height: Space.xl),
        if (!_checklistFailed)
          const FamilyPlaceholder(label: 'Carregando as perguntas')
        else ...[
          const ErrorNote(Copy.genericRetry),
          const SizedBox(height: Space.lg),
          PrimaryButton(label: 'Tentar de novo', onPressed: _readChecklist),
        ],
      ];
    }
    final idle = !_send.blocked;
    final none = _ticked.isEmpty;
    return [
      Text(refuseLead, style: text.bodyLarge),
      const SizedBox(height: Space.lg),
      Text(refuseItemsLead, style: text.bodyLarge),
      for (final g in list.groups)
        if (g.items.where((i) => i.rule == ChecklistRule.refuses).toList()
            case final items when items.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          Semantics(
            header: true,
            child: Text(g.title, style: text.titleMedium),
          ),
          const SizedBox(height: Space.sm),
          for (final i in items)
            DeclarationRow(
              text: i.text,
              value: _ticked.contains(i.id),
              onChanged: idle ? (on) => _toggle(i.id, on) : null,
            ),
        ],
      const SizedBox(height: Space.xl),
      TextField(
        controller: _note,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        minLines: 2,
        maxLines: null,
        maxLength: reasonMax,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                currentLength < _countFrom
                ? null
                : Text(
                    '$currentLength de $reasonMax',
                    style: text.bodySmall?.copyWith(
                      color: context.palette.muted,
                    ),
                  ),
        decoration: InputDecoration(
          labelText: refuseNoteLabel,
          alignLabelWithHint: true,
          errorText: _fieldError,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: Space.xl),
      if (_send.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Recusar',
        busy: _send.busy,
        onPressed: none || !idle ? null : () => _refuse(list),
      ),
      SubmitHint(refuseHint, visible: none, reserve: true),
    ];
  }
}
