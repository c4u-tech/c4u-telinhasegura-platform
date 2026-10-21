import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// The fewest and most characters a staff write's reason takes once
/// trimmed (the server answers `reason_required` outside them).
const staffReasonMin = 3;
const staffReasonMax = 200;

/// From this many characters the reason field shows its count.
const _countFrom = 160;

/// Whether [reason], trimmed, is a staff write's reason: [staffReasonMin]
/// to [staffReasonMax] characters.
bool validReason(String reason) {
  final length = reason.trim().length;
  return length >= staffReasonMin && length <= staffReasonMax;
}

/// "Motivo": the reason a staff write or an account lookup is sent with,
/// up to [staffReasonMax] characters, its count shown near the bound.
class ReasonField extends StatelessWidget {
  const ReasonField({super.key, required this.controller, this.enabled});

  final TextEditingController controller;
  final bool? enabled;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.multiline,
    textCapitalization: TextCapitalization.sentences,
    minLines: 3,
    maxLines: null,
    maxLength: staffReasonMax,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    buildCounter:
        (_, {required currentLength, required isFocused, maxLength}) =>
            currentLength < _countFrom
            ? null
            : Text(
                '$currentLength de $staffReasonMax',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.muted),
              ),
    decoration: const InputDecoration(
      labelText: 'Motivo',
      alignLabelWithHint: true,
    ),
  );
}

/// Under the action while the reason is not yet valid.
const reasonHint = 'Escreva acima um motivo de 3 a 200 caracteres.';

/// Asks before a destructive family action. [title] and [body] name who
/// it affects and what goes; [action] confirms. True once confirmed,
/// false when cancelled: nothing destructive happens on a single tap.
///
/// When [title] or [body] show an address with its break marks
/// (`addressBreaks`), [titleSemanticsLabel] and [bodySemanticsLabels] are
/// the same words with the plain address, for assistive technology.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required List<String> body,
  required String action,
  String? titleSemanticsLabel,
  List<String>? bodySemanticsLabels,
  String promise = promiseLine,
}) async {
  final confirmed = await _show<bool>(
    context,
    DestructiveConfirmation(
      title: title,
      body: body,
      action: action,
      titleSemanticsLabel: titleSemanticsLabel,
      bodySemanticsLabels: bodySemanticsLabels,
      promise: promise,
    ),
  );
  return confirmed ?? false;
}

/// Asks before a staff write, which the audit keeps with its reason: the
/// same confirmation, with "Motivo" between what it does and [action],
/// which waits on a reason of [staffReasonMin] to [staffReasonMax]
/// characters. The reason trimmed once confirmed,
/// null when cancelled. The action is the ordinary ink primary whether
/// the write removes something or not (the Quiet Loss Rule: clay is
/// never a fill); a removal is told apart by the clay quiet action that
/// opened it.
Future<String?> confirmWithReason(
  BuildContext context, {
  required String title,
  required List<String> body,
  required String action,
  String? titleSemanticsLabel,
  List<String>? bodySemanticsLabels,
  String promise = promiseLine,
}) => _show<String>(
  context,
  DestructiveConfirmation(
    title: title,
    body: body,
    action: action,
    titleSemanticsLabel: titleSemanticsLabel,
    bodySemanticsLabels: bodySemanticsLabels,
    promise: promise,
    askReason: true,
  ),
);

Future<T?> _show<T>(BuildContext context, Widget confirmation) => showDialog<T>(
  context: context,
  useSafeArea: false,
  barrierColor: BrandColors.dark.withValues(alpha: 0.6),
  builder: (_) => confirmation,
);

/// The confirmation itself: a whole task screen over the one it
/// interrupts, like the re-authentication prompt. It closes with true
/// when confirmed, or, when it [askReason]s, with the reason trimmed;
/// cancelled, with false, or null when it asked a reason.
class DestructiveConfirmation extends StatefulWidget {
  const DestructiveConfirmation({
    super.key,
    required this.title,
    required this.body,
    required this.action,
    this.titleSemanticsLabel,
    this.bodySemanticsLabels,
    this.promise = promiseLine,
    this.askReason = false,
  }) : assert(
         bodySemanticsLabels == null ||
             bodySemanticsLabels.length == body.length,
       );

  final String title;
  final List<String> body;
  final String action;

  /// The [title] and each [body] paragraph as read aloud, when shown with
  /// an address's break marks.
  final String? titleSemanticsLabel;
  final List<String>? bodySemanticsLabels;

  /// The field's promise line, as on the screen this confirmation
  /// interrupts.
  final String promise;

  /// Whether it asks "Motivo" before [action].
  final bool askReason;

  @override
  State<DestructiveConfirmation> createState() =>
      _DestructiveConfirmationState();
}

class _DestructiveConfirmationState extends State<DestructiveConfirmation> {
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _text => _reason.text.trim();

  bool get _ready => !widget.askReason || validReason(_text);

  void _close(bool confirmed) {
    final Object? answer = widget.askReason
        ? (confirmed ? _text : null)
        : confirmed;
    Navigator.of(context).pop(answer);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog.fullscreen(
      backgroundColor: context.palette.ground,
      child: FieldLayout(
        promise: widget.promise,
        title: widget.title,
        titleSemanticsLabel: widget.titleSemanticsLabel,
        onBack: () => _close(false),
        children: [
          for (final (i, paragraph) in widget.body.indexed) ...[
            Text(
              paragraph,
              semanticsLabel: widget.bodySemanticsLabels?[i],
              style: text.bodyLarge,
            ),
            const SizedBox(height: Space.md),
          ],
          const SizedBox(height: Space.md),
          if (widget.askReason) ...[
            ReasonField(controller: _reason),
            const SizedBox(height: Space.xl),
          ],
          PrimaryButton(
            label: widget.action,
            onPressed: _ready ? () => _close(true) : null,
          ),
          if (widget.askReason)
            SubmitHint(reasonHint, visible: !_ready, reserve: true),
          const SizedBox(height: Space.xxl),
          QuietAction(label: 'Cancelar', onPressed: () => _close(false)),
        ],
      ),
    );
  }
}
