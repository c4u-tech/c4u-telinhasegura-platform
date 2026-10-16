import '../auth/api_error.dart';
import 'curation.dart';

/// A pacotinho's place in curation.
/// [unknown] only ever comes from [parse].
enum PackState {
  pending,
  approved,
  held,
  removed,
  unknown;

  static PackState parse(Object? wire) => values.firstWhere(
    (s) => s != unknown && s.name == wire,
    orElse: () => unknown,
  );
}

/// The first rule a composition breaks (`pack_invalid`), in the order the
/// server checks them.
enum PackInvalidReason {
  count('count'),
  repeat('repeat'),
  notApproved('not_approved'),
  duration('duration'),
  cover('cover'),
  title('title'),
  unknown('');

  const PackInvalidReason(this.wire);

  final String wire;

  static PackInvalidReason parse(Object? wire) => values.firstWhere(
    (r) => r != unknown && r.wire == wire,
    orElse: () => unknown,
  );
}

extension PackInvalid on ApiError {
  /// The broken rule; null unless [code] is `pack_invalid`.
  PackInvalidReason? get packInvalid => code == 'pack_invalid'
      ? PackInvalidReason.parse(details['reason'])
      : null;
}

/// A composition's video as curators see it, whatever its state now.
class PackVideo {
  const PackVideo({
    required this.id,
    required this.title,
    required this.duration,
    required this.state,
    this.channelTitle = '',
  });

  factory PackVideo.fromJson(Map<String, dynamic> j) => PackVideo(
    id: j['id'] as String,
    title: j['title'] as String,
    duration: Duration(seconds: j['duration_seconds'] as int),
    state: VideoState.parse(j['state']),
    channelTitle: j['channel_title'] as String? ?? '',
  );

  final String id;
  final String title;
  final Duration duration;

  /// A video that is not approved is skipped for every child.
  final VideoState state;

  /// Empty from a server that predates channel titles.
  final String channelTitle;
}

/// One review of a pacotinho's round: the displayed role, never the
/// account.
class PackReview {
  const PackReview({
    required this.displayRole,
    required this.decision,
    required this.reviewedAt,
    this.reason,
  });

  factory PackReview.fromJson(Map<String, dynamic> j) => PackReview(
    displayRole: DisplayRole.parse(j['display_role']),
    decision: ReviewDecision.parse(j['decision']),
    reviewedAt: DateTime.parse(j['reviewed_at'] as String),
    reason: j['reason'] as String?,
  );

  final DisplayRole displayRole;
  final ReviewDecision decision;
  final DateTime reviewedAt;

  /// Only a rejection has one.
  final String? reason;
}

/// A pacotinho as curators see it: the current round's composition and
/// reviews, and the published round's provenance.
class Pack {
  const Pack({
    required this.id,
    required this.state,
    required this.round,
    required this.title,
    required this.coverVideoId,
    required this.composerRole,
    required this.videos,
    required this.total,
    required this.reviews,
    required this.reviewable,
    this.theme,
    this.provenance,
  });

  factory Pack.fromJson(Map<String, dynamic> j) => Pack(
    id: j['id'] as String,
    state: PackState.parse(j['state']),
    round: j['round'] as int,
    title: j['title'] as String,
    coverVideoId: j['cover_video_id'] as String,
    composerRole: DisplayRole.parse(j['composer_role']),
    videos: [
      for (final v in j['videos'] as List<dynamic>)
        PackVideo.fromJson(v as Map<String, dynamic>),
    ],
    total: Duration(seconds: j['total_seconds'] as int),
    reviews: [
      for (final r in j['reviews'] as List<dynamic>)
        PackReview.fromJson(r as Map<String, dynamic>),
    ],
    reviewable: j['reviewable'] as bool,
    theme: j['theme'] == null ? null : VideoTheme.parse(j['theme']),
    provenance: j['provenance'] == null
        ? null
        : Provenance.fromJson(j['provenance'] as Map<String, dynamic>),
  );

  final String id;
  final PackState state;

  /// The round under review; an approved pack keeps serving its
  /// published round meanwhile.
  final int round;
  final String title;
  final String coverVideoId;
  final DisplayRole composerRole;

  /// The current round's videos, in order.
  final List<PackVideo> videos;
  final Duration total;

  /// The current round's reviews.
  final List<PackReview> reviews;

  /// The caller may review: a round awaits review and they neither
  /// composed nor reviewed it.
  final bool reviewable;

  /// Curation surfaces only.
  final VideoTheme? theme;

  /// Null until the pack is first published.
  final Provenance? provenance;
}

class PackPage {
  const PackPage({required this.packs, required this.hasMore});

  factory PackPage.fromJson(Map<String, dynamic> j) => PackPage(
    packs: [
      for (final p in j['packs'] as List<dynamic>)
        Pack.fromJson(p as Map<String, dynamic>),
    ],
    hasMore: j['has_more'] as bool,
  );

  /// Those awaiting review first, the oldest round first; then the rest.
  final List<Pack> packs;

  /// Another page waits at the offset plus this page's length.
  final bool hasMore;
}

/// The composition rules the server enforces: the
/// composer shows the picks against them.
class PackLimits {
  const PackLimits({
    required this.minVideos,
    required this.maxVideos,
    required this.maxDuration,
  });

  factory PackLimits.fromJson(Map<String, dynamic> j) => PackLimits(
    minVideos: j['min_videos'] as int,
    maxVideos: j['max_videos'] as int,
    maxDuration: Duration(seconds: j['max_seconds'] as int),
  );

  final int minVideos;
  final int maxVideos;
  final Duration maxDuration;
}
