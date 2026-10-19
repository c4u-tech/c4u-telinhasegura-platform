// Package audit records security-relevant events: ids and event names
// only, never an email, token or password.
package audit

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Event string

const (
	SignedUp                    Event = "signed_up"
	EmailVerified               Event = "email_verified"
	SignInSucceeded             Event = "sign_in_succeeded"
	SignInFailed                Event = "sign_in_failed"
	SignedOut                   Event = "signed_out"
	SessionRevoked              Event = "session_revoked"
	RefreshReused               Event = "refresh_reused"
	PasswordChanged             Event = "password_changed"
	PasswordReset               Event = "password_reset"
	EmailChanged                Event = "email_changed"
	ProviderSignedUp            Event = "provider_signed_up"
	ProviderSignInSucceeded     Event = "provider_sign_in_succeeded"
	IdentityLinked              Event = "identity_linked"
	ProviderPasswordCleared     Event = "provider_password_cleared"
	FamilyCreated               Event = "family_created"
	InvitationSent              Event = "invitation_sent"
	InvitationRevoked           Event = "invitation_revoked"
	InvitationAccepted          Event = "invitation_accepted"
	GuardianRemoved             Event = "guardian_removed"
	GuardianLeft                Event = "guardian_left"
	OwnershipTransferred        Event = "ownership_transferred"
	MinorCreated                Event = "minor_created"
	MinorConsentGranted         Event = "minor_consent_granted"
	MinorUpdated                Event = "minor_updated"
	MinorDeleted                Event = "minor_deleted"
	FamilyDeleted               Event = "family_deleted"
	PINSet                      Event = "pin_set"
	PINBlocked                  Event = "pin_failed_blocked"
	KidModeEntered              Event = "kid_mode_entered"
	KidModeExited               Event = "kid_mode_exited"
	LinkCodeCreated             Event = "link_code_created"
	DeviceLinked                Event = "device_linked"
	DeviceProfileChanged        Event = "device_profile_changed"
	DeviceUnlinked              Event = "device_unlinked"
	DataExported                Event = "data_exported"
	AccountDeleted              Event = "account_deleted"
	AppleRevocationFailed       Event = "apple_revocation_failed"
	AdminGranted                Event = "admin_granted"
	AdminRevoked                Event = "admin_revoked"
	CuratorAppointed            Event = "curator_appointed"
	CuratorUpdated              Event = "curator_updated"
	CuratorRemoved              Event = "curator_removed"
	ModeratorAppointed          Event = "moderator_appointed"
	ModeratorRemoved            Event = "moderator_removed"
	VideoPublished              Event = "video_published"
	VideoHeld                   Event = "video_held"
	VideoRemoved                Event = "video_removed"
	VideoReopened               Event = "video_reopened"
	VideoHidden                 Event = "video_hidden"
	VideoUnhidden               Event = "video_unhidden"
	VideoReported               Event = "video_reported"
	PackPublished               Event = "pack_published"
	PackHeld                    Event = "pack_held"
	PackRemoved                 Event = "pack_removed"
	ScreenTimeRulesChanged      Event = "screen_time_rules_changed"
	ScreenTimeExtended          Event = "screen_time_extended"
	MFAEnrolled                 Event = "mfa_enrolled"
	MFAChallengeSucceeded       Event = "mfa_challenge_succeeded"
	MFAChallengeFailed          Event = "mfa_challenge_failed"
	MFABlocked                  Event = "mfa_blocked"
	MFARecoveryCodeUsed         Event = "mfa_recovery_code_used"
	MFARecoveryCodesRegenerated Event = "mfa_recovery_codes_regenerated"
	MFAReset                    Event = "mfa_reset"
	AccountLookedUp             Event = "account_looked_up"
	AccountSessionsRevoked      Event = "account_sessions_revoked"
	AccountDeviceUnlinked       Event = "account_device_unlinked"
	AccountPasswordResetSent    Event = "account_password_reset_sent"
	AccountSuspended            Event = "account_suspended"
	AccountReinstated           Event = "account_reinstated"
)

// SubjectKind is what an audit action acted on.
type SubjectKind string

const (
	SubjectAccount SubjectKind = "account"
	SubjectVideo   SubjectKind = "video"
	SubjectPack    SubjectKind = "pack"
)

// Action is a staff write: who did it under which platform role, to
// what, and why. Metadata holds ids and enum values only, never an email,
// a token or a child's data.
type Action struct {
	Actor       string // an account ID; "" for none
	ActorRole   string // "admin", "curator" or "moderator"
	Event       Event
	SubjectKind SubjectKind
	SubjectID   string
	Reason      string
	Metadata    map[string]string
}

// Recorder never fails the request it audits; a write error is logged.
type Recorder interface {
	Record(ctx context.Context, accountID string, e Event)
	RecordAction(ctx context.Context, a Action)
}

type Store struct {
	Pool *pgxpool.Pool
	Now  func() time.Time
	Log  *slog.Logger
}

func (s Store) Record(ctx context.Context, accountID string, e Event) {
	var id any
	if accountID != "" {
		id = accountID
	}
	// A client disconnect must not drop the audit row of what already happened.
	if _, err := s.Pool.Exec(context.WithoutCancel(ctx), `INSERT INTO audit_events (account_id, event, occurred_at) VALUES ($1, $2, $3)`, id, string(e), s.Now()); err != nil {
		s.Log.Error("audit: record failed", "event", string(e), "err", err)
	}
}

// retentionYears is how long a security event is kept: long enough to
// answer for an incident or a dispute about an account, and no longer.
const retentionYears = 5

// Sweep deletes the events older than five years. It is idempotent, so
// every replica may run it.
func (s Store) Sweep(ctx context.Context) error {
	_, err := s.Pool.Exec(ctx, `DELETE FROM audit_events WHERE occurred_at < $1`, s.Now().AddDate(-retentionYears, 0, 0))
	return err
}

// insertAction is the statement of RecordAction and RecordActionTx. An
// empty field is stored as NULL.
const insertAction = `INSERT INTO audit_events
	(account_id, event, occurred_at, actor_role, subject_kind, subject_id, reason, metadata)
	VALUES (nullif($1, '')::uuid, $2, $3, nullif($4, ''), nullif($5, ''), nullif($6, '')::uuid, nullif($7, ''), $8::jsonb)`

func actionArgs(a Action, at time.Time) []any {
	var meta []byte
	if len(a.Metadata) > 0 {
		meta, _ = json.Marshal(a.Metadata) // a map of strings always encodes
	}
	return []any{a.Actor, string(a.Event), at, a.ActorRole, string(a.SubjectKind), a.SubjectID, a.Reason, meta}
}

// RecordAction writes an action. An empty field is stored as NULL; the
// reason never reaches the log.
func (s Store) RecordAction(ctx context.Context, a Action) {
	// A client disconnect must not drop the audit row of what already happened.
	if _, err := s.Pool.Exec(context.WithoutCancel(ctx), insertAction, actionArgs(a, s.Now())...); err != nil {
		s.Log.Error("audit: record failed", "event", string(a.Event), "err", err)
	}
}

// RecordActionTx writes the action inside the caller's transaction, at
// at, so the action and its record commit or roll back together.
// Unlike RecordAction it answers its
// error: the caller must not commit a write it could not audit.
func RecordActionTx(ctx context.Context, tx pgx.Tx, at time.Time, a Action) error {
	_, err := tx.Exec(ctx, insertAction, actionArgs(a, at)...)
	return err
}
