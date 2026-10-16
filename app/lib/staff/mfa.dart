/// The caller's own factor and elevation (MfaStatus).
/// Never carries the secret or a recovery code.
class MfaStatus {
  const MfaStatus({
    required this.enrolled,
    this.enrolledAt,
    required this.recoveryCodesLeft,
    this.elevatedUntil,
    required this.mfaRequired,
  });

  factory MfaStatus.fromJson(Map<String, dynamic> j) => MfaStatus(
    enrolled: j['enrolled'] as bool,
    enrolledAt: _time(j['enrolled_at']),
    recoveryCodesLeft: j['recovery_codes_left'] as int,
    elevatedUntil: _time(j['elevated_until']),
    mfaRequired: j['required'] as bool,
  );

  final bool enrolled;
  final DateTime? enrolledAt;
  final int recoveryCodesLeft;

  /// Set only while this session is elevated.
  final DateTime? elevatedUntil;

  /// True when the server enforces MFA and the account is an admin or a
  /// moderator.
  final bool mfaRequired;
}

/// A pending factor's secret, shown once: the manual key and the link a
/// QR code carries.
class MfaEnrollment {
  const MfaEnrollment({required this.secret, required this.otpauthUri});

  factory MfaEnrollment.fromJson(Map<String, dynamic> j) => MfaEnrollment(
    secret: j['secret'] as String,
    otpauthUri: j['otpauth_uri'] as String,
  );

  final String secret;
  final String otpauthUri;
}

/// A passed challenge.
class Elevation {
  const Elevation({
    required this.elevatedUntil,
    required this.recoveryCodesLeft,
  });

  factory Elevation.fromJson(Map<String, dynamic> j) => Elevation(
    elevatedUntil: DateTime.parse(j['elevated_until'] as String),
    recoveryCodesLeft: j['recovery_codes_left'] as int,
  );

  final DateTime elevatedUntil;
  final int recoveryCodesLeft;
}

/// Ten recovery codes, shown once. A confirm also elevates the session
/// and says until when; a regeneration does not.
class RecoveryCodes {
  const RecoveryCodes({required this.codes, this.elevatedUntil});

  factory RecoveryCodes.fromJson(Map<String, dynamic> j) => RecoveryCodes(
    codes: [for (final c in j['recovery_codes'] as List<dynamic>) c as String],
    elevatedUntil: _time(j['elevated_until']),
  );

  final List<String> codes;
  final DateTime? elevatedUntil;
}

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);
