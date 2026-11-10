import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid_mode/hand_over.dart';
import '../screentime/kid_time.dart';
import '../screentime/screentime_api.dart';
import '../screentime/words.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'avatars.dart';
import 'family.dart';
import 'family_write.dart';

/// The home's title, by the device's local time: "Bom dia" from 5 h,
/// "Boa tarde" from noon, "Boa noite" from 18 h.
String greeting(DateTime now) => switch (now.hour) {
  >= 5 && < 12 => 'Bom dia',
  >= 12 && < 18 => 'Boa tarde',
  _ => 'Boa noite',
};

/// A child's day on the home, in words the row shows beside its modules.
abstract final class TodayWords {
  static const loading = 'Carregando o tempo de hoje';
  static const unavailable = 'tempo indisponível';
  static const spent = 'acabou o tempo de hoje';

  /// How many of the row's modules there are: each a fifth of the day.
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
        '\u00a0min';
    return rules.today.time.state == KidTimeState.outsideWindow
        ? '$count\u00a0· fora do horário'
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

/// The home once the family is ready: one row per child on the child
/// band, each ending in handing the device to that child, then suggesting
/// a video. With no child yet, the way to register one. Each child's day
/// is read on its own, so one slow or failed read holds up no other row.
class Inicio extends StatefulWidget {
  const Inicio({super.key, required this.family});

  final Family family;

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  late final FamilyWrite _write;
  bool _started = false;

  /// The children the reads were started for, and each one's read.
  String? _readFor;
  var _today = <String, Future<ScreenTimeRules>>{};

  /// The child being handed the device, while the hand-over runs.
  String? _handing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = FamilyWrite(
      family: AppScope.of(context).familyModel,
      confirm: () => confirmItsYou(context),
    );
    _read();
  }

  @override
  void didUpdateWidget(Inicio old) {
    super.didUpdateWidget(old);
    _read();
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  void _read() {
    final minors = widget.family.minors;
    final key = minors.map((m) => m.id).join(',');
    if (key == _readFor) return;
    _readFor = key;
    final api = AppScope.of(context).screenTime;
    _today = {for (final m in minors) m.id: api.rules(m.id)};
  }

  Future<void> _give(Minor minor) async {
    _write.clearMessage();
    setState(() => _handing = minor.id);
    await handOverTo(context, _write, minor);
    if (mounted) setState(() => _handing = null);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) {
      final minors = widget.family.minors;
      final text = Theme.of(context).textTheme;
      final waiting = _write.blocked;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_write.message case final message?) ...[
            ErrorNote(message),
            const SizedBox(height: Space.lg),
          ],
          if (minors.isEmpty) ...[
            Text('Nenhuma criança cadastrada ainda.', style: text.bodyLarge),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Cadastrar criança',
              onPressed: () => context.go(Routes.newChild),
            ),
          ] else
            ChildBand(
              columns: (ShellFrame.maybeOf(context)?.rail ?? false) ? 2 : 1,
              children: [
                for (final minor in minors)
                  ChildRow(
                    minor: minor,
                    today: _today[minor.id],
                    busy: _handing == minor.id && _write.busy,
                    onHandOver: waiting ? null : () => _give(minor),
                    onMoreTime: () => context.go(Routes.moreTime(minor.id)),
                  ),
              ],
            ),
          const SizedBox(height: Space.xxl),
          QuietAction(
            label: 'Sugerir um vídeo',
            onPressed: () => context.go(Routes.newSuggestion),
          ),
        ],
      );
    },
  );
}

/// The family's children grouped on one low-alpha ink band, the rows
/// divided by reed hairlines: no card, no shadow. Beside the rail it
/// sets them in [columns].
class ChildBand extends StatelessWidget {
  const ChildBand({super.key, required this.children, this.columns = 1});

  static const bandKey = Key('child-band');

  final List<Widget> children;
  final int columns;

  /// The band's ink, low enough that cream text and the filled actions on
  /// it keep their contrast; the dark ground takes more of it to show.
  static Color tint(Palette p) =>
      p.field.withValues(alpha: p.brightness == Brightness.light ? .08 : .32);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hairline = Divider(
      height: 1,
      thickness: 1,
      color: p.outline.withValues(alpha: .5),
    );
    final lines = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      if (i > 0) lines.add(hairline);
      lines.add(
        columns == 1
            ? children[i]
            // Side by side, the rows share their height, so each pair's
            // hand-over buttons stand on one line.
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: Space.xl),
                      Expanded(
                        child: i + c < children.length
                            ? children[i + c]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
      );
    }
    return DecoratedBox(
      key: bandKey,
      decoration: BoxDecoration(
        color: tint(p),
        borderRadius: BorderRadius.circular(10 * FieldSizes.bandUnit),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lines,
        ),
      ),
    );
  }
}

/// One child on the home: the 56 dp avatar, the nickname, today's time
/// as screen modules with its words, a quiet "+ tempo" opening the more
/// time screen, and the filled "Entregar para {apelido}" under them.
class ChildRow extends StatelessWidget {
  const ChildRow({
    super.key,
    required this.minor,
    required this.today,
    required this.onHandOver,
    required this.onMoreTime,
    this.busy = false,
  });

  static const todayPlaceholderKey = Key('today-placeholder');

  final Minor minor;

  /// The child's rules with today's count; null before the read starts.
  final Future<ScreenTimeRules>? today;
  final VoidCallback? onHandOver;
  final VoidCallback onMoreTime;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // At large text the quiet action leaves the line for its own, so the
    // nickname and the words keep the width.
    final large = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    final more = QuietAction(
      label: '+ tempo',
      semanticsLabel: 'Mais tempo para ${minor.nickname}',
      inline: true,
      onPressed: onMoreTime,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // Given a taller slot (beside another row), the button keeps to
        // its foot.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top-aligned, so a longer line of words never moves the avatar
          // or "+ tempo" off the line they share with the row beside.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarDisc(minor.avatar, size: 56, excludeSemantics: true),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(minor.nickname, style: text.titleMedium),
                    const SizedBox(height: Space.xs),
                    _Today(today),
                  ],
                ),
              ),
              if (!large) ...[const SizedBox(width: Space.sm), more],
            ],
          ),
          if (large) ...[
            const SizedBox(height: Space.xs),
            Align(alignment: AlignmentDirectional.centerStart, child: more),
          ],
          const SizedBox(height: Space.md),
          PrimaryButton(
            label: 'Entregar para ${minor.nickname}',
            busy: busy,
            onPressed: onHandOver,
          ),
        ],
      ),
    );
  }
}

/// Today's time: a quiet bar while it loads, its words when it cannot
/// be read, otherwise the modules and the words saying the same.
class _Today extends StatelessWidget {
  const _Today(this.today);

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
            label: TodayWords.loading,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Container(
                  key: ChildRow.todayPlaceholderKey,
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
