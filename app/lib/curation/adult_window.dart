import 'dart:async';

import 'package:flutter/material.dart';

import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid/kid_player.dart';
import '../shell/services.dart';
import 'adult_player.dart';

/// The adult player hosted on a curator's or admin's screen:
/// one video loaded without playing, links out of
/// it opened in the browser, another video playing in place stopped and
/// the video loaded again, a failure shown as the error note in the
/// window's place. The player goes when the screen does.
mixin AdultWindow<T extends StatefulWidget> on State<T> {
  KidPlayback? _playback;
  StreamSubscription<PlayerEvent>? _events;
  String? _youtubeId;
  bool _failed = false;

  /// The open player, if any.
  KidPlayback? get playback => _playback;

  /// Loads [youtubeId], waiting.
  void openPlayer(String youtubeId) {
    _youtubeId = youtubeId;
    final playback = AppScope.of(context).adultPlayer.open(youtubeId);
    _playback = playback;
    _events = playback.events.listen((e) => _on(playback, e));
  }

  Future<void> _on(KidPlayback playback, PlayerEvent event) async {
    final outcome = await followAdultPlayer(
      event,
      playback: playback,
      links: AppScope.of(context).links,
    );
    if (!mounted || playback != _playback) return;
    switch (outcome) {
      case AdultPlayerOutcome.playing:
        return;
      case AdultPlayerOutcome.stopped:
        // Not the video on this screen: it loads again, waiting.
        await closePlayer();
        if (mounted) setState(() => openPlayer(_youtubeId!));
      case AdultPlayerOutcome.failed:
        await closePlayer();
        if (mounted) setState(() => _failed = true);
    }
  }

  /// Lets the player go; nothing it says afterwards counts.
  Future<void> closePlayer() async {
    final playback = _playback;
    final events = _events;
    _playback = null;
    _events = null;
    unawaited(events?.cancel());
    await playback?.close();
  }

  @override
  void dispose() {
    unawaited(closePlayer());
    super.dispose();
  }

  /// The Whole Window Rule: the embed square-edged at 16:9 and the
  /// column's width, nothing of ours over it; failed, the window's box
  /// kept with its square edge drawn in the outline tone and the error
  /// note [failed] centred inside, growing past its height at large text
  /// rather than clip.
  Widget playerWindow({required String failed}) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth;
      final height = width * 9 / 16;
      if (_failed) {
        // The window that did not open: its box kept, its edge drawn.
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: width, minHeight: height),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: context.palette.outline, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Center(child: ErrorNote(failed)),
            ),
          ),
        );
      }
      return SizedBox(width: width, height: height, child: _playback?.view);
    },
  );
}
