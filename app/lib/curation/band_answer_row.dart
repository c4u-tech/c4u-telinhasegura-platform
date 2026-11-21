import 'package:flutter/material.dart';

import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'approve_screen.dart' show changeLabel;

/// An answer that moved the band: the question, then "— Sim" or "— Não
/// sei" in weight; for the one who gave it, "mudar", named by the question,
/// back to its page ([changeable]); for a moderator, who cannot change it,
/// who gave it ([by], muted) instead.
class BandAnswerRow extends StatelessWidget {
  const BandAnswerRow({
    super.key,
    required this.question,
    required this.word,
    this.onChange,
    this.changeable = true,
    this.by,
  });

  final String question;
  final String word;
  final VoidCallback? onChange;
  final bool changeable;

  /// Who gave the answer, by displayed role: "Mãe ou pai respondeu".
  final String? by;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final answer = Text.rich(
      TextSpan(
        text: '$question ',
        children: [
          TextSpan(
            // Kept on one line with its dash.
            text: '—\u00A0$word'.replaceAll(' ', '\u00A0'),
            // The answer in the weight of an action's label.
            style: TextStyle(
              fontWeight: text.labelLarge?.fontWeight,
              fontVariations: text.labelLarge?.fontVariations,
            ),
          ),
        ],
      ),
      semanticsLabel: '$question — $word',
      style: text.bodyLarge,
    );
    if (!changeable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        // Read as one: the answer, then who gave it.
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              answer,
              if (by case final by?) ...[
                const SizedBox(height: Space.xs),
                Text(
                  by,
                  style: text.bodyMedium?.copyWith(
                    color: context.palette.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final change = QuietAction(
      label: changeLabel,
      semanticsLabel: '$changeLabel: $question',
      inline: true,
      onPressed: onChange,
    );
    // At large text a column beside the question would leave it a word or
    // two a line: "mudar" goes under it.
    final large = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [answer, change],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: answer),
                const SizedBox(width: Space.sm),
                change,
              ],
            ),
    );
  }
}
