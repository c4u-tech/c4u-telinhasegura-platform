// Package parental owns the family PIN, kid mode on a shared device and
// child-device linking. A child principal is a session
// locked to a child or a linked device; it reaches only its own profile,
// and no guardian route accepts one.
package parental

import (
	"context"
	"crypto/rand"
	"errors"
	"io"
	"log/slog"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	failuresBeforeBlock = 5
	codeTTL             = 10 * time.Minute
	maxLiveCodes        = 5
	maxDevices          = 10
	deviceIdle          = 180 * 24 * time.Hour
)

var (
	ErrValidation      = errors.New("parental: validation failed")
	ErrWeakPIN         = errors.New("parental: PIN too easy to guess")
	ErrNoFamily        = errors.New("parental: account has no family")
	ErrNotFound        = errors.New("parental: not found")
	ErrPINNotSet       = errors.New("parental: the family has no PIN")
	ErrInvalidPIN      = errors.New("parental: wrong PIN")
	ErrInvalidCode     = errors.New("parental: invalid link code")
	ErrLimitReached    = errors.New("parental: limit reached")
	ErrProfileGone     = errors.New("parental: the child's profile was deleted")
	ErrUnauthenticated = errors.New("parental: unknown or expired device")
	ErrNotChild        = errors.New("parental: not a child principal")
)

// ThrottledError refuses a PIN check during a cooldown, or a request over
// its rate limit.
type ThrottledError struct{ RetryAfter time.Duration }

func (e *ThrottledError) Error() string { return "parental: rate limited" }

// Profile is a child as kid mode shows it: no dates, no consent.
type Profile struct {
	ID       string
	Nickname string
	Avatar   string
	AgeBand  string
}

// Device is a linked child device as the guardian area lists it; the
// token never leaves Redeem.
type Device struct {
	ID         string
	Label      string
	MinorID    string
	LinkedAt   time.Time
	LastSeenAt time.Time
}

type LinkCode struct {
	Code      string // XXXX-XXXX
	MinorID   string
	ExpiresAt time.Time
}

// Redeemed is what a child's device keeps after redeeming a code.
type Redeemed struct {
	Token   string
	Profile Profile
}

// Principal is a child principal: a session locked to a child, or a
// linked device. Exactly one of SessionID and DeviceID is set.
type Principal struct {
	FamilyID  string // "" once a locked session's guardian left the family
	MinorID   string // "" once a locked session's child was deleted
	SessionID string
	AccountID string // the locked session's guardian
	DeviceID  string
}

type Deps struct {
	Pool        *pgxpool.Pool
	Mail        mail.Sender
	Audit       audit.Recorder
	Now         func() time.Time
	Hash        identity.HashParams // the password parameters
	AppBaseURL  string
	CodeLimiter *ratelimit.Limiter // keyed by account
	Rand        io.Reader          // link codes; nil is crypto/rand
	Log         *slog.Logger       // post-commit notice failures
}

type Service struct{ d Deps }

func NewService(d Deps) *Service { return &Service{d: d} }

// now is the clock at the precision Postgres stores, so a returned time
// equals the one a later read gives.
func (s *Service) now() time.Time { return s.d.Now().Truncate(time.Microsecond) }

func (s *Service) rand() io.Reader {
	if s.d.Rand != nil {
		return s.d.Rand
	}
	return rand.Reader
}

// notify sends committed-change notices on a best-effort basis: a failure
// is logged without its address and never fails the request.
func (s *Service) notify(ctx context.Context, e audit.Event, msgs ...mail.Message) {
	for _, m := range msgs {
		if err := s.d.Mail.Send(ctx, m); err != nil {
			s.d.Log.Error("parental: notice not sent", "event", string(e), "err", err)
		}
	}
}
