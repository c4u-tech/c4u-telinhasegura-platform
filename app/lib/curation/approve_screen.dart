import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/profile_fields.dart' show AgeBandChoice, SelectableRow;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'video_heading.dart';
import 'words.dart';

/// Under the primary until a theme and a band are chosen.
const approveHint = 'Escolha um tema e uma idade acima.';

/// The done state's notice.
const approved = 'Sua aprovação foi registrada.';

/// `validation` on an approval: the choices are marked, and
/// cleared to choose again.
const approvalRefused =
    'Essa escolha não foi aceita. Escolha o tema e a idade de novo.';

/// `/curadoria/:id/aprovar`: one theme of six and a band of three, none
/// chosen on arrival; the primary "Aprovar" waits with its hint until
/// both are, sends the approval once, then the done state back to the
/// queue.
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
  bool _started = false;
  Video? _video;
  VideoTheme? _theme;
  AgeBand? _band;
  bool _refused = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    _video = widget.video;
    if (_video == null) scheduleMicrotask(_readVideo);
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

  @override
  void dispose() {
    _send.dispose();
    super.dispose();
  }

  Future<void> _approve(VideoTheme theme, AgeBand band) async {
    final api = AppScope.of(context).curation;
    final ok = await _send.run(
      () => api.approve(widget.id, theme: theme, minAgeBand: band),
      handle: _handle,
    );
    if (ok && mounted) setState(() => _done = true);
  }

  bool _handle(ApiError e) {
    if (leaveForQueue(context, e)) return true;
    if (e.code != 'validation') return false;
    setState(() {
      _refused = true;
      _theme = null;
      _band = null;
    });
    return true;
  }

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
      onBack: () =>
          context.go(_done ? Routes.curation : Routes.review(widget.id)),
      children: [
        if (_video case final video?) ...[
          VideoHeading(video),
          const SizedBox(height: Space.xl),
        ],
        ...(_done
            ? [
                const Notice(approved),
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
    final p = context.palette;
    final idle = !_send.blocked;
    final theme = _theme;
    final band = _band;
    return [
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
      const SizedBox(height: Space.md),
      AgeBandChoice(
        value: band,
        onChanged: idle ? (b) => _pick(() => _band = b) : null,
      ),
      const SizedBox(height: Space.xl),
      if (_send.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Aprovar',
        busy: _send.busy,
        onPressed: theme != null && band != null && idle
            ? () => _approve(theme, band)
            : null,
      ),
      SubmitHint(
        approveHint,
        visible: theme == null || band == null,
        reserve: true,
      ),
    ];
  }
}
