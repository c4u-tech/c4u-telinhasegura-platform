import 'package:flutter/foundation.dart';

import 'curation.dart';
import 'pack.dart';

/// A video picked for a pacotinho, as the composer shows it.
@immutable
class PickedVideo {
  const PickedVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.duration,
  });

  factory PickedVideo.of(Video v) => PickedVideo(
    id: v.id,
    title: v.title,
    channelTitle: v.channelTitle,
    duration: v.duration,
  );

  factory PickedVideo.inPack(PackVideo v) => PickedVideo(
    id: v.id,
    title: v.title,
    channelTitle: v.channelTitle,
    duration: v.duration,
  );

  final String id;
  final String title;
  final String channelTitle;
  final Duration duration;

  @override
  bool operator ==(Object other) => other is PickedVideo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The composition a composer holds while its picker is open above it:
/// the videos in order, the cover
/// and the theme. The name lives in the composer's field.
class PackDraft extends ChangeNotifier {
  PackDraft({this.limits = defaultLimits});

  /// The composition rule until the server states its
  /// own: only the longest total is configured there.
  static const defaultLimits = PackLimits(
    minVideos: 3,
    maxVideos: 5,
    maxDuration: Duration.zero,
  );

  /// [PackLimits.maxDuration] is zero while the server has not said.
  PackLimits limits;

  final List<PickedVideo> _videos = [];
  String? _coverId;
  VideoTheme? _theme;
  bool _themeChosen = false;

  List<PickedVideo> get videos => List.unmodifiable(_videos);

  Duration get total => _videos.fold(Duration.zero, (t, v) => t + v.duration);

  /// The cover: the one chosen while it is picked, else the first video.
  String? get coverId =>
      _videos.any((v) => v.id == _coverId) ? _coverId : _videos.firstOrNull?.id;

  VideoTheme? get theme => _theme;

  bool get overLimit =>
      limits.maxDuration > Duration.zero && total > limits.maxDuration;

  /// A recompose starts from the current round.
  void prefill(Pack p) {
    _videos
      ..clear()
      ..addAll(p.videos.map(PickedVideo.inPack));
    _coverId = p.coverVideoId;
    _theme = p.theme == VideoTheme.unknown ? null : p.theme;
    _themeChosen = true;
    notifyListeners();
  }

  /// The picker's "Pronto": [picks] keeps the order the videos already
  /// had and appends new ones in the order chosen; [browsed], the first
  /// theme the curator opened, presets the theme while none was chosen.
  void take(List<PickedVideo> picks, {VideoTheme? browsed}) {
    final kept = _videos.where(picks.contains).toList();
    final added = picks.where((v) => !kept.contains(v));
    _videos
      ..clear()
      ..addAll(kept)
      ..addAll(added);
    if (!_themeChosen && browsed != null) {
      _theme = browsed;
      _themeChosen = true;
    }
    notifyListeners();
  }

  void move(int from, int to) {
    if (to < 0 || to >= _videos.length) return;
    _videos.insert(to, _videos.removeAt(from));
    notifyListeners();
  }

  void remove(int at) {
    _videos.removeAt(at);
    notifyListeners();
  }

  void chooseCover(String id) {
    _coverId = id;
    notifyListeners();
  }

  /// Null for "Sem tema".
  void chooseTheme(VideoTheme? t) {
    _theme = t;
    _themeChosen = true;
    notifyListeners();
  }
}
