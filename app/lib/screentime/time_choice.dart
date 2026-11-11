import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../family/profile_fields.dart' show SelectableRow;

/// More time today as one choice of one: "Mais 15 min", "Mais 30 min" and
/// "Mais 60 min" as a row of three keys, and one full-width row for going
/// without more time, named by [plain], before the keys or after them.
/// Read as radios by the full words.
///
/// Where a key's words would wrap (large text, a narrow screen), the
/// times stand as full-width rows instead; the choice reads and behaves
/// the same. It takes the palette of its ground, at [height].
class TimeChoice extends StatelessWidget {
  const TimeChoice({
    super.key,
    required this.chosen,
    required this.onChoose,
    required this.plain,
    this.plainFirst = false,
    this.height = 56,
    this.waits,
  });

  /// The minutes offered.
  static const minutes = [15, 30, 60];

  /// The minutes chosen; null for [plain].
  final int? chosen;

  /// Null while nothing may be chosen (a check running).
  final ValueChanged<int?>? onChoose;
  final String plain;
  final bool plainFirst;
  final double height;

  /// An option that cannot be chosen now waits, disabled; null is
  /// [plain].
  final bool Function(int? minutes)? waits;

  /// A key's words: the number and its unit never part.
  static String short(int minutes) => '$minutes\u00A0min';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final keyed = _keysFit(context, box.maxWidth);
      VoidCallback? choose(int? m) =>
          onChoose == null || (waits?.call(m) ?? false)
          ? null
          : () => onChoose!(m);
      final times = [
        for (final m in minutes)
          SelectableRow(
            label: 'Mais $m min',
            text: keyed ? short(m) : null,
            asKey: keyed,
            selected: chosen == m,
            onTap: choose(m),
            height: height,
          ),
      ];
      final none = SelectableRow(
        label: plain,
        selected: chosen == null,
        onTap: choose(null),
        height: height,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (plainFirst) ...[none, const SizedBox(height: Space.sm)],
          if (keyed)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, time) in times.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.sm),
                  Expanded(child: time),
                ],
              ],
            )
          else
            for (final (i, time) in times.indexed) ...[
              if (i > 0) const SizedBox(height: Space.sm),
              time,
            ],
          if (!plainFirst) ...[const SizedBox(height: Space.sm), none],
        ],
      );
    },
  );

  /// Whether every key's module, gap and words fit one line inside a third
  /// of [width], at the text scale in force.
  static bool _keysFit(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final key = (width - 2 * Space.sm) / 3 - 2 * Space.sm;
    const module = 10 * 58 / 33;
    for (final m in minutes) {
      final words = TextPainter(
        text: TextSpan(text: short(m), style: style),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final fits = module + Space.sm + words.width <= key;
      words.dispose();
      if (!fits) return false;
    }
    return true;
  }
}
