// Package privacy answers a guardian's LGPD art. 18 rights over their
// account: a JSON export of what the platform holds
// about them and their family, and the account's immediate erasure. It
// reads and deletes across the other modules' tables.
package privacy

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Format names the export document's version.
const Format = "telinhasegura.export/1"

// ErrOwnerMustTransfer refuses an owner's deletion: the family would be
// left without an owner.
var ErrOwnerMustTransfer = errors.New("privacy: the owner must transfer ownership or delete the family first")

// ErrAccountGone means the account row was already deleted, as by a
// concurrent second deletion.
var ErrAccountGone = errors.New("privacy: account already deleted")

// The Apple step of a deletion (App Store 5.1.1(v)).
var (
	ErrAppleReauthRequired       = errors.New("privacy: an Apple-linked account needs a fresh Apple authorization to be deleted")
	ErrAppleIdentityMismatch     = errors.New("privacy: the Apple authorization is not this account's")
	ErrAppleAuthorizationInvalid = errors.New("privacy: Apple rejected the authorization code")
)

// AppleCredential is a fresh Sign in with Apple answer: its identity
// token, which names the Apple ID and the client, and its single-use
// authorization code.
type AppleCredential struct {
	IdentityToken     string
	AuthorizationCode string
}

// AppleRevoker exchanges an authorization code and revokes its token
// (appleid.Client).
type AppleRevoker interface {
	Revoke(ctx context.Context, clientID, code string) error
}

// ThrottledError refuses an export over its rate limit.
type ThrottledError struct{ RetryAfter time.Duration }

func (e *ThrottledError) Error() string { return "privacy: rate limited" }

type Deps struct {
	Pool          *pgxpool.Pool
	Mail          mail.Sender
	Audit         audit.Recorder
	Now           func() time.Time
	ExportLimiter *ratelimit.Limiter // keyed by account
	Log           *slog.Logger       // post-commit notice failures
	IDTokens      idtoken.Verifier   // verifies the Apple identity token of a deletion
	Apple         AppleRevoker       // nil: Apple is off, and nothing can be revoked
}

type Service struct{ d Deps }

func NewService(d Deps) *Service { return &Service{d: d} }

// now is the clock at the precision Postgres stores, in UTC.
func (s *Service) now() time.Time { return s.d.Now().Truncate(time.Microsecond).UTC() }
