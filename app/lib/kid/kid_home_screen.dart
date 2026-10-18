import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_error.dart';
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
import 'kid_error_note.dart';
import 'kid_layout.dart';
import 'pack_player_screen.dart' show PackStart;
import 'paused_profile.dart';
import 'player_screen.dart';
import 'shelves.dart';
import 'sleeping_telinha.dart';

/// `/crianca`: the child home.
/// The child finds their own avatar, from `AppModeModel.profile` on a
/// shared and a linked device alike, small above their theme shelves.
/// Without shelves (none yet, or the catalogue failed) the avatar and
/// nickname stand large above the empty shelf or the way to try again,
/// both larger from 840 px wide. Without a child (deleted, or the read
/// failed) the neutral avatar stands alone and the exit still works.
/// A day without time (used up, or outside the hours) sleeps:
/// the same composition with the sleeping telinha in the shelf's place,
/// whatever the shelves hold. A profile waiting for a guardian to
/// authorize it again is paused the same way, saying so; only the exit
/// behind the PIN leaves it.
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

  /// The child the profile was read for, and what it answered.
  String? _minorId;
  bool _asked = false;
  Profile? _profile;

  /// The child's shelves: null while loading; [_failed] when the read
  /// failed.
  KidCatalog? _catalog;
  bool _failed = false;

  /// The server answered `consent_required`: the profile is paused until
  /// a guardian authorizes it again.
  bool _paused = false;

  /// The profile read answered `consent_required`; it is read again once
  /// the shelves open.
  bool _profileRefused = false;

  /// Each thumbnail read once per visit, however often a tile rebuilds.
  final _thumbs = <String, Future<Uint8List>>{};

  /// A play is on its way to the server; the shelves wait.
  bool _pending = false;

  /// The kid error note: a refused play here, or one the player sent
  /// back.
  String? _notice;

  /// Asleep or paused, the catalogue is read again on this beat.
  Timer? _wake;

  bool get _asleep =>
      !_failed && (_catalog?.time.state ?? KidTimeState.ok) != KidTimeState.ok;

  /// Waiting for something outside the child's hands: time again, or an
  /// adult's new authorization.
  bool get _waiting => _asleep || _paused;

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
    if (back.note case final note?) setState(() => _notice = note);
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
    if (!initial) setState(() => _profile = null);
    if (minorId != null) unawaited(_read(minorId));
    unawaited(_load());
  }

  /// Back in the foreground, a sleeping or paused home asks again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waiting) {
      unawaited(_load(quiet: true));
    }
  }

  /// Reads the shelves, and again on "Tentar de novo". A [quiet]
  /// read keeps what stands, the picture of a sleeping home or the
  /// shelves the player returned to, while it runs and if it fails.
  Future<void> _load({bool quiet = false}) async {
    final minorId = _minorId;
    if (!quiet) {
      setState(() {
        _catalog = null;
        _failed = false;
        _paused = false;
      });
    }
    try {
      final catalog = await AppScope.of(context).child.catalog();
      if (mounted && minorId == _minorId) {
        setState(() {
          _catalog = catalog;
          _failed = false;
          _paused = false;
        });
        // The profile read was refused while paused: read it now.
        if (_profileRefused && minorId != null) unawaited(_read(minorId));
      }
    } on Object catch (e) {
      if (mounted && minorId == _minorId) {
        if (e is ApiError && e.code == 'consent_required') {
          // Said even on a quiet read: the shelves no longer open.
          setState(() {
            _catalog = null;
            _failed = false;
            _paused = true;
          });
        } else if (!quiet) {
          setState(() => _failed = true);
        }
      }
    }
    if (mounted) _beat();
  }

  /// Asleep or paused, the catalogue is read every [KidHomeScreen.wake];
  /// otherwise, not at all.
  void _beat() {
    if (!_waiting) {
      _wake?.cancel();
      _wake = null;
    } else {
      _wake ??= Timer.periodic(
        KidHomeScreen.wake,
        (_) => unawaited(_load(quiet: true)),
      );
    }
  }

  /// Re-checks the video with the server and opens the player with the
  /// YouTube id it returns. A refusal says so and fetches the
  /// shelves again, since the video has left them; a day without
  /// time says nothing and fetches them, to sleep.
  Future<void> _play(KidVideo video) async {
    if (_pending) return;
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _pending = true;
      _notice = null;
    });
    try {
      final play = await services.child.play(video.id);
      if (mounted) router.go(Routes.watch(video.id), extra: play);
    } on Object catch (e) {
      if (!mounted) return;
      final note = refusalNote(e);
      setState(() => _notice = note);
      if (refetchAfter(note)) unawaited(_load());
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  /// Opens a pacotinho on its first video the server lets play:
  /// a video refused is passed over for the next; a day without time
  /// sleeps, and a paused profile says so; with none left, the shelves say why the last one did not
  /// open.
  Future<void> _openPack(KidPack pack) async {
    if (_pending) return;
    final services = AppScope.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _pending = true;
      _notice = null;
    });
    try {
      Object? refused;
      for (final (i, video) in pack.videos.indexed) {
        try {
          final play = await services.child.play(video.id);
          if (mounted) {
            router.go(
              Routes.pack(pack.id),
              extra: PackStart(pack: pack, index: i, play: play),
            );
          }
          return;
        } on Object catch (e) {
          refused = e;
          if (refusesEvery(e)) break;
        }
      }
      if (!mounted || refused == null) return;
      final note = refusalNote(refused);
      setState(() => _notice = note);
      if (refetchAfter(note)) unawaited(_load());
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Widget _note(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
    child: KidErrorNote(message),
  );

  Future<Uint8List> _thumbnail(String id) =>
      _thumbs[id] ??= AppScope.of(context).child.thumbnail(id);

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

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    // A day without time sleeps, shelves or none.
    final time = _failed ? null : catalog?.time.state;
    final asleep = time != null && time != KidTimeState.ok;
    // Asleep, the door it opens offers more time.
    final exit = HoldToExit(
      onExit: () {
        AppScope.of(context).moreTimeErrand = asleep;
        context.go(Routes.kidExit);
      },
    );
    final paused = _paused;
    if (!_failed &&
        !asleep &&
        !paused &&
        (catalog == null ||
            catalog.shelves.isNotEmpty ||
            catalog.packs.isNotEmpty)) {
      return KidLayout(
        exit: exit,
        fullWidth: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Semantics(
                image: true,
                label: _profile?.nickname,
                child: AvatarDisc(
                  _profile?.avatar ?? Avatar.unknown,
                  size: KidShelves.avatar,
                  excludeSemantics: true,
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
            if (_notice case final notice?) _note(notice),
            if (catalog == null)
              const ShelvesLoading()
            else
              KidShelves(
                catalog: catalog,
                thumbnail: _thumbnail,
                onPlay: _pending ? null : _play,
                onOpenPack: _pending ? null : _openPack,
              ),
          ],
        ),
      );
    }
    final profile = _profile;
    final wide = MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint;
    final avatarSize = wide ? KidSizes.avatarWide : KidSizes.avatarLarge;
    return KidLayout(
      exit: exit,
      // Below the frame's kid theme, so the text takes the kid dialect.
      child: Builder(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The child and their picture, read as one: the nickname.
            MergeSemantics(
              child: Column(
                children: [
                  AvatarDisc(
                    profile?.avatar ?? Avatar.unknown,
                    size: avatarSize,
                    excludeSemantics: true,
                  ),
                  if (profile != null) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      profile.nickname,
                      textAlign: TextAlign.center,
                      style: wide
                          ? Theme.of(context).textTheme.displaySmall
                          : Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.xxxl),
            // Paused, the line below already says why nothing opens.
            if (_notice case final notice? when !asleep && !paused) ...[
              KidErrorNote(notice),
              const SizedBox(height: Space.xl),
            ],
            if (_failed)
              ShelvesFailed(onRetry: () => unawaited(_load()))
            else if (paused)
              Center(
                child: PausedProfile(scale: avatarSize / KidSizes.avatarLarge),
              )
            else if (asleep)
              Center(
                child: SleepingTelinha(
                  state: time,
                  scale: avatarSize / KidSizes.avatarLarge,
                ),
              )
            else
              // The shelf grows as the avatar does.
              Center(
                child: EmptyShelf(scale: avatarSize / KidSizes.avatarLarge),
              ),
          ],
        ),
      ),
    );
  }
}
