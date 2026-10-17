// Package family owns families, their guardians, email invitations, minor
// profiles and the per-minor consent ledger. Every
// write takes the family's row lock first, then re-reads the caller's
// standing, so writes to one family serialize.
package family

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Role string

const (
	Owner    Role = "owner"
	Guardian Role = "guardian"
)

type AgeBand string

const (
	AgeUpTo4 AgeBand = "ate-4"
	Age5To8  AgeBand = "5-8"
	Age9To12 AgeBand = "9-12"
)

// ConsentPolicyVersion names the consent text the app shows before a
// minor is created. The Dart constant kConsentPolicyVersion must equal it.
const ConsentPolicyVersion = "2026-10-17"

// Avatars are the preset avatar keys; the app maps each key to its art.
var Avatars = []string{"fox", "owl", "cat", "dog", "rabbit", "bear", "turtle", "whale", "lion", "panda", "frog", "penguin"}

const (
	maxSeats      = 6 // members, owner included, plus pending invitations
	maxMinors     = 10
	maxNickname   = 20 // runes
	invitationTTL = 7 * 24 * time.Hour
)

var (
	ErrValidation              = errors.New("family: validation failed")
	ErrNotFound                = errors.New("family: not found")
	ErrInvalidToken            = errors.New("family: invalid invitation token")
	ErrEmailUnverified         = errors.New("family: email not verified")
	ErrAlreadyInFamily         = errors.New("family: account already in a family")
	ErrNoFamily                = errors.New("family: account has no family")
	ErrNotOwner                = errors.New("family: owner only")
	ErrOwnerMustTransfer       = errors.New("family: the owner must transfer ownership before leaving")
	ErrLimitReached            = errors.New("family: limit reached")
	ErrPolicyOutdated          = errors.New("family: consent policy version outdated")
	ErrInvitationEmailMismatch = errors.New("family: invitation sent to another email")
	ErrAlreadyMember           = errors.New("family: email belongs to a member")
	ErrInvitationUnavailable   = errors.New("family: invitation unavailable")
	ErrOtherGuardians          = errors.New("family: other guardians remain")
)

// ThrottledError refuses a request over its rate limit.
type ThrottledError struct{ RetryAfter time.Duration }

func (e *ThrottledError) Error() string { return "family: rate limited" }

type Member struct {
	AccountID string
	Email     string
	Role      Role
	JoinedAt  time.Time
}

type Minor struct {
	ID        string
	Nickname  string
	Avatar    string
	AgeBand   AgeBand
	CreatedAt time.Time
	UpdatedAt time.Time
	// ConsentCurrent is true when a guardian has authorized the profile
	// under the current consent text.
	ConsentCurrent bool
}

type Invitation struct {
	ID        string
	Email     string
	ExpiresAt time.Time
}

// Family is one caller's view of their family: Role is the caller's own,
// and Invitations is nil unless the caller is the owner.
type Family struct {
	ID                 string
	Role               Role
	Members            []Member
	Minors             []Minor
	PendingInvitations int
	Invitations        []Invitation
}

// Preview is what an invitee sees before accepting.
type Preview struct {
	InviterEmail string
	InvitedEmail string
	ExpiresAt    time.Time
}

// ReceivedInvitation is a pending invitation as its invitee sees it in
// the app.
type ReceivedInvitation struct {
	ID           string
	InviterEmail string
	ExpiresAt    time.Time
}

type MinorInput struct {
	Nickname string
	Avatar   string
	AgeBand  AgeBand
}

// MinorPatch changes the non-nil fields only.
type MinorPatch struct {
	Nickname *string
	Avatar   *string
	AgeBand  *AgeBand
}

type Deps struct {
	Pool          *pgxpool.Pool
	Mail          mail.Sender
	Audit         audit.Recorder
	Now           func() time.Time
	AppBaseURL    string
	InviteLimiter *ratelimit.Limiter // keyed by family
	TokenLimiter  *ratelimit.Limiter // keyed by account: lookup and accept
	Log           *slog.Logger       // post-commit notice failures
}

type Service struct{ d Deps }

func NewService(d Deps) *Service { return &Service{d: d} }

// now is the clock at the precision Postgres stores, so a returned time
// equals the one a later read gives.
func (s *Service) now() time.Time { return s.d.Now().Truncate(time.Microsecond) }

// notify sends committed-change notices on a best-effort basis: every
// message is attempted, a failure is logged without its address
// and never fails the request, whose change already took effect.
func (s *Service) notify(ctx context.Context, e audit.Event, msgs ...mail.Message) {
	for _, m := range msgs {
		if err := s.d.Mail.Send(ctx, m); err != nil {
			s.d.Log.Error("family: notice not sent", "event", string(e), "err", err)
		}
	}
}
