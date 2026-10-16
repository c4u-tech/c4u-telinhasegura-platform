import '../screentime/kid_time.dart';
import 'curation.dart' show VideoTheme;

/// What a child's shelf shows of a video: no provenance, no channel, no
/// band.
class KidVideo {
  const KidVideo({
    required this.id,
    required this.title,
    required this.duration,
  });

  factory KidVideo.fromJson(Map<String, dynamic> j) => KidVideo(
    id: j['id'] as String,
    title: j['title'] as String,
    duration: Duration(seconds: j['duration_seconds'] as int),
  );

  final String id;

  /// For screen readers only: a pre-reader finds a video by its picture.
  final String title;
  final Duration duration;
}

/// One theme's videos, at most the server's shelf size.
class KidShelf {
  const KidShelf({required this.theme, required this.videos});

  final VideoTheme theme;
  final List<KidVideo> videos;
}

/// A pacotinho as a child's row shows it: its playable videos in order
/// and a cover among them; no provenance.
class KidPack {
  const KidPack({
    required this.id,
    required this.title,
    required this.coverVideoId,
    required this.videos,
  });

  factory KidPack.fromJson(Map<String, dynamic> j) => KidPack(
    id: j['id'] as String,
    title: j['title'] as String,
    coverVideoId: j['cover_video_id'] as String,
    videos: [
      for (final v in j['videos'] as List<dynamic>)
        KidVideo.fromJson(v as Map<String, dynamic>),
    ],
  );

  final String id;

  /// For screen readers only, like a video's.
  final String title;

  /// The video whose thumbnail stands for the pacotinho; the child may
  /// fetch it.
  final String coverVideoId;
  final List<KidVideo> videos;
}

/// The child's shelves in the server's theme order.
class KidCatalog {
  const KidCatalog({
    required this.shelves,
    this.packs = const [],
    this.time = KidTime.unknown,
  });

  /// A theme this app does not know has no picture to be found by, so
  /// its shelf is left out rather than shown unlabelled.
  factory KidCatalog.fromJson(Map<String, dynamic> j) => KidCatalog(
    shelves: [
      for (final s
          in (j['themes'] as List<dynamic>).cast<Map<String, dynamic>>())
        if (VideoTheme.parse(s['theme']) case final theme
            when theme != VideoTheme.unknown)
          KidShelf(
            theme: theme,
            videos: [
              for (final v in s['videos'] as List<dynamic>)
                KidVideo.fromJson(v as Map<String, dynamic>),
            ],
          ),
    ],
    packs: [
      for (final p in (j['packs'] as List<dynamic>?) ?? const [])
        KidPack.fromJson(p as Map<String, dynamic>),
    ],
    time: KidTime.fromJson(j['time'] as Map<String, dynamic>?),
  );

  final List<KidShelf> shelves;

  /// The day's pacotinhos, in the server's order; an older server sends
  /// none.
  final List<KidPack> packs;

  /// The day's time: the child home sleeps while it is not `ok`.
  final KidTime time;
}
