import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'queue_screen.dart' show leaveForQueue;
import 'video_heading.dart';

/// What a refusal does, said before the field.
const refuseLead = 'Recusar tira o vídeo das prateleiras na mesma hora.';

/// Under the primary while the reason is blank.
const refuseHint = 'Escreva acima o motivo da recusa.';

/// The done state's notice.
const refused = 'Sua recusa foi registrada.';

/// `validation` on a refusal, on the field.
const reasonInvalid = 'Escreva um motivo de 1 a 500 caracteres.';

/// The longest reason the server takes, in characters.
const reasonMax = 500;

/// From this many characters the field shows its count.
const _countFrom = 400;

/// `/curadoria/:id/recusar`: what a refusal does, one multi-line
/// "Motivo" of 1 to 500 characters, and the ordinary ink primary
/// "Recusar" (the Quiet Loss Rule: never clay), waiting until the reason
/// has a non-blank character; it sends the refusal once, then the done
/// state back to the queue.
class RefuseScreen extends StatefulWidget {
  const RefuseScreen({super.key, required this.id, this.video});

  final String id;

  /// The video as the review read it; opened directly, it is read here.
  final Video? video;

  @override
  State<RefuseScreen> createState() => _RefuseScreenState();
}

class _RefuseScreenState extends State<RefuseScreen> {
  final _reason = TextEditingController();
  final _send = Submission();
  bool _started = false;
  Video? _video;
  String? _fieldError;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() {
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
    _reason.dispose();
    _send.dispose();
    super.dispose();
  }

  String get _text => _reason.text.trim();

  Future<void> _refuse() async {
    final reason = _text;
    if (reason.isEmpty) return;
    final api = AppScope.of(context).curation;
    final ok = await _send.run(
      () => api.reject(widget.id, reason),
      handle: _handle,
    );
    if (ok && mounted) setState(() => _done = true);
  }

  bool _handle(ApiError e) {
    if (leaveForQueue(context, e)) return true;
    if (e.code != 'validation') return false;
    setState(() => _fieldError = reasonInvalid);
    return true;
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
    final blank = _text.isEmpty;
    return [
      Text(refuseLead, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      TextField(
        controller: _reason,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        minLines: 3,
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
          labelText: 'Motivo',
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
        onPressed: blank || _send.blocked ? null : _refuse,
      ),
      SubmitHint(refuseHint, visible: blank, reserve: true),
    ];
  }
}
