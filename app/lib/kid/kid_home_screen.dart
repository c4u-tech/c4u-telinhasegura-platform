import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_error.dart';
import '../curation/curation.dart' show VideoTheme;
import '../curation/kid_catalog.dart';
import '../design/tokens.dart';
import '../family/avatars.dart';
import '../family/family.dart';
import '../parental/app_mode.dart';
import '../parental/parental.dart' show Profile;
import '../screentime/kid_time.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'empty_shelf.dart';
import 'hold_to_exit.dart';
import 'kid_day.dart';
import 'kid_error_note.dart';
import 'kid_layout.dart';
import 'mosaic.dart';
import 'paused_profile.dart';
import 'player_screen.dart';
import 'room_screen.dart' show RoomDoor;
import 'room_transition.dart' show DoorPlace;
import 'shelves.dart';
import 'sleeping_telinha.dart';
import 'tap_guard.dart';

/// `/crianca`: the child home.
/// The child finds their own avatar, from `AppModeModel.profile` on a
/// shared and a linked device alike, small at the strip's start, and the
/// day on one screen: the highlight, the pictures that play at one tap
/// and a block per theme (the mosaic). Without videos (none yet, or the
/// catalogue failed) the empty shelf or the way to try again stands in
/// its place, larger from 840 px wide. Without a child (deleted, or the
/// read failed) the neutral avatar stands alone and the exit still works.
/// A day without time (used up, or outside the hours) sleeps on the
/// night's dark, the sleeping telinha in the pictures' place, whatever
/// the catalogue holds. A profile waiting for a guardian to authorize it
/// again is paused the same way, saying so; only the exit behind the PIN
/// leaves it.
class KidHomeScreen extends StatefulWidget {
  const KidHomeScreen({super.key});

  /// How often a sleeping home asks whether the day has time again.
  static const wake = Duration(seconds: 60);

  @override
  State<KidHomeScreen> createState() => _KidHomeScreenState();
}

class _KidHomeScreenState extends State<KidHomeScreen>
    with WidgetsBindingObserver {
  late final AppModeModel _mode;
  bool _started = false;

  /// The resting picture's: from a day without time to a paused profile
  /// and back, the mascot that fell asleep stays asleep.
  final _resting = GlobalKey();

  /// The child the profile was read for, and what it answered.
  String? _minorId;
  bool _asked = false;
  Profile? _profile;

  /// The profile read answered `consent_required`; it is read again once
  /// the shelves open.
  bool _profileRefused = false;

  /// The day as read: the catalogue, a play on its way and the note,
  /// shared with the pages that open from here.
  late final KidDay _day;

  /// Asleep or paused, the catalogue is read again on this beat.
  Timer? _wake;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _mode = services.appMode;
    _day = KidDay(services.child)..addListener(_onDay);
    _returns = services.kidReturn;
    _returns.addListener(_onReturn);
    _mode.addListener(_onMode);
    _onMode(initial: true);
  }

  /// The player beneath which this home stays hands back a note, and
  /// whether the shelves changed.
  late final ValueNotifier<KidReturn?> _returns;

  void _onReturn() {
    final back = _returns.value;
    if (back == null) return;
    _returns.value = null;
    if (back.note case final note?) _day.note(note);
    // Without a note the shelves stay where they were while it reads,
    // and stay if it fails; awake past the limit, the home then sleeps.
    if (back.refetch) unawaited(_load(quiet: back.note == null));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wake?.cancel();
    _returns.removeListener(_onReturn);
    _mode.removeListener(_onMode);
    _day.dispose();
    super.dispose();
  }

  static String? _childOf(AppMode? mode) => switch (mode) {
    SharedKid(:final minorId) => minorId,
    LinkedDevice(:final minorId) => minorId,
    _ => null,
  };

  /// Reads the profile, and again when the device's child changes (a linked device re-bound behind the PIN).
  void _onMode({bool initial = false}) {
    final minorId = _childOf(_mode.mode);
    if (_asked && minorId == _minorId) return;
    _asked = true;
    _minorId = minorId;
    _day.child = minorId;
    if (!initial) setState(() => _profile = null);
    if (minorId != null) unawaited(_read(minorId));
    unawaited(_load());
  }

  /// Back in the foreground, a sleeping or paused home asks again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _day.waiting) {
      unawaited(_load(quiet: true));
    }
  }

  /// Reads the shelves, and again on "Tentar de novo"; [quiet] keeps what
  /// stands while it runs and if it fails.
  Future<void> _load({bool quiet = false}) => _day.load(quiet: quiet);

  /// The day changed: the home redraws, beats while it waits, and reads a
  /// profile refused while paused once the shelves open.
  void _onDay() {
    if (!mounted) return;
    setState(() {});
    _beat();
    final minorId = _minorId;
    if (_profileRefused && _day.catalog != null && minorId != null) {
      unawaited(_read(minorId));
    }
  }

  /// Asleep or paused, the catalogue is read every [KidHomeScreen.wake];
  /// otherwise, not at all.
  void _beat() {
    if (!_day.waiting) {
      _wake?.cancel();
      _wake = null;
    } else {
      _wake ??= Timer.periodic(
        KidHomeScreen.wake,
        (_) => unawaited(_load(quiet: true)),
      );
    }
  }

  /// Opens the player in the home's place.
  void _open(String location, Object extra) =>
      GoRouter.of(context).go(location, extra: extra);

  void _play(KidVideo video) => unawaited(_day.play(video, open: _open));

  void _openPack(KidPack pack) => unawaited(_day.openPack(pack, open: _open));

  /// The note floats over the home's foot, wherever the home stands.
  Widget _note(String message) =>
      FloatingNote(message, asleep: restsNote(message));

  /// A theme's block tapped: the theme's page grows from where the block
  /// stood, on the day this home read. A note from before stays here.
  void _openTheme(VideoTheme theme, DoorPlace from) {
    _day.note(null);
    context.go(
      Routes.theme(theme),
      extra: RoomDoor(day: _day, from: from),
    );
  }

  /// The door to every pacotinho, opening the same way.
  void _openPacks(DoorPlace from) {
    _day.note(null);
    context.go(
      Routes.kidPacks,
      extra: RoomDoor(day: _day, from: from),
    );
  }

  Future<void> _read(String minorId) async {
    _profileRefused = false;
    try {
      final profile = await _mode.profile();
      if (mounted && minorId == _minorId) setState(() => _profile = profile);
    } on Object catch (e) {
      // The neutral avatar stays; the exit still works. Paused, it is read
      // again once the shelves open.
      if (minorId == _minorId) {
        _profileRefused = e is ApiError && e.code == 'consent_required';
      }
    }
  }

  // A touch just after the home appears, or just after it changes what
  // it shows, was aimed at what stood there before.
  @override
  Widget build(BuildContext context) {
    final catalog = _day.catalog;
    final plan = catalog == null
        ? null
        : MosaicPlan.of(catalog, band: _profile?.ageBand ?? AgeBand.unknown);
    final scene = switch (_day) {
      KidDay(paused: true) => _Scene.paused,
      KidDay(failed: true) => _Scene.failed,
      KidDay(asleep: true) => _Scene.asleep,
      _ when plan == null => _Scene.loading,
      _ when plan.isEmpty => _Scene.empty,
      _ => _Scene.pictures,
    };
    return TapGuard(scene: scene, child: _screen(context, plan));
  }

  Widget _screen(BuildContext context, MosaicPlan? plan) {
    final catalog = _day.catalog;
    final failed = _day.failed;
    final pending = _day.pending;
    // A day without time sleeps, shelves or none.
    final time = failed ? null : catalog?.time.state;
    final asleep = time != null && time != KidTimeState.ok;
    // Asleep, the door it opens offers more time.
    final exit = HoldToExit(
      onExit: () {
        AppScope.of(context).moreTimeErrand = asleep;
        context.go(Routes.kidExit);
      },
    );
    final paused = _day.paused;
    final wide = MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint;
    // The child and their picture at the strip's start, read as their
    // nickname: not a target.
    final avatar = Semantics(
      image: true,
      label: _profile?.nickname,
      child: AvatarDisc(
        _profile?.avatar ?? Avatar.unknown,
        size: KidMosaic.avatar,
        excludeSemantics: true,
      ),
    );
    final notice = _day.notice;
    if (!failed && !asleep && !paused && !(plan?.isEmpty ?? false)) {
      return KidLayout(
        exit: exit,
        lead: avatar,
        fullWidth: true,
        scrolls: false,
        rise: KidMosaic.rise,
        child: catalog == null
            ? MosaicLoading(
                band: _profile?.ageBand,
                note: notice == null ? null : _note(notice),
              )
            : KidMosaic(
                catalog: catalog,
                plan: plan,
                band: _profile?.ageBand ?? AgeBand.unknown,
                thumbnail: _day.thumbnail,
                onPlay: pending ? null : _play,
                onOpenPack: pending ? null : _openPack,
                onOpenTheme: pending ? null : _openTheme,
                onOpenPacks: pending ? null : _openPacks,
                note: notice == null ? null : _note(notice),
              ),
      );
    }
    if (!asleep && !paused) {
      // The picture grows on a wide screen, as the sleeping home's does.
      final scale = wide ? 1.5 : 1.25;
      return KidLayout(
        exit: exit,
        lead: avatar,
        // Below the frame's kid theme, so the text takes the kid dialect.
        child: Builder(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notice != null) ...[
                KidErrorNote(notice, asleep: restsNote(notice)),
                const SizedBox(height: Space.xl),
              ],
              if (failed)
                ShelvesFailed(onRetry: () => unawaited(_load()), scale: scale)
              else
                Center(child: EmptyShelf(scale: scale)),
            ],
          ),
        ),
      );
    }
    // Asleep or paused, the home is a dark room: the strip as on the
    // awake home, and the mascot asleep on its wire.
    final scale = wide ? 1.5 : 1.25;
    return KidLayout(
      exit: exit,
      lead: avatar,
      ground: BrandColors.dark,
      // Below the frame's kid theme, so the text takes the kid dialect.
      child: Center(
        child: paused
            ? PausedProfile(scale: scale, pictureKey: _resting)
            : SleepingTelinha(state: time!, scale: scale, pictureKey: _resting),
      ),
    );
  }
}

/// What the home shows, as far as a touch is concerned.
enum _Scene { loading, pictures, empty, failed, asleep, paused }
