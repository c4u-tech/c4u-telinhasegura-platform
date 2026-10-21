import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/profile_fields.dart' show ChoiceTarget;
import 'curation.dart';
import 'words.dart';

/// One checklist question and its answers side by side as 56 dp keys, a
/// choice of one: "Não · Sim · Não sei", or "Não · Sim" without [unsure]
/// (a fact the curator knows, such as a tie to the channel). The chosen
/// key fills and carries a check, so the choice never rests on colour
/// alone. Assistive technology hears the question as the group's name and
/// each key as one of its options.
class AnswerChoice extends StatelessWidget {
  const AnswerChoice({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
    this.unsure = true,
  });

  final String question;

  /// Null until answered.
  final ChecklistAnswer? value;
  final ValueChanged<ChecklistAnswer>? onChanged;
  final bool unsure;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final options = [
      ChecklistAnswer.ok,
      ChecklistAnswer.appears,
      if (unsure) ChecklistAnswer.doubt,
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.radioGroup,
      label: question,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Read once, as the group's name.
          ExcludeSemantics(
            child: Text(question, style: Theme.of(context).textTheme.bodyLarge),
          ),
          const SizedBox(height: Space.sm),
          // Stretched to the tallest, so a word that wraps in a narrow
          // window leaves the keys level.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, a) in options.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.sm),
                  Expanded(
                    child: _AnswerKey(
                      answer: a,
                      selected: a == value,
                      onTap: onChanged == null ? null : () => onChanged(a),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One answer as a key: the input tone with an outline stroke, or, chosen,
/// the action colour with a check before its word. Without [onTap] (a
/// send running) it waits: the outline tone at 32% fill and its words at
/// 60%, a chosen key keeping its check and its stroke in the action
/// colour.
class _AnswerKey extends StatelessWidget {
  const _AnswerKey({
    required this.answer,
    required this.selected,
    required this.onTap,
  });

  final ChecklistAnswer answer;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final off = onTap == null;
    final ink = off
        ? p.text.withValues(alpha: .6)
        : selected
        ? p.onAction
        : p.text;
    return ChoiceTarget(
      label: answer.word,
      selected: selected,
      onTap: onTap,
      radius: Radii.control,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: off
              ? p.outline.withValues(alpha: .32)
              : selected
              ? p.action
              : p.input,
          borderRadius: BorderRadius.circular(Radii.control),
          // The same width chosen or not: choosing moves nothing.
          border: Border.all(
            color: selected ? p.action : p.outline,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 20, color: ink),
              const SizedBox(width: Space.xs),
            ],
            Flexible(
              child: Text(
                answer.word,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
