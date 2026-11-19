import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/tevi.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid_mode/hand_over_screen.dart' show ChildChoice;
import '../parental/app_mode.dart';
import '../parental/parental.dart' show Profile;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'kid_layout.dart';
import 'paused_profile.dart';

/// `/crianca/quem`: the linked device's profile picker, on ink, behind the
/// PIN the exit gate checked. The mascot stands looking back from the top
/// of a dark panel that holds the question and the family's children at
/// [avatar] dp, each read by nickname, the device's own child chosen;
/// choosing one re-binds the device and lands on that child's home. A
/// child whose profile waits for a guardian's new authorization stays in
/// the row, disabled, and a line under the row says why. The
/// PIN lives in `AppServices.profilePick` only while this screen does:
/// leaving drops it, whichever way.
class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  /// A child's avatar: large enough that a child finds themself at once.
  static const avatar = 132.0;

  /// The dark panel the children stand in.
  static const panelKey = Key('picker-panel');

  /// The mascot standing on the panel.
  static const tevi = 104.0;

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  final _switch = Submission();
  late final AppServices _services;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _services = AppScope.of(context);
  }

  @override
  void dispose() {
    _services.profilePick = null;
    _switch.dispose();
    super.dispose();
  }

  /// A device unlinked meanwhile answers `401`: the mode moves to the
  /// guardian's and the router leaves for the entry screen.
  Future<void> _choose(Profile child) async {
    final pick = _services.profilePick;
    if (pick == null) return;
    final router = GoRouter.of(context);
    final ok = await _switch.run(
      () => _services.appMode.switchProfile(pin: pick.pin, minorId: child.id),
      overrides: const {'not_found': Copy.childGone},
    );
    if (ok) router.go(Routes.kidHome);
  }

  static const _gap = Space.lg;

  /// The width of a row holding as many children as fit in [room], then
  /// evened out so no row is left with a lone child where the rows could
  /// share them: four children in three places make two rows of two.
  static double _rowWidth(int children, double room) {
    final tile = ChildChoice.widthFor(ProfilePickerScreen.avatar);
    final fit = math.max(1, ((room + _gap) / (tile + _gap)).floor());
    final rows = (children / fit).ceil();
    final perRow = rows == 0 ? 1 : (children / rows).ceil();
    return perRow * tile + (perRow - 1) * _gap;
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _services.profilePick?.profiles ?? const <Profile>[];
    final current = switch (_services.appMode.mode) {
      LinkedDevice(:final minorId) => minorId,
      _ => null,
    };
    final panel = DecoratedBox(
      key: ProfilePickerScreen.panelKey,
      decoration: const BoxDecoration(
        color: BrandColors.dark,
        borderRadius: BorderRadius.all(Radius.circular(Radii.card)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.xl,
          Space.md,
          Space.xl,
        ),
        child: ListenableBuilder(
          listenable: _switch,
          // Built below the frame's kid theme, so the text takes the kid
          // dialect.
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Quem vai assistir?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: Space.xl),
              LayoutBuilder(
                builder: (context, box) => Center(
                  child: SizedBox(
                    width: _rowWidth(profiles.length, box.maxWidth),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: _gap,
                      runSpacing: _gap,
                      children: [
                        for (final child in profiles)
                          ChildChoice(
                            nickname: child.nickname,
                            avatar: child.avatar,
                            avatarSize: ProfilePickerScreen.avatar,
                            selected: child.id == current,
                            onTap: _switch.blocked || !child.consentCurrent
                                ? null
                                : () => _choose(child),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              for (final child in profiles.where((p) => !p.consentCurrent)) ...[
                const SizedBox(height: Space.lg),
                Text(
                  '${child.nickname}: ${PausedProfile.line}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: context.palette.muted),
                ),
              ],
              if (_switch.message case final message?) ...[
                const SizedBox(height: Space.lg),
                ErrorNote(message),
              ],
            ],
          ),
        ),
      ),
    );
    // The mascot's legs land on the panel's top edge, its body over the
    // panel's middle, looking back at the child choosing.
    const size = ProfilePickerScreen.tevi;
    final stand =
        size * (TeviPainter.perchY - TeviPainter.body.top) -
        TeviPainter.perchOverlap;
    return KidLayout(
      // The mascot stands whole on the screen: no small one beside it.
      mark: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(top: stand),
                child: panel,
              ),
              Positioned(
                top:
                    stand +
                    TeviPainter.perchOverlap -
                    size * TeviPainter.perchY,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: Offset((.5 - TeviPainter.body.center.dx) * size, 0),
                    child: Builder(
                      builder: (context) => Tevi(
                        size: size,
                        look: TeviLook.lookingBack,
                        night: TeviGround.nightAt(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xxl),
          KidBack(onPressed: () => context.go(Routes.kidHome)),
        ],
      ),
    );
  }
}
