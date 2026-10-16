// Package staff owns the platform roles and every write to
// platform_roles: the server command's admin grants and the admin's team.
// curation keeps
// read-only reads of platform_roles inside its own transactions (its race
// guard) and in the suggestion-limit check (isCurator in suggest.go)
// (the read seam). staff never imports curation.
package staff

import (
	"context"
	"errors"
	"log/slog"
	"regexp"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Role is a platform role, independent of any family role.
type Role string

const (
	Admin     Role = "admin"
	Curator   Role = "curator"
	Moderator Role = "moderator"
)

var (
	ErrValidation      = errors.New("staff: validation failed")
	ErrNotFound        = errors.New("staff: not found")
	ErrNotCurator      = errors.New("staff: the account is not a curator")
	ErrNotAdmin        = errors.New("staff: the account is not an admin")
	ErrNotModerator    = errors.New("staff: the account is neither a moderator nor an admin")
	ErrAccountNotFound = errors.New("staff: no account with that email")
	ErrEmailUnverified = errors.New("staff: the account's email is not verified")
	ErrAlreadyHasRole  = errors.New("staff: the account already holds the role")
	ErrReasonRequired  = errors.New("staff: a reason of 3 to 200 characters is required")
	ErrSelfAppointment = errors.New("staff: an admin cannot appoint themself")
	ErrAdminCLIOnly    = errors.New("staff: only the server command grants or revokes admin")
	ErrSelfAction      = errors.New("staff: a support action cannot target the caller's own account")
	ErrDeviceNotFound  = errors.New("staff: the device is not in the account's family")

	ErrSubjectIsAdmin   = errors.New("staff: an admin cannot be suspended")
	ErrAlreadySuspended = errors.New("staff: the account is already suspended")
	ErrNotSuspended     = errors.New("staff: the account is not suspended")
	ErrAccountSuspended = errors.New("staff: the account is suspended")
)

type Deps struct {
	Pool   *pgxpool.Pool
	Audit  audit.Recorder
	Now    func() time.Time
	MFAKey []byte // seals TOTP secrets (STAFF_MFA_KEY); nil: MFA is unavailable

	// The account directory, each module through its
	// own service API. Nil where only the server command
	// builds the service.
	Accounts      AccountDirectory
	Sessions      SessionDirectory
	Families      FamilyDirectory
	Devices       DeviceDirectory
	Content       ContentCounter
	AuditLog      AuditReader
	LookupLimiter *ratelimit.Limiter // 30 lookups per admin per hour, hits and misses
	ResetLimiter  *ratelimit.Limiter // 3 reset emails per subject per hour

	// The suspension notices, sent after
	// the commit; a failed send is logged without the address. Nil where
	// only the server command builds the service.
	Mail mail.Sender
	Log  *slog.Logger
}

type Service struct{ d Deps }

func NewService(d Deps) *Service { return &Service{d: d} }

// now is the clock at the precision Postgres stores, in UTC.
func (s *Service) now() time.Time { return s.d.Now().Truncate(time.Microsecond).UTC() }

func (s *Service) inTx(ctx context.Context, fn func(tx pgx.Tx) error) error {
	tx, err := s.d.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// scanner is a single row: a pgx.Row or a pgx.CollectableRow.
type scanner interface {
	Scan(dest ...any) error
}

var uuidRE = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// validID keeps a malformed ID away from a ::uuid cast (a 500); the
// caller answers it like an unknown ID.
func validID(v string) bool { return uuidRE.MatchString(v) }
