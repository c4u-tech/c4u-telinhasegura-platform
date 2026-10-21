import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../family/profile_fields.dart' show SelectableRow;
import 'checklist_draft.dart';
import 'curation.dart';

/// A group's "everything is fine": [noneAppears] for a group of things to
/// look for, [allClear] for one that also asks in the positive.
const noneAppears = 'Nada disso aparece';
const allClear = 'Tudo certo neste grupo';

/// A mark on a question asked as "does it appear?", on one asked in the
/// positive, and a doubt.
const marksAppears = 'Aparece';
const marksNo = 'Não';
const marksDoubt = 'Tenho dúvida';

/// The checklist, group by group: the group's title, its "everything is
/// fine" row, then each question with its two marks side by side. Every
/// row reads its question or group with it, since the words repeat.
/// [onChanged] null leaves the list read-only.
class ChecklistForm extends StatelessWidget {
  const ChecklistForm({super.key, required this.draft, this.onChanged});

  final ChecklistDraft draft;
  final VoidCallback? onChanged;

  static String _clearLabel(ChecklistGroup g) =>
      g.items.any((i) => i.positive) ? allClear : noneAppears;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final changed = onChanged;
    VoidCallback? act(void Function() change) => changed == null
        ? null
        : () {
            change();
            changed();
          };
    Widget markRow(ChecklistGroup g, ChecklistItem item, ChecklistAnswer a) {
      final words = a == ChecklistAnswer.doubt
          ? marksDoubt
          : item.positive
          ? marksNo
          : marksAppears;
      // A second tap takes the mark back: each mark is a checkbox.
      return SelectableRow(
        label: '$words: ${item.text}',
        text: words,
        asKey: true,
        toggle: true,
        selected: draft.answerOf(item) == a,
        onTap: act(() => draft.mark(g, item, a)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (gi, g) in draft.checklist.groups.indexed) ...[
          if (gi > 0) const SizedBox(height: Space.xxl),
          Semantics(
            header: true,
            child: Text(g.title, style: text.titleMedium),
          ),
          const SizedBox(height: Space.md),
          SelectableRow(
            label: '${_clearLabel(g)}: ${g.title}',
            text: _clearLabel(g),
            selected: draft.cleared(g),
            onTap: act(() => draft.clear(g)),
          ),
          for (final item in g.items) ...[
            const SizedBox(height: Space.lg),
            Text(item.text, style: text.bodyLarge),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(child: markRow(g, item, ChecklistAnswer.appears)),
                const SizedBox(width: Space.sm),
                Expanded(child: markRow(g, item, ChecklistAnswer.doubt)),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
