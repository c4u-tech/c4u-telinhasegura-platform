package staff

// The account directory: an exact-match lookup with
// a reason, a masked sheet, and the readers for the audit log and the
// metrics. staff reaches identity, session, family, parental and
// curation only through the interfaces below; curation is
// counts only, since it imports staff.

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
)

// AccountDirectory is identity as the directory reads it.
type AccountDirectory interface {
	AccountForStaff(ctx context.Context, id string) (identity.StaffAccount, error)
	AccountIDByEmail(ctx context.Context, email string) (string, error)
	Emails(ctx context.Context, ids []string) (map[string]string, error)
	SendPasswordReset(ctx context.Context, accountID string) error
	CountAccounts(ctx context.Context) (int, error)
}

// SessionDirectory is session as the directory reads and ends it.
type SessionDirectory interface {
	List(ctx context.Context, accountID string) ([]session.Session, error)
	RevokeAll(ctx context.Context, accountID, exceptID string) error
}

// FamilyDirectory is family as the directory counts it.
type FamilyDirectory interface {
	Membership(ctx context.Context, accountID string) (family.Membership, bool, error)
	MinorCount(ctx context.Context, familyID string) (int, error)
	CountFamilies(ctx context.Context) (int, error)
	CountMinors(ctx context.Context) (int, error)
}

// DeviceDirectory is parental's devices, without labels.
type DeviceDirectory interface {
	FamilyDevices(ctx context.Context, familyID string) ([]parental.FamilyDevice, error)
	UnlinkInFamily(ctx context.Context, familyID, deviceID string) error
	CountActiveDevices(ctx context.Context) (int, error)
}

// ContentCounter is curation's totals.
type ContentCounter interface {
	CountPublishedVideos(ctx context.Context) (int, error)
	CountPublishedPacks(ctx context.Context) (int, error)
	CountReportsSince(ctx context.Context, since time.Time) (int, error)
}

// AuditReader reads the staff actions (audit.Store implements it).
type AuditReader interface {
	ActionsAbout(ctx context.Context, kind audit.SubjectKind, id string, limit int) ([]audit.Recorded, error)
	StaffActions(ctx context.Context, offset, limit int) ([]audit.Recorded, bool, error)
}

const sheetActions = 20

// AccountSheet is one account as an admin sees it: counts, never a
// child, a device label, a session id or a secret.
type AccountSheet struct {
	AccountID     string
	EmailMasked   string
	EmailVerified bool
	CreatedAt     time.Time
	Providers     []string
	Roles         []Role
	MFAEnrolled   bool
	Suspension    *SheetSuspension // nil unless suspended
	Family        *SheetFamily     // nil without a family
	Devices       []SheetDevice
	Sessions      []SheetSession
	Actions       []AuditEntry
}

type SheetFamily struct {
	Role    family.Role
	Minors  int
	Devices int // active: seen within 180 days
}

// SheetSuspension is a suspended account's start and staff reason. The
// reason never reaches the person.
type SheetSuspension struct {
	Since  time.Time
	Reason string
}

type SheetDevice struct {
	ID         string
	LinkedAt   time.Time
	LastSeenAt time.Time
}

type SheetSession struct {
	Client     session.Client
	CreatedAt  time.Time
	LastSeenAt time.Time
}

// AuditEntry is a staff action as the sheet and the log answer it. An
// empty string is null: ActorEmail once the actor is erased,
// SubjectEmailMasked for a non-account or erased subject.
type AuditEntry struct {
	ID                 int64
	OccurredAt         time.Time
	Event              string
	ActorID            string
	ActorEmail         string
	ActorRole          string
	SubjectKind        string
	SubjectID          string
	SubjectEmailMasked string
	Reason             string
	Metadata           json.RawMessage
}

// LookupInput is exactly one of Email and AccountID, and a reason.
type LookupInput struct {
	Email     *string
	AccountID *string
	Reason    string
}

// Lookup finds one account by exact email or id for adminID and answers
// its sheet. The reason, then the input, are checked first and
// neither refusal is audited or counted; then the per-admin
// limit, before any account is read. A hit and a miss are both
// audited with the reason; a miss without the email.
func (s *Service) Lookup(ctx context.Context, adminID string, in LookupInput) (AccountSheet, error) {
	why, err := CheckReason(in.Reason)
	if err != nil {
		return AccountSheet{}, err
	}
	by, key, err := lookupKey(in)
	if err != nil {
		return AccountSheet{}, err
	}
	if ok, wait := s.d.LookupLimiter.Allow(adminID); !ok {
		return AccountSheet{}, &ThrottledError{RetryAfter: wait}
	}
	id := key
	if by == "email" {
		id, err = s.d.Accounts.AccountIDByEmail(ctx, key)
	}
	var acc identity.StaffAccount
	if err == nil {
		acc, err = s.d.Accounts.AccountForStaff(ctx, id)
	}
	if errors.Is(err, identity.ErrNotFound) {
		s.d.Audit.RecordAction(ctx, audit.Action{Actor: adminID, ActorRole: string(Admin), Event: audit.AccountLookedUp,
			Reason: why, Metadata: map[string]string{"by": by, "match": "none"}})
		return AccountSheet{}, ErrAccountNotFound
	}
	if err != nil {
		return AccountSheet{}, err
	}
	s.recordAbout(ctx, adminID, audit.AccountLookedUp, acc.ID, why, map[string]string{"by": by})
	return s.sheet(ctx, acc)
}

// lookupKey takes exactly one of the email and the id, well formed.
func lookupKey(in LookupInput) (by, key string, err error) {
	switch {
	case (in.Email == nil) == (in.AccountID == nil):
		return "", "", ErrValidation
	case in.Email != nil:
		e := identity.NormalizeEmail(*in.Email)
		if !identity.ValidEmail(e) {
			return "", "", ErrValidation
		}
		return "email", e, nil
	default:
		if !validID(*in.AccountID) {
			return "", "", ErrValidation
		}
		return "id", strings.ToLower(*in.AccountID), nil
	}
}

// recordAbout records adminID's action on the account subjectID.
func (s *Service) recordAbout(ctx context.Context, adminID string, e audit.Event, subjectID, reason string, meta map[string]string) {
	s.d.Audit.RecordAction(ctx, audit.Action{Actor: adminID, ActorRole: string(Admin), Event: e,
		SubjectKind: audit.SubjectAccount, SubjectID: subjectID, Reason: reason, Metadata: meta})
}

// sheet builds the account's sheet; every list is empty, never nil.
func (s *Service) sheet(ctx context.Context, acc identity.StaffAccount) (AccountSheet, error) {
	sh := AccountSheet{AccountID: acc.ID, EmailMasked: MaskEmail(acc.Email), EmailVerified: acc.EmailVerified,
		CreatedAt: acc.CreatedAt, Providers: acc.Providers, Devices: []SheetDevice{}, Sessions: []SheetSession{}}
	if acc.Status == identity.StatusSuspended {
		sh.Suspension = &SheetSuspension{Since: acc.SuspendedAt, Reason: acc.SuspensionReason}
	}
	var err error
	if sh.Roles, err = s.Roles(ctx, acc.ID); err != nil {
		return AccountSheet{}, err
	}
	if sh.MFAEnrolled, err = s.HasConfirmedFactor(ctx, acc.ID); err != nil {
		return AccountSheet{}, err
	}
	m, ok, err := s.d.Families.Membership(ctx, acc.ID)
	if err != nil {
		return AccountSheet{}, err
	}
	if ok {
		devices, err := s.d.Devices.FamilyDevices(ctx, m.FamilyID)
		if err != nil {
			return AccountSheet{}, err
		}
		minors, err := s.d.Families.MinorCount(ctx, m.FamilyID)
		if err != nil {
			return AccountSheet{}, err
		}
		sh.Family = &SheetFamily{Role: m.Role, Minors: minors, Devices: len(devices)}
		for _, d := range devices {
			sh.Devices = append(sh.Devices, SheetDevice{ID: d.ID, LinkedAt: d.LinkedAt, LastSeenAt: d.LastSeenAt})
		}
	}
	live, err := s.d.Sessions.List(ctx, acc.ID)
	if err != nil {
		return AccountSheet{}, err
	}
	for _, x := range live {
		sh.Sessions = append(sh.Sessions, SheetSession{Client: x.Client, CreatedAt: x.CreatedAt.UTC(), LastSeenAt: x.LastSeenAt.UTC()})
	}
	rows, err := s.d.AuditLog.ActionsAbout(ctx, audit.SubjectAccount, acc.ID, sheetActions)
	if err != nil {
		return AccountSheet{}, err
	}
	if sh.Actions, err = s.entries(ctx, rows); err != nil {
		return AccountSheet{}, err
	}
	return sh, nil
}

// entries resolves each row's actor email and, for an account subject,
// its masked email, from the accounts that still exist.
func (s *Service) entries(ctx context.Context, rows []audit.Recorded) ([]AuditEntry, error) {
	ids := make([]string, 0, 2*len(rows))
	for _, r := range rows {
		ids = append(ids, r.ActorID)
		if r.SubjectKind == audit.SubjectAccount {
			ids = append(ids, r.SubjectID)
		}
	}
	emails, err := s.d.Accounts.Emails(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := make([]AuditEntry, 0, len(rows))
	for _, r := range rows {
		e := AuditEntry{ID: r.ID, OccurredAt: r.OccurredAt, Event: string(r.Event), ActorID: r.ActorID, ActorEmail: emails[r.ActorID],
			ActorRole: r.ActorRole, SubjectKind: string(r.SubjectKind), SubjectID: r.SubjectID, Reason: r.Reason, Metadata: r.Metadata}
		if email, ok := emails[r.SubjectID]; ok && r.SubjectKind == audit.SubjectAccount {
			e.SubjectEmailMasked = MaskEmail(email)
		}
		out = append(out, e)
	}
	return out, nil
}
