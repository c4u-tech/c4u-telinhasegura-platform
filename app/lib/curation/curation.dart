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
  doubt,
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
  doubt,
  audit,
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

/// An answer to one question of the curation checklist. For a question
/// asked in the positive ("Tem começo, meio e fim claros?") [ok] is yes
/// and [appears] is no. [unknown] only ever comes from [parse].
enum ChecklistAnswer {
  ok,
  appears,
  doubt,
  unknown;

  String get wire => name;

  static ChecklistAnswer parse(Object? wire) => values.firstWhere(
    (a) => a != unknown && a.name == wire,
    orElse: () => unknown,
  );
}

/// What an [ChecklistAnswer.appears] does to a review: it refuses the
/// video, sends it to the team, rules out the youngest band, is a reason
/// the criteria never accept, or keeps the curator from reviewing it.
enum ChecklistRule {
  refuses('refuses'),
  doubt('doubt'),
  band('band'),
  invalidReason('invalid_reason'),
  conflict('conflict'),
  unknown('');

  const ChecklistRule(this.wire);

  final String wire;

  static ChecklistRule parse(Object? wire) => values.firstWhere(
    (r) => r != unknown && r.wire == wire,
    orElse: () => unknown,
  );
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    required this.rule,
    this.positive = false,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
    id: j['id'] as String,
    text: j['text'] as String,
    rule: ChecklistRule.parse(j['rule']),
    positive: j['positive'] as bool? ?? false,
  );

  final String id;
  final String text;
  final ChecklistRule rule;

  /// Asked in the positive: marking it means "no".
  final bool positive;
}

class ChecklistGroup {
  const ChecklistGroup({
    required this.id,
    required this.title,
    required this.items,
  });

  factory ChecklistGroup.fromJson(Map<String, dynamic> j) => ChecklistGroup(
    id: j['id'] as String,
    title: j['title'] as String,
    items: [
      for (final i in j['items'] as List<dynamic>)
        ChecklistItem.fromJson(i as Map<String, dynamic>),
    ],
  );

  final String id;
  final String title;
  final List<ChecklistItem> items;
}

/// The list every review answers, as the server holds it: the app renders
/// it and sends its [version] back with the answers.
class Checklist {
  const Checklist({required this.version, required this.groups});

  factory Checklist.fromJson(Map<String, dynamic> j) => Checklist(
    version: j['version'] as String,
    groups: [
      for (final g in j['groups'] as List<dynamic>)
        ChecklistGroup.fromJson(g as Map<String, dynamic>),
    ],
  );

  final String version;
  final List<ChecklistGroup> groups;

  Iterable<ChecklistItem> get items => groups.expand((g) => g.items);

  /// The question [id] names; null for one this list does not have.
  ChecklistItem? item(String id) => items.where((i) => i.id == id).firstOrNull;
}

/// The curator terms in force, and whether this curator accepted them.
class CuratorTerms {
  const CuratorTerms({
    required this.version,
    required this.text,
    required this.accepted,
  });

  factory CuratorTerms.fromJson(Map<String, dynamic> j) => CuratorTerms(
    version: j['version'] as String,
    text: j['text'] as String,
    accepted: j['accepted'] as bool,
  );

  final String version;
  final String text;
  final bool accepted;
}

/// A published round offered to an audit, with the approvals that
/// published it by displayed role.
class AuditCandidate {
  const AuditCandidate({
    required this.video,
    required this.round,
    required this.approvals,
  });

  factory AuditCandidate.fromJson(Map<String, dynamic> j) => AuditCandidate(
    video: Video.fromJson(j['video'] as Map<String, dynamic>),
    round: j['round'] as int,
    approvals: [
      for (final r in j['approvals'] as List<dynamic>)
        Review.fromJson(r as Map<String, dynamic>),
    ],
  );

  final Video video;
  final int round;
  final List<Review> approvals;
}

/// A moderator's verdict on an approval they audited.
enum AuditVerdict {
  agree,
  disagree,
  unknown;

  static AuditVerdict parse(Object? wire) => values.firstWhere(
    (v) => v != unknown && v.name == wire,
    orElse: () => unknown,
  );
}

/// The audit that held a video: the verdict and its reason, never who
/// audited.
class HeldAudit {
  const HeldAudit({
    required this.verdict,
    required this.auditedAt,
    this.reason,
  });

  factory HeldAudit.fromJson(Map<String, dynamic> j) => HeldAudit(
    verdict: AuditVerdict.parse(j['verdict']),
    reason: j['reason'] as String?,
    auditedAt: DateTime.parse(j['audited_at'] as String),
  );

  final AuditVerdict verdict;
  final String? reason;
  final DateTime auditedAt;
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
    this.checklistVersion,
    this.answers,
    this.failedItems,
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
    checklistVersion: j['checklist_version'] as String?,
    answers: switch (j['answers']) {
      final Map<String, dynamic> m => {
        for (final e in m.entries) e.key: ChecklistAnswer.parse(e.value),
      },
      _ => null,
    },
    failedItems: (j['failed_items'] as List<dynamic>?)?.cast<String>(),
  );

  final DisplayRole displayRole;
  final ReviewDecision decision;
  final DateTime reviewedAt;
  final VideoTheme? theme;
  final AgeBand? minAgeBand;
  final String? reason;

  /// Null for a review written before the checklist.
  final String? checklistVersion;

  /// An approval's or a doubt's answers, by question.
  final Map<String, ChecklistAnswer>? answers;

  /// A rejection's questions.
  final List<String>? failedItems;
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
    this.doubts = const [],
    this.heldReason = HeldReason.review,
    this.reports = const ReportSummary(),
    this.audit,
  });

  factory HeldVideo.fromJson(Map<String, dynamic> j) => HeldVideo(
    video: Video.fromJson(j['video'] as Map<String, dynamic>),
    rejections: [
      for (final r in j['rejections'] as List<dynamic>)
        Review.fromJson(r as Map<String, dynamic>),
    ],
    doubts: [
      for (final r in j['doubts'] as List<dynamic>? ?? const [])
        Review.fromJson(r as Map<String, dynamic>),
    ],
    heldReason: HeldReason.parse(j['held_reason']),
    reports: ReportSummary.fromJson(j['reports'] as Map<String, dynamic>?),
    audit: j['audit'] == null
        ? null
        : HeldAudit.fromJson(j['audit'] as Map<String, dynamic>),
  );

  final Video video;
  final List<Review> rejections;

  /// The held round's curator doubts, with the answers and the note.
  final List<Review> doubts;
  final HeldReason heldReason;
  final ReportSummary reports;

  /// Only for [HeldReason.audit]: the audit that held the video.
  final HeldAudit? audit;
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
