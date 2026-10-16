// Package screentime owns how long and when a child may watch: per-child
// rules, the family's time zone, plays counted by beats across devices,
// extensions, usage and retention.
// Like curation, it runs its own SQL, including the minors and family
// reads it needs.
package screentime

import (
	"context"
	"errors"
	"regexp"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// State is a child's day state (Rules of counting).
type State string

const (
	OK            State = "ok"
	TimeUp        State = "time_up"
	OutsideWindow State = "outside_window"
)

// The reasons that go with a state other than OK.
const (
	ReasonDaily  = "daily"
	ReasonWindow = "window"
)

// Time is a child's day state now. Remaining is what can be watched now;
// it informs, the app never cuts a video.
type Time struct {
	State     State
	Reason    string // "" when OK
	Remaining time.Duration
}

// Child is a child principal as screentime needs it (parental.Principal).
// DeviceID is "" for a session locked to the child.
type Child struct {
	FamilyID string
	MinorID  string
	DeviceID string
}

const (
	MaxDailyMinutes = 240
	DefaultZone     = "America/Sao_Paulo"

	creditCap     = 45 * time.Second // per beat interval
	closeAfter    = 45 * time.Second // a play with no beat this long is closed
	overrun       = 60 * time.Second // past the video's length, nothing more is credited
	playRetention = 30 * 24 * time.Hour
	dayRetention  = 90 * 24 * time.Hour
)

var (
	ErrValidation  = errors.New("screentime: validation failed")
	ErrNotFound    = errors.New("screentime: not found")
	ErrProfileGone = errors.New("screentime: the child or its family is gone")
	ErrPlayClosed  = errors.New("screentime: the play is closed")
	ErrOverCap     = errors.New("screentime: the day would go over 240 minutes")
)

// TimeUpError refuses a play for time, with its reason.
type TimeUpError struct{ Reason string }

func (e *TimeUpError) Error() string { return "screentime: time up: " + e.Reason }

// ThrottledError refuses a beat over the per-child limit.
type ThrottledError struct{ RetryAfter time.Duration }

func (e *ThrottledError) Error() string { return "screentime: rate limited" }

type Deps struct {
	Pool        *pgxpool.Pool
	Audit       audit.Recorder
	Now         func() time.Time
	BeatLimiter *ratelimit.Limiter // 20 beats per child per minute, keyed by minor
	PlayLimiter *ratelimit.Limiter // 30 play opens per child per minute, keyed by minor
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

var uuidRE = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// validID keeps a malformed ID away from a ::uuid cast (a 500).
func validID(v string) bool { return uuidRE.MatchString(v) }

// querier is satisfied by both the pool and a transaction.
type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}
