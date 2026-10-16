import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/band_transition.dart';
import '../design/pin_pad.dart';
import '../design/tokens.dart';
import '../family/profile_fields.dart' show SelectableRow;
import '../parental/app_mode.dart';
import '../parental/parental.dart' show Profile;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'hold_to_exit.dart';
import 'kid_layout.dart';

/// `/crianca/sair`: the exit gate, on ink, for the adult.
/// The PIN goes to the server, which alone decides: on a shared
/// device it lifts the lock and the screen closes back onto the band of
/// the family home. A wrong PIN empties the pad and says so; a cooldown
/// disables it while the time left counts down. On a linked device it
/// opens the profile picker instead. The PIN is never kept after
/// its call, but across that picker in memory.
///
/// Opened by a player's link, the gate is that
/// link's door: on a shared device the PIN is the exit itself and the link
/// then opens outside the app; on a linked device the PIN is checked and
/// the link opens while the video waits. "Voltar" goes back to the video.
///
/// Opened from the sleeping home, the
/// gate also offers more time above the pad, as a choice of one beside
/// its usual exit, which is chosen on arrival: a time and the PIN extend
/// the child's day and return to the home, still in kid mode; the usual
/// exit is the gate as above. Nowhere else does it offer time.
class KidExitScreen extends StatefulWidget {
  const KidExitScreen({super.key});

  /// The minutes an adult may add from the sleeping home; the
  /// server holds the day to its cap.
  static const moreTime = [15, 30, 60];

  @override
  State<KidExitScreen> createState() => _KidExitScreenState();
}

class _KidExitScreenState extends State<KidExitScreen> {
  final _pad = PinPadController();
  final _check = Submission();

  /// The link this gate is the door for, if a player sent it.
  Uri? _link;
  AppServices? _services;

  /// Opened from the sleeping home: the gate offers more time.
  bool _offersTime = false;

  /// The minutes chosen; null for the usual exit, chosen on arrival.
  int? _minutes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    final services = _services = AppScope.of(context);
    _link = services.linkErrand;
    // Taken at once: the errand opens this door only.
    _offersTime = services.moreTimeErrand && _link == null;
    services.moreTimeErrand = false;
  }

  @override
  void dispose() {
    // However the gate closes, the link does not outlive it.
    if (_link != null) _services?.linkErrand = null;
    _check.dispose();
    _pad.dispose();
    super.dispose();
  }

  void _submit(String pin) {
    if (_minutes case final minutes?) {
      _extend(pin, minutes);
      return;
    }
    switch (AppScope.of(context).appMode.mode) {
      case LinkedDevice() when _link != null:
        _openLink(pin);
      case LinkedDevice():
        _openPicker(pin);
      case _:
        _unlock(pin);
    }
  }

  /// More time today behind the PIN, on either device: the home
  /// beneath reads its catalogue again and wakes; kid mode goes on.
  /// `over_cap` and the PIN's own codes say so above the pad, the choice
  /// kept.
  Future<void> _extend(String pin, int minutes) async {
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    final ok = await _check.run(
      () => services.child.extend(pin: pin, minutes: minutes),
    );
    _pad.clear();
    if (!ok || !mounted) return;
    services.kidReturn.value = (note: null, refetch: true);
    router.go(Routes.kidHome);
  }

  /// A linked device: the PIN checked by the same profiles read the
  /// picker uses, the link opens outside and the video waits.
  Future<void> _openLink(String pin) async {
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    final ok = await _check.run(() => services.appMode.listProfiles(pin));
    _pad.clear();
    if (!ok || !mounted) return;
    final link = _take();
    router.pop();
    if (link != null) await services.links.open(link);
  }

  /// The link, let go of as it is used.
  Uri? _take() {
    final link = _link;
    _link = null;
    _services?.linkErrand = null;
    return link;
  }

  void _back() {
    if (_link != null) {
      _take();
      context.pop();
    } else {
      context.go(Routes.kidHome);
    }
  }

  /// A shared device: the lock lifts and the app lands on the family home
  /// as the child's screen closes back onto the band. An unlock
  /// that finds the family gone ends the session (`401`): the router leaves for the entry screen, which says why.
  Future<void> _unlock(String pin) async {
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    final ok = await _check.run(
      () => services.appMode.unlock(pin),
      handle: (e) {
        if (e.status != 401) return false;
        services.entryNotice = Copy.familyGone;
        return true;
      },
    );
    _pad.clear();
    if (!ok) return;
    // A link's door: kid mode has ended, as any exit does; the link then
    // opens outside.
    final link = _take();
    // The mode's move already sends the router home; this arrival says
    // how it comes in.
    router.go(Routes.home, extra: BandMotion.shrink);
    if (link != null) await services.links.open(link);
  }

  /// A linked device: the PIN opens the profile picker with the family's
  /// children. The PIN rides to the picker in memory only, for its
  /// one re-bind. A device unlinked meanwhile answers `401`: the mode
  /// moves to the guardian's and the router leaves for the entry screen.
  Future<void> _openPicker(String pin) async {
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    List<Profile>? profiles;
    final ok = await _check.run(
      () async => profiles = await services.appMode.listProfiles(pin),
    );
    _pad.clear();
    if (!ok || !mounted) return;
    services.profilePick = (pin: pin, profiles: profiles!);
    router.go(Routes.profilePicker);
  }

  @override
  Widget build(BuildContext context) => KidLayout(
    child: ListenableBuilder(
      listenable: _check,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'PIN dos pais',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: Space.xl),
          if (_offersTime) ...[_choice(), const SizedBox(height: Space.xl)],
          if (_check.message case final message?) ...[
            ErrorNote(message),
            const SizedBox(height: Space.lg),
          ],
          Center(
            child: PinPad(
              controller: _pad,
              enabled: !_check.blocked,
              onSubmit: _submit,
            ),
          ),
          const SizedBox(height: Space.xxl),
          KidBack(onPressed: _back),
        ],
      ),
    ),
  );

  /// More time as one row of three 64 dp keys, then the usual exit as
  /// the one full-width row: one choice, read as radios,
  /// short enough that the pad and "Voltar" stay in view.
  /// Where a key's words would wrap (large text, a narrow
  /// screen), the times stand as full-width rows instead, which may
  /// scroll; the choice reads and behaves the same. The usual exit names
  /// itself as the corner exit does.
  Widget _choice() {
    final busy = _check.busy;
    VoidCallback? choose(int? minutes) =>
        busy ? null : () => setState(() => _minutes = minutes);
    return LayoutBuilder(
      builder: (context, box) {
        final keyed = _keysFit(context, box.maxWidth);
        final times = [
          for (final m in KidExitScreen.moreTime)
            SelectableRow(
              label: 'Mais $m min',
              text: keyed ? _short(m) : null,
              asKey: keyed,
              selected: _minutes == m,
              onTap: choose(m),
              height: KidSizes.target,
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: Space.sm),
            SelectableRow(
              label: HoldToExit.label,
              selected: _minutes == null,
              onTap: choose(null),
              height: KidSizes.target,
            ),
          ],
        );
      },
    );
  }

  /// A key's words: the number and its unit never part.
  static String _short(int minutes) => '$minutes min';

  /// Whether every key's module, gap and words fit one line inside a third
  /// of [width], at the text scale in force.
  bool _keysFit(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final key = (width - 2 * Space.sm) / 3 - 2 * Space.sm;
    const module = 10 * 58 / 33;
    for (final m in KidExitScreen.moreTime) {
      final words = TextPainter(
        text: TextSpan(text: _short(m), style: style),
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
