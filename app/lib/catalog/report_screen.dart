import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../curation/curation.dart' show ReportReason;
import '../curation/family_catalog.dart';
import '../curation/video_heading.dart';
import '../curation/words.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../family/profile_fields.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'family_video_screen.dart' show findFamilyVideo;
import 'words.dart';

/// The longest note the server takes, in characters.
const noteMax = 500;

/// From this many characters the note shows its count.
const _countFrom = 400;

/// `validation` on a report: the note, on its field.
const noteInvalid =
    'Confira a nota: até 500 caracteres, sem símbolos de controle.';

/// `/familia/videos/:crianca/:video/denunciar`: what a report does, a
/// choice of one of four reasons, an optional note of up to 500
/// characters and the ordinary ink primary "Denunciar" (the Quiet Loss
/// Rule), waiting for a reason; then the done state back to the child's
/// catalogue, where the video is gone.
class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.minorId,
    required this.videoId,
    this.video,
  });

  final String minorId;
  final String videoId;

  /// The video as its screen read it; opened directly, it is read here.
  final FamilyVideo? video;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _note = TextEditingController();
  final _send = Submission();
  late final FamilyModel _model;
  bool _started = false;
  FamilyVideo? _video;
  ReportReason? _reason;
  String? _noteError;

  /// The done state's notice: null until sent.
  String? _done;

  @override
  void initState() {
    super.initState();
    _note.addListener(() {
      if (_noteError == null) return;
      setState(() => _noteError = null);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    scheduleMicrotask(_model.load);
    _video = widget.video;
    if (_video == null) scheduleMicrotask(_readVideo);
  }

  /// Opened directly: the video is found to be named. A video not there
  /// goes back to the catalogue; any other failure leaves the form as it
  /// is, since the report does not need the name to be sent.
  Future<void> _readVideo() async {
    if (!mounted) return;
    try {
      final v = await findFamilyVideo(context, widget.minorId, widget.videoId);
      if (!mounted) return;
      if (v == null) return _toCatalogue();
      setState(() => _video = v);
    } on Object catch (_) {
      return;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _send.dispose();
    super.dispose();
  }

  void _toCatalogue() =>
      context.go(Routes.childVideos(widget.minorId), extra: videoGone);

  Future<void> _report(ReportReason reason) async {
    final api = AppScope.of(context).familyCatalog;
    final note = _note.text.trim();
    bool? created;
    final ok = await _send.run(() async {
      created = await api.report(
        widget.videoId,
        reason,
        note: note.isEmpty ? null : note,
      );
    }, handle: _handle);
    if (!ok || !mounted) return;
    setState(() => _done = created! ? reportNew : reportExisting);
  }

  bool _handle(ApiError e) {
    if (e.code == 'not_found') {
      _toCatalogue();
      return true;
    }
    if (e.code != 'validation') return false;
    setState(() => _noteError = noteInvalid);
    return true;
  }

  void _pick(ReportReason r) {
    _send.clearMessage();
    setState(() => _reason = r);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _send]),
    builder: (context, _) {
      final nickname = switch (_model.state) {
        FamilyReady(:final family) =>
          family.minors
              .where((m) => m.id == widget.minorId)
              .firstOrNull
              ?.nickname,
        _ => null,
      };
      final back = Routes.childVideos(widget.minorId);
      return FieldLayout(
        title: 'Denunciar',
        onBack: () => context.go(
          _done != null
              ? back
              : Routes.familyVideo(widget.minorId, widget.videoId),
        ),
        children: [
          if (_video case final v?) ...[
            VideoHeading.parts(
              title: v.title,
              channelTitle: v.channelTitle,
              duration: v.duration,
            ),
            const SizedBox(height: Space.xl),
          ],
          if (_done case final done?) ...[
            Notice(done),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: nickname == null
                  ? 'Voltar para os vídeos'
                  : CatalogWords.backTo(nickname),
              onPressed: () => context.go(back),
            ),
          ] else
            ..._form(),
        ],
      );
    },
  );

  List<Widget> _form() {
    final text = Theme.of(context).textTheme;
    final idle = !_send.blocked;
    final reason = _reason;
    return [
      Text(reportLead, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      Text('Motivo', style: text.titleMedium),
      const SizedBox(height: Space.md),
      for (final (i, r) in ReportReason.values.indexed)
        if (r != ReportReason.unknown) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          SelectableRow(
            label: r.label,
            selected: r == reason,
            onTap: idle ? () => _pick(r) : null,
          ),
        ],
      const SizedBox(height: Space.xl),
      TextField(
        controller: _note,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        minLines: 3,
        maxLines: null,
        maxLength: noteMax,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                currentLength < _countFrom
                ? null
                : Text(
                    '$currentLength de $noteMax',
                    style: text.bodySmall?.copyWith(
                      color: context.palette.muted,
                    ),
                  ),
        decoration: InputDecoration(
          labelText: 'Nota (opcional)',
          alignLabelWithHint: true,
          errorText: _noteError,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: Space.xl),
      if (_send.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Denunciar',
        busy: _send.busy,
        onPressed: reason != null && idle ? () => _report(reason) : null,
      ),
      SubmitHint(reportHint, visible: reason == null, reserve: true),
    ];
  }
}
