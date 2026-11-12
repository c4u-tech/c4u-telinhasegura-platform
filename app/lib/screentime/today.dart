import 'package:flutter/material.dart';

import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'kid_time.dart';
import 'screentime_api.dart';
import 'words.dart';

/// A child's day in the words shown beside its modules, on the home's row
/// and on the child's page alike.
abstract final class TodayWords {
  static const loading = 'Carregando o tempo de hoje';
  static const unavailable = 'tempo indisponível';
  static const spent = 'acabou o tempo de hoje';

  /// How many modules there are: each a fifth of the day.
  static const modules = 5;

  static bool isSpent(ScreenTimeRules rules) {
    final limit = ScreenTimeWords.limit(rules);
    return rules.today.time.state == KidTimeState.timeUp ||
        (limit > 0 && rules.today.used.inMinutes >= limit);
  }

  /// "30 de 50 min", "… · fora do horário" outside the hours, or "acabou
  /// o tempo de hoje" once spent: said calmly, never as a warning.
  static String of(ScreenTimeRules rules) {
    if (isSpent(rules)) return spent;
    final count =
        '${rules.today.used.inMinutes} de ${ScreenTimeWords.limit(rules)}'
        ' min';
    return rules.today.time.state == KidTimeState.outsideWindow
        ? '$count · fora do horário'
        : count;
  }

  /// The modules filled: the whole fifths of the day used, so the last
  /// one fills only once the day is spent.
  static int filled(ScreenTimeRules rules) {
    if (isSpent(rules)) return modules;
    final limit = ScreenTimeWords.limit(rules);
    if (limit <= 0) return 0;
    return (rules.today.used.inMinutes * modules ~/ limit).clamp(0, modules);
  }
}

/// Today's time: a quiet bar while it loads, its words when it cannot
/// be read, otherwise five modules with the words under them saying the
/// same.
class TodayTime extends StatelessWidget {
  const TodayTime(this.today, {super.key});

  static const placeholderKey = Key('today-placeholder');

  /// The child's rules with today's count; null before the read starts.
  final Future<ScreenTimeRules>? today;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: p.muted);
    return FutureBuilder(
      future: today,
      builder: (context, read) {
        if (read.hasError) return Text(TodayWords.unavailable, style: muted);
        final rules = read.data;
        if (rules == null) {
          const height = 10.0;
          return Semantics(
            container: true,
            label: TodayWords.loading,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Container(
                  key: placeholderKey,
                  width: 136,
                  height: height,
                  decoration: BoxDecoration(
                    color: p.outline.withValues(alpha: .24),
                    borderRadius: BorderRadius.circular(
                      height * Radii.screenRatio,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        final words = TodayWords.of(rules);
        final filled = TodayWords.filled(rules);
        return Semantics(
          container: true,
          label: 'Hoje, $words',
          child: ExcludeSemantics(
            // The words always under the modules, so every row has one
            // shape and rows side by side line up.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < TodayWords.modules; i++) ...[
                      if (i > 0) const SizedBox(width: Space.xs),
                      StateModule(filled: i < filled),
                    ],
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(words, style: muted),
              ],
            ),
          ),
        );
      },
    );
  }
}
