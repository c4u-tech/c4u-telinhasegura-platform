import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/link_opener.dart';

/// A [LinkOpener] that records what it was asked to open.
class FakeLinks implements LinkOpener {
  final opened = <Uri>[];

  /// What [open] answers: false as for a link no app takes.
  bool opens = true;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return opens;
  }
}

/// A [KidPlayer] with no WebView: it records what the screen asks of it
/// and lets a test say what the player does.
class FakeKidPlayer implements KidPlayer {
  final opened = <FakePlayback>[];

  /// The player opened last, if any.
  FakePlayback? get current => opened.isEmpty ? null : opened.last;

  @override
  FakePlayback open(String youtubeId) {
    final playback = FakePlayback(youtubeId);
    opened.add(playback);
    return playback;
  }
}

class FakePlayback implements KidPlayback {
  FakePlayback(this.youtubeId);

  final String youtubeId;

  /// What the screen asked, in order: `play`, `pause`, `close`.
  final calls = <String>[];
  final _events = StreamController<PlayerEvent>.broadcast();

  bool get closed => calls.contains('close');

  static const viewKey = Key('fake-player');

  /// Says what the player did.
  void emit(PlayerEvent event) => _events.add(event);

  @override
  Widget get view => const ColoredBox(
    key: viewKey,
    color: Color(0xFF000000),
    child: SizedBox.expand(),
  );

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> close() async {
    calls.add('close');
    await _events.close();
  }
}
