import '../auth/auth_api.dart' show PlatformRole;

/// One account as the directory shows it (AccountSheet):
/// the email masked, counts of the family's children and
/// devices, never a child, a device label or a session id.
class AccountSheet {
  const AccountSheet({
    required this.accountId,
    required this.emailMasked,
    required this.emailVerified,
    required this.createdAt,
    required this.providers,
    required this.roles,
    required this.mfaEnrolled,
    this.suspension,
    this.family,
    required this.devices,
    required this.sessions,
    required this.actions,
  });

  factory AccountSheet.fromJson(Map<String, dynamic> j) => AccountSheet(
    accountId: j['account_id'] as String,
    emailMasked: j['email_masked'] as String,
    emailVerified: j['email_verified'] as bool,
    createdAt: DateTime.parse(j['created_at'] as String),
    providers: [for (final p in j['providers'] as List<dynamic>) p as String],
    roles: PlatformRole.parseAll(j['roles']),
    mfaEnrolled: j['mfa_enrolled'] as bool,
    suspension: j['suspension'] == null
        ? null
        : SheetSuspension.fromJson(j['suspension'] as Map<String, dynamic>),
    family: j['family'] == null
        ? null
        : SheetFamily.fromJson(j['family'] as Map<String, dynamic>),
    devices: [
      for (final d in j['devices'] as List<dynamic>)
        SheetDevice.fromJson(d as Map<String, dynamic>),
    ],
    sessions: [
      for (final s in j['sessions'] as List<dynamic>)
        SheetSession.fromJson(s as Map<String, dynamic>),
    ],
    actions: [
      for (final a in j['actions'] as List<dynamic>)
        AuditAction.fromJson(a as Map<String, dynamic>),
    ],
  );

  final String accountId;
  final String emailMasked;
  final bool emailVerified;
  final DateTime createdAt;

  /// `password`, `google`, `apple`, in that order, as held.
  final List<String> providers;
  final Set<PlatformRole> roles;
  final bool mfaEnrolled;

  /// Set while the account is suspended; null
  /// otherwise.
  final SheetSuspension? suspension;

  /// Null without a family.
  final SheetFamily? family;
  final List<SheetDevice> devices;
  final List<SheetSession> sessions;

  /// The latest 20 staff actions about the account, newest first.
  final List<AuditAction> actions;
}

/// The account's role in its family and the family's counts.
class SheetFamily {
  const SheetFamily({
    required this.role,
    required this.minors,
    required this.devices,
  });

  factory SheetFamily.fromJson(Map<String, dynamic> j) => SheetFamily(
    role: j['role'] as String,
    minors: j['minors'] as int,
    devices: j['devices'] as int,
  );

  /// `owner` or `guardian`.
  final String role;
  final int minors;

  /// Devices seen within 180 days.
  final int devices;
}

/// A suspension: since when, and the staff reason, which never reaches
/// the person.
class SheetSuspension {
  const SheetSuspension({required this.since, required this.reason});

  factory SheetSuspension.fromJson(Map<String, dynamic> j) => SheetSuspension(
    since: DateTime.parse(j['since'] as String),
    reason: j['reason'] as String,
  );

  final DateTime since;
  final String reason;
}

/// A family device: no label, no child.
class SheetDevice {
  const SheetDevice({
    required this.id,
    required this.linkedAt,
    required this.lastSeenAt,
  });

  factory SheetDevice.fromJson(Map<String, dynamic> j) => SheetDevice(
    id: j['id'] as String,
    linkedAt: DateTime.parse(j['linked_at'] as String),
    lastSeenAt: DateTime.parse(j['last_seen_at'] as String),
  );

  final String id;
  final DateTime linkedAt;
  final DateTime lastSeenAt;
}

/// A live session: no id, label or token.
class SheetSession {
  const SheetSession({
    required this.client,
    required this.createdAt,
    required this.lastSeenAt,
  });

  factory SheetSession.fromJson(Map<String, dynamic> j) => SheetSession(
    client: j['client'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    lastSeenAt: DateTime.parse(j['last_seen_at'] as String),
  );

  /// `web` or `mobile`.
  final String client;
  final DateTime createdAt;
  final DateTime lastSeenAt;
}

/// A staff action (AuditAction). [actorEmail] is null
/// once the actor is erased; [subjectEmailMasked] for a non-account or
/// erased subject; [reason] once the subject is erased.
class AuditAction {
  const AuditAction({
    required this.id,
    required this.occurredAt,
    required this.event,
    required this.actorId,
    this.actorEmail,
    required this.actorRole,
    this.subjectKind,
    this.subjectId,
    this.subjectEmailMasked,
    this.reason,
    required this.metadata,
  });

  factory AuditAction.fromJson(Map<String, dynamic> j) => AuditAction(
    id: j['id'] as int,
    occurredAt: DateTime.parse(j['occurred_at'] as String),
    event: j['event'] as String,
    actorId: j['actor_id'] as String,
    actorEmail: j['actor_email'] as String?,
    actorRole: j['actor_role'] as String,
    subjectKind: j['subject_kind'] as String?,
    subjectId: j['subject_id'] as String?,
    subjectEmailMasked: j['subject_email_masked'] as String?,
    reason: j['reason'] as String?,
    metadata: {
      for (final e
          in ((j['metadata'] as Map<String, dynamic>?) ?? const {}).entries)
        e.key: '${e.value}',
    },
  );

  final int id;
  final DateTime occurredAt;
  final String event;
  final String actorId;
  final String? actorEmail;
  final String actorRole;
  final String? subjectKind;
  final String? subjectId;
  final String? subjectEmailMasked;
  final String? reason;

  /// Ids and enum values only; empty when the action stored none.
  final Map<String, String> metadata;
}

/// One page of the staff audit log, newest first.
class AuditPage {
  const AuditPage({required this.actions, this.nextOffset});

  factory AuditPage.fromJson(Map<String, dynamic> j) => AuditPage(
    actions: [
      for (final a in j['actions'] as List<dynamic>)
        AuditAction.fromJson(a as Map<String, dynamic>),
    ],
    nextOffset: j['next_offset'] as int?,
  );

  final List<AuditAction> actions;

  /// Null on the last page.
  final int? nextOffset;
}

/// Platform totals; a null count means fewer than [suppressedBelow].
class Metrics {
  const Metrics({
    this.accounts,
    this.families,
    this.minors,
    this.activeDevices,
    this.publishedVideos,
    this.publishedPacks,
    this.reports7d,
    required this.suppressedBelow,
  });

  factory Metrics.fromJson(Map<String, dynamic> j) => Metrics(
    accounts: j['accounts'] as int?,
    families: j['families'] as int?,
    minors: j['minors'] as int?,
    activeDevices: j['active_devices'] as int?,
    publishedVideos: j['published_videos'] as int?,
    publishedPacks: j['published_packs'] as int?,
    reports7d: j['reports_7d'] as int?,
    suppressedBelow: j['suppressed_below'] as int,
  );

  final int? accounts;
  final int? families;
  final int? minors;
  final int? activeDevices;
  final int? publishedVideos;
  final int? publishedPacks;
  final int? reports7d;
  final int suppressedBelow;
}
