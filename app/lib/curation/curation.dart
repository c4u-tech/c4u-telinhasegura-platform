import '../auth/api_error.dart';
import '../family/family.dart' show AgeBand;

/// A video's place in curation.
enum VideoState {
  pending,
  approved,
  held,
  removed,
  unknown;

  static VideoState parse(Object? wire) => values.firstWhere(
    (s) => s != unknown && s.name == wire,
    orElse: () => unknown,
  );
}

/// The fixed theme set, in display order. Named `VideoTheme` so a screen
/// can import it beside Flutter's `Theme`.
/// [unknown] only ever comes from [parse]; never send it.
enum VideoTheme {
  bichos,
  musica,
  historias,
  aprender,
  brincar,
  natureza,
  unknown;

  String get wire => name;

  static VideoTheme parse(Object? wire) => values.firstWhere(
    (t) => t != unknown && t.name == wire,
    orElse: () => unknown,
  );
}

/// How a curator's reviews are shown; the screens own the PT-BR labels.
/// [unknown] only ever comes from [parse]; never send it.
enum DisplayRole {
  maePai('mae-pai'),
  cuidador('cuidador'),
  pedagogo('pedagogo', professional: true),
  psicologo('psicologo', professional: true),
  educador('educador', professional: true),
  pediatra('pediatra', professional: true),
  unknown('');

  const DisplayRole(this.wire, {this.professional = false});

  final String wire;

  /// Appointing or switching to it needs `verifiedProfessional`.
  final bool professional;

  static DisplayRole parse(Object? wire) => values.firstWhere(
    (r) => r != unknown && r.wire == wire,
    orElse: () => unknown,
  );
}

enum ReviewDecision {
  approve,
  reject,
  unknown;

  static ReviewDecision parse(Object? wire) => values.firstWhere(
    (d) => d != unknown && d.name == wire,
    orElse: () => unknown,
  );
}

/// Why the server refused a suggested video (`video_refused`).
enum RefusalReason {
  notFound('not_found'),
  notForKids('not_for_kids'),
  notEmbeddable('not_embeddable'),
  live('live'),
  tooLong('too_long'),
  shorts('shorts'),
  removed('removed'),
  unknown('');

  const RefusalReason(this.wire);

  final String wire;

  static RefusalReason parse(Object? wire) => values.firstWhere(
    (r) => r != unknown && r.wire == wire,
    orElse: () => unknown,
  );
}

/// Why a video is held. An older server
/// sends none, which reads as [review].
enum HeldReason {
  review,
  reports,
  unavailable,
  unknown;

  static HeldReason parse(Object? wire) => wire == null
      ? review
      : values.firstWhere(
          (r) => r != unknown && r.name == wire,
          orElse: () => unknown,
        );
}

/// Why a family reports a video. [unknown] only
/// ever comes from [parse]; never send it.
enum ReportReason {
  inadequado,
  assustador,
  publicidade,
  outro,
  unknown;

  String get wire => name;

  static ReportReason parse(Object? wire) => values.firstWhere(
    (r) => r != unknown && r.name == wire,
    orElse: () => unknown,
  );
}

/// A held video's reports since its latest reopen: counts by reason and
/// the notes, never who reported.
class ReportSummary {
  const ReportSummary({this.byReason = const {}, this.notes = const []});

  /// Unknown reasons all parse to [ReportReason.unknown]: their counts
  /// add up.
  factory ReportSummary.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ReportSummary();
    final by = <ReportReason, int>{};
    for (final e in (j['by_reason'] as Map<String, dynamic>).entries) {
      by.update(
        ReportReason.parse(e.key),
        (n) => n + (e.value as int),
        ifAbsent: () => e.value as int,
      );
    }
    return ReportSummary(
      byReason: by,
      notes: (j['notes'] as List<dynamic>).cast<String>(),
    );
  }

  final Map<ReportReason, int> byReason;
  final List<String> notes;
}

extension VideoRefusal on ApiError {
  /// The refusal's reason; null unless [code] is `video_refused`.
  RefusalReason? get refusal =>
      code == 'video_refused' ? RefusalReason.parse(details['reason']) : null;
}

DateTime? _time(Object? wire) =>
    wire == null ? null : DateTime.parse(wire as String);

class Video {
  const Video({
    required this.id,
    required this.youtubeId,
    required this.title,
    required this.channelId,
    required this.channelTitle,
    required this.duration,
    required this.state,
    required this.round,
    required this.createdAt,
    this.theme,
    this.minAgeBand,
    this.lastReviewedAt,
    this.reviewDueAt,
    this.revisit = false,
  });

  factory Video.fromJson(Map<String, dynamic> j) => Video(
    id: j['id'] as String,
    youtubeId: j['youtube_id'] as String,
    title: j['title'] as String,
    channelId: j['channel_id'] as String,
    channelTitle: j['channel_title'] as String,
    duration: Duration(seconds: j['duration_seconds'] as int),
    state: VideoState.parse(j['state']),
    round: j['round'] as int,
    createdAt: DateTime.parse(j['created_at'] as String),
    theme: j['theme'] == null ? null : VideoTheme.parse(j['theme']),
    minAgeBand: j['min_age_band'] == null
        ? null
        : AgeBand.parse(j['min_age_band']),
    lastReviewedAt: _time(j['last_reviewed_at']),
    reviewDueAt: _time(j['review_due_at']),
    revisit: j['revisit'] as bool? ?? false,
  );

  final String id;
  final String youtubeId;
  final String title;
  final String channelId;
  final String channelTitle;
  final Duration duration;
  final VideoState state;
  final int round;
  final DateTime createdAt;

  /// Null until the video is first published.
  final VideoTheme? theme;
  final AgeBand? minAgeBand;
  final DateTime? lastReviewedAt;
  final DateTime? reviewDueAt;

  /// Only queue items carry it: an approved video whose revisit fell due.
  final bool revisit;
}

/// One review, as curators see it: the displayed role, never the account.
class Review {
  const Review({
    required this.displayRole,
    required this.decision,
    required this.reviewedAt,
    this.theme,
    this.minAgeBand,
    this.reason,
  });

  factory Review.fromJson(Map<String, dynamic> j) => Review(
    displayRole: DisplayRole.parse(j['display_role']),
    decision: ReviewDecision.parse(j['decision']),
    reviewedAt: DateTime.parse(j['reviewed_at'] as String),
    theme: j['theme'] == null ? null : VideoTheme.parse(j['theme']),
    minAgeBand: j['min_age_band'] == null
        ? null
        : AgeBand.parse(j['min_age_band']),
    reason: j['reason'] as String?,
  );

  final DisplayRole displayRole;
  final ReviewDecision decision;
  final DateTime reviewedAt;
  final VideoTheme? theme;
  final AgeBand? minAgeBand;
  final String? reason;
}

/// The published round's approvals by displayed role.
class Provenance {
  const Provenance({required this.approvals, required this.lastReviewedAt});

  factory Provenance.fromJson(Map<String, dynamic> j) => Provenance(
    approvals: _sum(j['approvals'] as Map<String, dynamic>),
    lastReviewedAt: DateTime.parse(j['last_reviewed_at'] as String),
  );

  /// Unknown roles all parse to [DisplayRole.unknown]: their counts add up.
  static Map<DisplayRole, int> _sum(Map<String, dynamic> wire) {
    final out = <DisplayRole, int>{};
    for (final e in wire.entries) {
      out.update(
        DisplayRole.parse(e.key),
        (n) => n + (e.value as int),
        ifAbsent: () => e.value as int,
      );
    }
    return out;
  }

  final Map<DisplayRole, int> approvals;
  final DateTime lastReviewedAt;
}

class VideoDetail {
  const VideoDetail({
    required this.video,
    required this.reviews,
    this.provenance,
  });

  factory VideoDetail.fromJson(Map<String, dynamic> j) => VideoDetail(
    video: Video.fromJson(j['video'] as Map<String, dynamic>),
    reviews: [
      for (final r in j['reviews'] as List<dynamic>)
        Review.fromJson(r as Map<String, dynamic>),
    ],
    provenance: j['provenance'] == null
        ? null
        : Provenance.fromJson(j['provenance'] as Map<String, dynamic>),
  );

  final Video video;

  /// The current round's reviews.
  final List<Review> reviews;

  /// Null only when the video was never published, whatever its state.
  final Provenance? provenance;
}

class QueuePage {
  const QueuePage({required this.videos, this.nextOffset});

  factory QueuePage.fromJson(Map<String, dynamic> j) => QueuePage(
    videos: [
      for (final v in j['videos'] as List<dynamic>)
        Video.fromJson(v as Map<String, dynamic>),
    ],
    nextOffset: j['next_offset'] as int?,
  );

  final List<Video> videos;

  /// The offset of the next page; null on the last one.
  final int? nextOffset;
}

class HeldVideo {
  const HeldVideo({
    required this.video,
    required this.rejections,
    this.heldReason = HeldReason.review,
    this.reports = const ReportSummary(),
  });

  factory HeldVideo.fromJson(Map<String, dynamic> j) => HeldVideo(
    video: Video.fromJson(j['video'] as Map<String, dynamic>),
    rejections: [
      for (final r in j['rejections'] as List<dynamic>)
        Review.fromJson(r as Map<String, dynamic>),
    ],
    heldReason: HeldReason.parse(j['held_reason']),
    reports: ReportSummary.fromJson(j['reports'] as Map<String, dynamic>?),
  );

  final Video video;
  final List<Review> rejections;
  final HeldReason heldReason;
  final ReportSummary reports;
}

/// A video the guardian suggested, with where it stands.
class Suggestion {
  const Suggestion({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.state,
    required this.suggestedAt,
  });

  factory Suggestion.fromJson(Map<String, dynamic> j) => Suggestion(
    videoId: j['video_id'] as String,
    title: j['title'] as String,
    channelTitle: j['channel_title'] as String,
    state: VideoState.parse(j['state']),
    suggestedAt: DateTime.parse(j['suggested_at'] as String),
  );

  final String videoId;
  final String title;
  final String channelTitle;
  final VideoState state;
  final DateTime suggestedAt;
}
