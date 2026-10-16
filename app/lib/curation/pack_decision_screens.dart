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
import 'pack.dart';
import 'packs_screen.dart' show leaveForPacks;
import 'refuse_screen.dart' show reasonMax;

/// What approving a pacotinho confirms, said before the primary.
const approvePackLead =
    'Ao aprovar, você confirma que estes vídeos funcionam bem nesta ordem '
    'para uma criança.';

/// The approval's done state.
const packApproved = 'Sua aprovação foi registrada.';

/// What a refusal does, said before the field.
const refusePackLead =
    'Recusar tira esta versão da revisão. Quem quiser pode montar uma '
    'nova.';

/// Under the primary while the reason is blank.
const refusePackHint = 'Escreva acima o motivo da recusa.';

/// The refusal's done state.
const packRefused = 'Sua recusa foi registrada.';

/// `validation` on a refusal, on the field.
const packReasonInvalid = 'Escreva um motivo de 1 a 500 caracteres.';

/// From this many characters the field shows its count.
const _countFrom = 400;

/// The pacotinho a decision names: as the review read it, or read here
/// when the decision was opened directly. A pacotinho the curator can
/// no longer act on goes back to the list.
mixin _NamedPack<T extends StatefulWidget> on State<T> {
  String get packId;
  Pack? get given;

  bool _started = false;
  Pack? pack;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    pack = given;
    if (pack == null) scheduleMicrotask(_readPack);
  }

  Future<void> _readPack() async {
    if (!mounted) return;
    try {
      final p = await AppScope.of(context).curation.pack(packId);
      if (mounted) setState(() => pack = p);
    } on Object catch (e) {
      if (mounted) leaveForPacks(context, e);
    }
  }

  List<Widget> heading() => [
    if (pack case final p?) ...[
      Text(p.title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.xl),
    ],
  ];

  /// The done state: [notice], then back to the list.
  List<Widget> done(String notice) => [
    Notice(notice),
    const SizedBox(height: Space.xl),
    PrimaryButton(
      label: 'Voltar para pacotinhos',
      onPressed: () => context.go(Routes.packs),
    ),
  ];
}

/// `/pacotinhos/:id/aprovar`: one line on what approving confirms, then
/// the primary "Aprovar"; it approves once, then the done state back to
/// the list.
class ApprovePackScreen extends StatefulWidget {
  const ApprovePackScreen({super.key, required this.id, this.pack});

  final String id;
  final Pack? pack;

  @override
  State<ApprovePackScreen> createState() => _ApprovePackScreenState();
}

class _ApprovePackScreenState extends State<ApprovePackScreen> with _NamedPack {
  final _send = Submission();
  bool _done = false;

  @override
  String get packId => widget.id;

  @override
  Pack? get given => widget.pack;

  @override
  void dispose() {
    _send.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    final api = AppScope.of(context).curation;
    final ok = await _send.run(
      () => api.approvePack(widget.id),
      handle: (e) => leaveForPacks(context, e),
    );
    if (ok && mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _send,
    builder: (context, _) => FieldLayout(
      title: 'Aprovar',
      onBack: () =>
          context.go(_done ? Routes.packs : Routes.packReview(widget.id)),
      children: [
        ...heading(),
        ...(_done
            ? done(packApproved)
            : [
                Text(
                  approvePackLead,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: Space.xl),
                if (_send.message case final message?) ...[
                  ErrorNote(message),
                  const SizedBox(height: Space.lg),
                ],
                PrimaryButton(
                  label: 'Aprovar',
                  busy: _send.busy,
                  onPressed: _send.blocked ? null : _approve,
                ),
              ]),
      ],
    ),
  );
}

/// `/pacotinhos/:id/recusar`: what a refusal does, one multi-line
/// "Motivo" of 1 to 500 characters, and the ink primary "Recusar" (the
/// Quiet Loss Rule), waiting for a non-blank reason; it refuses once,
/// then the done state back to the list.
class RefusePackScreen extends StatefulWidget {
  const RefusePackScreen({super.key, required this.id, this.pack});

  final String id;
  final Pack? pack;

  @override
  State<RefusePackScreen> createState() => _RefusePackScreenState();
}

class _RefusePackScreenState extends State<RefusePackScreen> with _NamedPack {
  final _reason = TextEditingController();
  final _send = Submission();
  String? _fieldError;
  bool _done = false;

  @override
  String get packId => widget.id;

  @override
  Pack? get given => widget.pack;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() {
      _send.clearMessage();
      setState(() => _fieldError = null);
    });
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
      () => api.rejectPack(widget.id, reason),
      handle: _handle,
    );
    if (ok && mounted) setState(() => _done = true);
  }

  bool _handle(ApiError e) {
    if (leaveForPacks(context, e)) return true;
    if (e.code != 'validation') return false;
    setState(() => _fieldError = packReasonInvalid);
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _send,
    builder: (context, _) => FieldLayout(
      title: 'Recusar',
      onBack: () =>
          context.go(_done ? Routes.packs : Routes.packReview(widget.id)),
      children: [...heading(), ...(_done ? done(packRefused) : _form())],
    ),
  );

  List<Widget> _form() {
    final text = Theme.of(context).textTheme;
    final blank = _text.isEmpty;
    return [
      Text(refusePackLead, style: text.bodyLarge),
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
      SubmitHint(refusePackHint, visible: blank, reserve: true),
    ];
  }
}
