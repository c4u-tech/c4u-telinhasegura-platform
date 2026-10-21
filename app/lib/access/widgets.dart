import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// A form-level message: earth tone, an icon and text together, announced
/// to assistive technology.
class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.errorGround,
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: p.error, size: 22),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: p.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calm confirmation in the task column: plain text, announced.
class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.semanticsLabel});

  final String message;

  /// What assistive technology reads instead of [message], when the shown
  /// text carries break marks (an address set with `addressBreaks`).
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyLarge,
      semanticsLabel: semanticsLabel,
    ),
  );
}

/// The full-width primary action. While [busy] it shows progress but
/// keeps its label for assistive technology.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: busy
        ? Semantics(
            label: label,
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: context.palette.text,
              ),
            ),
          )
        : Text(label),
  );
}

class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.onSubmitted,
    this.label = 'E-\u2060mail',
    this.errorText,
  });

  final TextEditingController controller;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final String label;
  final String? errorText;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.next,
    maxLength: 254,
    buildCounter: (
      _, {
      required currentLength,
      required isFocused,
      maxLength,
    }) => null,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(labelText: label, errorText: errorText),
  );
}

/// A password with show/hide. [isNew] picks the `newPassword` autofill
/// hint so password managers offer to generate and save.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.isNew = false,
    this.label = 'Senha',
    this.errorText,
    this.helper,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool isNew;
  final String label;
  final String? errorText;
  final Widget? helper;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.visiblePassword,
    autofillHints: [
      widget.isNew ? AutofillHints.newPassword : AutofillHints.password,
    ],
    textInputAction: TextInputAction.done,
    inputFormatters: [LengthLimitingTextInputFormatter(256)],
    onSubmitted: widget.onSubmitted,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: widget.errorText,
      helper: widget.helper,
      suffixIcon: Padding(
        padding: const EdgeInsets.only(right: Space.xs),
        child: IconButton(
          onPressed: () => setState(() => _visible = !_visible),
          tooltip: _visible ? 'Ocultar senha' : 'Mostrar senha',
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    ),
  );
}

/// The state module: the mark's screen as a small rounded block, filled
/// when its condition holds and hollow when it does not. State is never
/// carried by colour alone: the text beside it says the same.
class StateModule extends StatelessWidget {
  const StateModule({super.key, required this.filled, this.height = 10});

  final bool filled;

  /// 10 px beside text; larger where the modules are the content, as in
  /// the PIN pad.
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = height;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: h * 58 / 33,
      height: h,
      decoration: BoxDecoration(
        color: filled ? p.action : Colors.transparent,
        borderRadius: BorderRadius.circular(h * Radii.screenRatio),
        border: Border.all(color: filled ? p.action : p.outline, width: 1.5),
      ),
    );
  }
}

/// A condition the guardian can see being met, such as the password
/// length.
class Guidance extends StatelessWidget {
  const Guidance({super.key, required this.text, required this.met});

  final String text;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.palette.muted);
    // The module centres on the first line, as the declaration's box
    // does, when the text wraps.
    final line = MediaQuery.textScalerOf(context)
        .scale(style!.fontSize! * (style.height ?? 1));
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: line,
            child: Center(child: StateModule(filled: met)),
          ),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(text, style: style)),
          Semantics(label: met ? 'atendido' : 'ainda não atendido'),
        ],
      ),
    );
  }
}

/// "Passo 1 de 2", with one module per step. A flow that calls its steps
/// something else names them with [word] ("Etapa 1 de 5").
class StepMarks extends StatelessWidget {
  const StepMarks({
    super.key,
    required this.step,
    required this.of,
    this.word = 'Passo',
  });

  final int step;
  final int of;
  final String word;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      children: [
        for (var i = 1; i <= of; i++) ...[
          StateModule(filled: i <= step),
          const SizedBox(width: Space.xs),
        ],
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            '$word $step de $of',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ),
      ],
    ),
  );
}

/// The quiet "ou" between the provider buttons and email.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final line = Expanded(
      child: Divider(color: p.outline.withValues(alpha: .5)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Text(
              'ou',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: p.muted),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// A quiet text action at the start of the column, such as a screen's
/// foot or a confirmation's "Cancelar": its label starts on the column
/// edge, with the 48 dp target and the focus ring kept around it.
/// [destructive] ones take the clay tone. While [busy] it shows progress
/// beside its label and waits. [inline], it follows a muted lead-in on
/// the same line ("Prefere começar a sua? Começar minha família")
/// instead of standing alone at the column's start.
class QuietAction extends StatelessWidget {
  const QuietAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.busy = false,
    this.inline = false,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool busy;
  final bool inline;

  /// What assistive technology reads instead of [label], when the same
  /// label repeats on a screen and must say what it acts on.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.palette.error : null;
    final button = TextButton.icon(
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsetsDirectional.only(end: Space.md),
      ),
      icon: busy
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color ?? context.palette.text,
              ),
            )
          : null,
      label: Text(label, semanticsLabel: semanticsLabel),
    );
    if (inline) return button;
    return Align(alignment: AlignmentDirectional.centerStart, child: button);
  }
}

/// Shown under a submit that waits for the declaration.
const declarationHint = 'Marque a declaração acima para continuar.';

/// Says, under a disabled submit, what it waits for (the
/// disabled-with-hint pattern). Hidden once [visible] is false; with
/// [reserve], hidden keeps its place (unseen and unread), so a centred
/// column does not re-centre when it goes.
class SubmitHint extends StatelessWidget {
  const SubmitHint(
    this.text, {
    super.key,
    this.visible = true,
    this.reserve = false,
  });

  final String text;
  final bool visible;
  final bool reserve;

  @override
  Widget build(BuildContext context) {
    if (!visible && !reserve) return const SizedBox.shrink();
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.palette.muted),
        ),
      ),
    );
  }
}

/// A declaration the guardian makes by checking it: unchecked until
/// they do, with the whole row as its target.
class DeclarationRow extends StatelessWidget {
  const DeclarationRow({
    super.key,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final String text;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(Radii.small),
        // The box sits on the column's left edge, centred on the label's
        // first 24 dp line; the whole 48 dp row is the target.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 24,
                child: Checkbox(
                  value: value,
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: VisualDensity.minimumDensity,
                    vertical: VisualDensity.minimumDensity,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of a list in the task column, led by a small mark in the
/// text's colour (`/conta/dados`, `/conta/excluir`).
class BulletItem extends StatelessWidget {
  const BulletItem(this.text, {super.key, this.semanticsLabel});

  final String text;

  /// What assistive technology reads instead of [text] (see [Notice]).
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    // The mark sits on the first line's x-height, at any text scale.
    final lead = MediaQuery.textScalerOf(context)
        .scale((style?.fontSize ?? 16) * 0.6);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: lead),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.palette.text,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox.square(dimension: 6),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(text, style: style, semanticsLabel: semanticsLabel),
          ),
        ],
      ),
    );
  }
}
