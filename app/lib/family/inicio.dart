import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid_mode/hand_over.dart';
import '../screentime/screentime_api.dart';
import '../screentime/today.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'avatars.dart';
import 'child_page.dart';
import 'family.dart';
import 'family_write.dart';
import 'first_run.dart' show firstRunSteps;
import 'widgets.dart';

/// The home's title, by the device's local time: "Bom dia" from 5 h,
/// "Boa tarde" from noon, "Boa noite" from 18 h.
String greeting(DateTime now) => switch (now.hour) {
  >= 5 && < 12 => 'Bom dia',
  >= 12 && < 18 => 'Boa tarde',
  _ => 'Boa noite',
};

/// The home once the family is ready: one row per child on the child
/// band, each ending in handing the device to that child, then suggesting
/// a video. While the family has no child, or no PIN, one calm row names
/// the next step and opens the first run there. Each child's day is read
/// on its own, so one slow or failed read holds up no other row.
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

  /// Whether the family has a PIN: null until read, and after a failed
  /// read, which shows nothing rather than a step that may be done.
  bool? _pinSet;

  /// Whether Início was the screen on top at the last look.
  bool _current = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Back on top after a screen of its own (the first run, the PIN
    // changed elsewhere): the PIN may have been created meanwhile, or a
    // failed read may answer now.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_current && _started) _readPin();
    _current = current;
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
    _readPin();
  }

  /// The PIN matters once there is a child to hand the device to.
  Future<void> _readPin() async {
    if (widget.family.minors.isEmpty) return;
    try {
      final set = await AppScope.of(context).parental.pinIsSet();
      if (mounted) setState(() => _pinSet = set);
    } on Object {
      // Início stays as built.
    }
  }

  /// The row naming the first run's next step, or null once both the
  /// child and the PIN exist.
  Widget? _resume() {
    final (title, step) = switch ((widget.family.minors.isEmpty, _pinSet)) {
      (true, _) => ('Continuar: cadastrar uma criança', 1),
      (false, false) => ('Continuar: criar o PIN', 2),
      _ => (null, 0),
    };
    if (title == null) return null;
    return Doors(
      children: [
        DoorRow(
          title: title,
          semanticsLabel: '$title, Passo $step de $firstRunSteps',
          onTap: () => context.go(Routes.firstRun),
          child: StepMarks(step: step, of: firstRunSteps),
        ),
      ],
    );
  }

  Future<void> _give(Minor minor) async {
    // Without a PIN the hand-over would be refused: the first run creates
    // it, then hands the device to this child.
    if (_pinSet == false) {
      context.go(Routes.firstRunFor(child: minor.id));
      return;
    }
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
      final waiting = _write.blocked;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_write.message case final message?) ...[
            ErrorNote(message),
            const SizedBox(height: Space.lg),
          ],
          if (_resume() case final resume?) ...[
            resume,
            if (minors.isNotEmpty) const SizedBox(height: Space.xl),
          ],
          if (minors.isNotEmpty)
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
                    onOpen: () => context.go(
                      Routes.child(minor.id),
                      extra: ChildPage.fromHome,
                    ),
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
/// time screen, and the filled "Entregar para {apelido}" under them. The
/// avatar, the nickname and the day together open the child's page.
class ChildRow extends StatelessWidget {
  const ChildRow({
    super.key,
    required this.minor,
    required this.today,
    required this.onHandOver,
    required this.onMoreTime,
    required this.onOpen,
    this.busy = false,
  });

  static const todayPlaceholderKey = TodayTime.placeholderKey;

  final Minor minor;

  /// The child's rules with today's count; null before the read starts.
  final Future<ScreenTimeRules>? today;
  final VoidCallback? onHandOver;
  final VoidCallback onMoreTime;

  /// Opens the child's page.
  final VoidCallback onOpen;
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
              Expanded(
                child: _OpenTarget(
                  label: 'Abrir a página de ${minor.nickname}',
                  onTap: onOpen,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AvatarDisc(
                        minor.avatar,
                        size: 56,
                        excludeSemantics: true,
                      ),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Text(
                                minor.nickname,
                                style: text.titleMedium,
                              ),
                            ),
                            const SizedBox(height: Space.xs),
                            TodayTime(today),
                          ],
                        ),
                      ),
                    ],
                  ),
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

/// The part of a child's row that opens the child's page: one target,
/// read by [label] with today's words inside it, washed on hover and
/// press and ringed on focus like a door row.
class _OpenTarget extends StatefulWidget {
  const _OpenTarget({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_OpenTarget> createState() => _OpenTargetState();
}

class _OpenTargetState extends State<_OpenTarget> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.small),
    );
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape.copyWith(side: ring ?? BorderSide.none),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (focused) => setState(() => _focused = focused),
          customBorder: shape,
          focusColor: Colors.transparent,
          hoverColor: p.outline.withValues(alpha: .08),
          highlightColor: p.outline.withValues(alpha: .12),
          splashColor: p.outline.withValues(alpha: .12),
          child: widget.child,
        ),
      ),
    );
  }
}
