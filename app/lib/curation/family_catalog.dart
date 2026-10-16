import '../family/family.dart' show AgeBand;
import 'curation.dart';

/// A video as a guardian browses what one child can see, with who
/// reviewed it. Provenance never reaches a
/// child screen.
class FamilyVideo {
  const FamilyVideo({
    required this.id,
    required this.youtubeId,
    required this.title,
    required this.channelTitle,
    required this.duration,
    required this.theme,
    required this.minAgeBand,
    required this.hidden,
    this.provenance,
  });

  factory FamilyVideo.fromJson(Map<String, dynamic> j) => FamilyVideo(
    id: j['id'] as String,
    youtubeId: j['youtube_id'] as String,
    title: j['title'] as String,
    channelTitle: j['channel_title'] as String,
    duration: Duration(seconds: j['duration_seconds'] as int),
    theme: VideoTheme.parse(j['theme']),
    minAgeBand: AgeBand.parse(j['min_age_band']),
    hidden: j['hidden'] as bool,
    provenance: j['provenance'] == null
        ? null
        : Provenance.fromJson(j['provenance'] as Map<String, dynamic>),
  );

  final String id;

  /// What the Guardian Window plays.
  final String youtubeId;
  final String title;
  final String channelTitle;
  final Duration duration;
  final VideoTheme theme;
  final AgeBand minAgeBand;

  /// Hidden for this child by a guardian; unhiding brings it back.
  final bool hidden;
  final Provenance? provenance;
}

/// A video of a pacotinho as a guardian sees it: [hidden] when it is
/// skipped for this child.
class FamilyPackVideo {
  const FamilyPackVideo({
    required this.id,
    required this.title,
    required this.duration,
    required this.hidden,
  });

  factory FamilyPackVideo.fromJson(Map<String, dynamic> j) => FamilyPackVideo(
    id: j['id'] as String,
    title: j['title'] as String,
    duration: Duration(seconds: j['duration_seconds'] as int),
    hidden: j['hidden'] as bool,
  );

  final String id;
  final String title;
  final Duration duration;
  final bool hidden;
}

/// A pacotinho the child gets today, with who built and reviewed it, as
/// displayed roles.
class FamilyPack {
  const FamilyPack({
    required this.id,
    required this.title,
    required this.coverVideoId,
    required this.composerRole,
    required this.videos,
    required this.provenance,
  });

  factory FamilyPack.fromJson(Map<String, dynamic> j) => FamilyPack(
    id: j['id'] as String,
    title: j['title'] as String,
    coverVideoId: j['cover_video_id'] as String,
    composerRole: DisplayRole.parse(j['composer_role']),
    videos: [
      for (final v in j['videos'] as List<dynamic>)
        FamilyPackVideo.fromJson(v as Map<String, dynamic>),
    ],
    provenance: Provenance.fromJson(j['provenance'] as Map<String, dynamic>),
  );

  final String id;
  final String title;
  final String coverVideoId;
  final DisplayRole composerRole;

  /// Every approved video, in order.
  final List<FamilyPackVideo> videos;
  final Provenance provenance;
}

class FamilyCatalogPage {
  const FamilyCatalogPage({
    required this.videos,
    required this.hasMore,
    this.packs = const [],
  });

  factory FamilyCatalogPage.fromJson(Map<String, dynamic> j) =>
      FamilyCatalogPage(
        videos: [
          for (final v in j['videos'] as List<dynamic>)
            FamilyVideo.fromJson(v as Map<String, dynamic>),
        ],
        hasMore: j['has_more'] as bool,
        packs: [
          for (final p in (j['packs'] as List<dynamic>?) ?? const [])
            FamilyPack.fromJson(p as Map<String, dynamic>),
        ],
      );

  final List<FamilyVideo> videos;

  /// Another page waits at the offset plus this page's length.
  final bool hasMore;

  /// The pacotinhos the child gets today; only the first page carries
  /// them, and an older server sends none.
  final List<FamilyPack> packs;
}
