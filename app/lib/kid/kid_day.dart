import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/api_error.dart';
import '../curation/kid_catalog.dart';
import '../parental/child_api.dart';
import '../screentime/kid_time.dart';
import '../shell/routes.dart';
import 'pack_player_screen.dart' show PackStart;
import 'paused_profile.dart';
import 'player_screen.dart';

/// Opens a player at [location], handing it [extra]: the child home
/// replaces itself with the player, a page opened from the home stacks
/// it, so the player's end comes back to that page.
typedef PlayerOpener = void Function(String location, Object extra);

/// The child's day as the home read it, shared with the pages that open
/// from the home, so a theme's page plays from the same catalogue, waits
/// on the same play and shows the same note, with no read of its own.
/// The home owns it: it reads the catalogue, and everything that opens
/// from the home goes when the home does.
class KidDay extends ChangeNotifier {
  KidDay(this._api);

  final ChildApi _api;

  /// The child the catalogue is read for; a read for another child that
  /// answers late is dropped.
  String? child;

  /// The catalogue: null while loading; [failed] when the read failed.
  KidCatalog? catalog;
  bool failed = false;

  /// The server answered `consent_required`: the profile is paused until
  /// a guardian authorizes it again.
  bool paused = false;

  /// A play is on its way to the server; the pictures wait.
  bool pending = false;

  /// The kid error note: a refused play, or one the player sent back.
  String? notice;

  /// Each thumbnail read once per visit, however often a picture
  /// rebuilds, on the home or on a page.
  final _thumbs = <String, Future<Uint8List>>{};

  bool _disposed = false;

  bool get asleep =>
      !failed && (catalog?.time.state ?? KidTimeState.ok) != KidTimeState.ok;

  /// Waiting for something outside the child's hands: time again, or an
  /// adult's new authorization.
  bool get waiting => asleep || paused;

  Future<Uint8List> thumbnail(String id) => _thumbs[id] ??= _api.thumbnail(id);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Sets the note shown above the pictures.
  void note(String? message) {
    notice = message;
    _changed();
  }

  /// Reads the catalogue, and again on "Tentar de novo". A [quiet] read
  /// keeps what stands, the picture of a sleeping home or the pictures
  /// the player returned to, while it runs and if it fails. True when
  /// the catalogue came for the child still on the device.
  Future<bool> load({bool quiet = false}) async {
    final child = this.child;
    if (!quiet) {
      catalog = null;
      failed = false;
      paused = false;
      _changed();
    }
    try {
      final read = await _api.catalog();
      if (_disposed || child != this.child) return false;
      catalog = read;
      failed = false;
      paused = false;
      // The paused line is true no longer once the pictures open.
      if (notice == PausedProfile.line) notice = null;
      _changed();
      return true;
    } on Object catch (e) {
      if (_disposed || child != this.child) return false;
      if (e is ApiError && e.code == 'consent_required') {
        // Said even on a quiet read: the pictures no longer open.
        catalog = null;
        failed = false;
        paused = true;
        _changed();
      } else if (!quiet) {
        failed = true;
        _changed();
      }
      return false;
    }
  }

  /// Re-checks the video with the server and opens the player with the
  /// YouTube id it returns. A refusal says so and fetches the catalogue
  /// again, since the video has left it; a day without time says nothing
  /// and fetches it, to sleep. A video longer than the time left asks
  /// nothing and says why.
  Future<void> play(KidVideo video, {required PlayerOpener open}) async {
    if (pending) return;
    if (!video.fits) return note(PlayerScreen.doesNotFit);
    pending = true;
    notice = null;
    _changed();
    try {
      final play = await _api.play(video.id);
      if (!_disposed) open(Routes.watch(video.id), play);
    } on Object catch (e) {
      if (_disposed) return;
      final message = refusalNote(e);
      note(message);
      if (refetchAfter(message)) unawaited(load());
    } finally {
      pending = false;
      _changed();
    }
  }

  /// Opens a pacotinho on its first video the server lets play:
  /// a video refused is passed over for the next; a day without time
  /// sleeps, a paused profile says so, and a video longer than the time
  /// left stops the search, since no pacotinho should open past its first
  /// video; with none left, the note says why the last one did not open.
  Future<void> openPack(KidPack pack, {required PlayerOpener open}) async {
    if (pending) return;
    if (!pack.fits) return note(PlayerScreen.packDoesNotFit);
    pending = true;
    notice = null;
    _changed();
    try {
      Object? refused;
      for (final (i, video) in pack.videos.indexed) {
        try {
          final play = await _api.play(video.id);
          if (!_disposed) {
            open(
              Routes.pack(pack.id),
              PackStart(pack: pack, index: i, play: play),
            );
          }
          return;
        } on Object catch (e) {
          refused = e;
          if (refusesEvery(e) || doesNotFit(e)) break;
        }
      }
      if (_disposed || refused == null) return;
      final message = refusalNote(refused);
      note(message);
      if (refetchAfter(message)) unawaited(load());
    } finally {
      pending = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
