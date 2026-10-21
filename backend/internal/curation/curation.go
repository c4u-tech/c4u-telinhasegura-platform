// Package curation owns the community curation of YouTube videos:
// suggestion, review rounds, publication, revisits, the admin's and the
// moderators' decisions, and pacotinhos. The platform roles belong to staff: curation
// only reads platform_roles, inside its own transactions and in the
// suggestion-limit check (isCurator in suggest.go): the read seam.
// Like parental and privacy, it runs its own SQL, including the account
// reads it needs.
package curation

import (
	"errors"
	"log/slog"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5/pgxpool"
)

// State is a video's place in curation.
type State string

const (
	Pending  State = "pending"
	Approved State = "approved"
	Held     State = "held"
	Removed  State = "removed"
)

// The reasons a suggested video is refused, as the API sends them.
const (
	RefusedNotFound      = "not_found"
	RefusedNotForKids    = "not_for_kids"
	RefusedNotEmbeddable = "not_embeddable"
	RefusedLive          = "live"
	RefusedTooLong       = "too_long"
	RefusedShorts        = "shorts"
	RefusedRemoved       = "removed"
)

// Why a video is held.
const (
	HeldByReview      = "review"
	HeldByReports     = "reports"
	HeldByUnavailable = "unavailable"
	HeldByDoubt       = "doubt" // a curator was unsure; a moderator decides
	HeldByAudit       = "audit" // a moderator's audit disagreed with the approval
)

// The rules a composition can break, in the order they are checked.
const (
	PackInvalidCount       = "count"
	PackInvalidRepeat      = "repeat"
	PackInvalidNotApproved = "not_approved"
	PackInvalidDuration    = "duration"
	PackInvalidCover       = "cover"
	PackInvalidTitle       = "title"
)

var (
	ErrValidation        = errors.New("curation: validation failed")
	ErrNotFound          = errors.New("curation: not found")
	ErrNotCurator        = staff.ErrNotCurator // one sentinel, one code: staff's
	ErrInvalidLink       = errors.New("curation: not a YouTube video link")
	ErrVideoNotFound     = errors.New("curation: no such YouTube video")
	ErrSourceUnavailable = errors.New("curation: the video source is unavailable")
	ErrNotReviewable     = errors.New("curation: the video is not awaiting a review")
	ErrAlreadyReviewed   = errors.New("curation: already reviewed in this round")
	ErrOwnSuggestion     = errors.New("curation: a curator cannot review their own suggestion")
	ErrOwnComposition    = errors.New("curation: a curator cannot review their own composition")
	ErrStateConflict     = errors.New("curation: the video's state does not allow this")
	ErrAlreadyAudited    = errors.New("curation: the round was already audited")
	ErrOwnReview         = errors.New("curation: the round holds a review of the same account")
	ErrVideoNotAllowed   = errors.New("curation: the child may not see this video")
	ErrProfileGone       = errors.New("curation: the child or its family is gone")

	ErrChecklistOutdated   = errors.New("curation: the checklist version is not the current one")
	ErrChecklistRefuses    = errors.New("curation: an answer refuses the video")
	ErrChecklistBand       = errors.New("curation: the pace answered rules out the youngest band")
	ErrDeclarationRequired = errors.New("curation: the curator has not accepted the current curator terms")
	ErrDeclarationOutdated = errors.New("curation: the curator terms version is not the current one")
	ErrConflictOfInterest  = errors.New("curation: the curator has a tie to the channel")

	ErrThumbnailUnavailable = errors.New("curation: the thumbnail could not be fetched")
)

// RefusedError refuses a suggested video, with its reason.
type RefusedError struct{ Reason string }

func (e *RefusedError) Error() string { return "curation: video refused: " + e.Reason }

// ThrottledError refuses a guardian's suggestion over the daily limit.
type ThrottledError struct{ RetryAfter time.Duration }

func (e *ThrottledError) Error() string { return "curation: rate limited" }

// PackInvalidError refuses a composition with the first rule it breaks.
type PackInvalidError struct{ Reason string }

func (e *PackInvalidError) Error() string { return "curation: pack invalid: " + e.Reason }

type Deps struct {
	Pool              *pgxpool.Pool
	Audit             audit.Recorder
	Now               func() time.Time
	Source            VideoSource        // nil while YOUTUBE_API_KEY is empty: a YouTube call answers 503
	Thumbs            ThumbSource        // YouTube's image host, no key
	SuggestLimiter    *ratelimit.Limiter // 10 suggestion calls per guardian per 24 h, keyed by account
	ReportLimiter     *ratelimit.Limiter // 20 report calls per account per 24 h
	ReportThreshold   int                // distinct families' reports that hold a video
	CheckVideoLimiter *ratelimit.Limiter // one YouTube re-check per video per hour
	CheckChildLimiter *ratelimit.Limiter // 10 unavailable checks per child per hour
	MinApprovals      int                // approvals that publish a round
	MaxDuration       time.Duration      // a longer video is refused
	RevisitAfter      time.Duration      // from a publication to its revisit
	ShelfSize         int                // videos per theme on a child's shelf
	PackMaxDuration   time.Duration      // the longest total of a pack's videos
	PackRowSize       int                // packs in a child's row
	Log               *slog.Logger       // source failures, never the key or the link
}

type Service struct{ d Deps }

func NewService(d Deps) *Service { return &Service{d: d} }

// now is the clock at the precision Postgres stores, in UTC.
func (s *Service) now() time.Time { return s.d.Now().Truncate(time.Microsecond).UTC() }
