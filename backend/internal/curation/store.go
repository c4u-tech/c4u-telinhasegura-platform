package curation

import (
	"context"
	"regexp"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/jackc/pgx/v5"
)

// scanner is a single row: a pgx.Row or a pgx.CollectableRow.
type scanner interface {
	Scan(dest ...any) error
}

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

// validID keeps a malformed ID away from a ::uuid cast (a 500); the caller
// answers it like an unknown ID.
func validID(v string) bool { return uuidRE.MatchString(v) }

// querier is satisfied by both the pool and a transaction.
type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// Video is a catalogue entry as curation reads it.
type Video struct {
	ID              string
	YouTubeID       string
	Title           string
	ChannelID       string
	ChannelTitle    string
	DurationSeconds int
	State           State
	Round           int            // the round under review (0005_curation.sql)
	PublishedRound  *int           // the round that last published it; nil until then
	Theme           string         // "" until a publication
	MinAgeBand      family.AgeBand // "" until a publication
	LastReviewedAt  *time.Time
	ReviewDueAt     *time.Time
	CreatedAt       time.Time
}

// videoCols reads the videos table aliased v, in scanVideo's order.
const videoCols = `v.id::text, v.youtube_id, v.title, v.channel_id, v.channel_title, v.duration_seconds, v.state,
	v.round, v.published_round, coalesce(v.theme, ''), coalesce(v.min_age_band, ''), v.last_reviewed_at, v.review_due_at, v.created_at`

// scanVideo scans videoCols, then any extra columns after them.
func scanVideo(row scanner, extra ...any) (Video, error) {
	var v Video
	var state, band string
	err := row.Scan(append([]any{&v.ID, &v.YouTubeID, &v.Title, &v.ChannelID, &v.ChannelTitle, &v.DurationSeconds,
		&state, &v.Round, &v.PublishedRound, &v.Theme, &band, &v.LastReviewedAt, &v.ReviewDueAt, &v.CreatedAt}, extra...)...)
	v.State, v.MinAgeBand = State(state), family.AgeBand(band)
	v.LastReviewedAt, v.ReviewDueAt, v.CreatedAt = utcp(v.LastReviewedAt), utcp(v.ReviewDueAt), v.CreatedAt.UTC()
	return v, err
}

// utcp is t in UTC, keeping nil.
func utcp(t *time.Time) *time.Time {
	if t == nil {
		return nil
	}
	u := t.UTC()
	return &u
}
