package curation

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// PackVideo is a composition's video as curators see it, whatever its
// state now.
type PackVideo struct {
	ID              string
	Title           string
	ChannelTitle    string
	DurationSeconds int
	State           State
}

// PackReview is one review of a pack's round: the displayed role at
// review time, never the account.
type PackReview struct {
	DisplayRole DisplayRole
	Decision    Decision
	Reason      string // a rejection's; "" on an approval
	ReviewedAt  time.Time
}

// Pack is a pack as curators see it: the current round's composition and
// reviews, and the published round's provenance.
type Pack struct {
	ID           string
	State        State
	Round        int    // the round under review
	Theme        string // "" for none; curation surfaces only
	Title        string
	CoverVideoID string
	ComposerRole DisplayRole
	Videos       []PackVideo // in position order
	TotalSeconds int
	Reviews      []PackReview // the current round's, in review order
	// Reviewable is for the caller: the current round awaits review and
	// they neither composed nor reviewed it.
	Reviewable bool
	Provenance *Provenance // nil until the pack is first published
}

// PackDetail reads a pack, in one snapshot, for the curator curatorID. A
// malformed or unknown ID is ErrNotFound.
func (s *Service) PackDetail(ctx context.Context, curatorID, id string) (Pack, error) {
	if !validID(id) {
		return Pack{}, ErrNotFound
	}
	tx, err := s.d.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return Pack{}, err
	}
	defer tx.Rollback(ctx)
	p, err := packOf(ctx, tx, curatorID, id)
	if err != nil {
		return Pack{}, err
	}
	return p, tx.Commit(ctx)
}

// packOf reads one pack for curatorID. A round awaits review while its
// outcome is open and the pack is not removed. An erased
// composer (NULL) is no one, so never the caller.
func packOf(ctx context.Context, q querier, curatorID, id string) (Pack, error) {
	p := Pack{ID: id}
	var state, role, outcome string
	var composer *string
	var published *int
	var last *time.Time
	err := q.QueryRow(ctx, `SELECT p.state, p.round, coalesce(p.theme, ''), p.published_round, p.last_reviewed_at,
			r.title, r.cover_video_id::text, r.composer_role, r.composer_id::text, r.outcome
		FROM packs p JOIN pack_rounds r ON r.pack_id = p.id AND r.round = p.round WHERE p.id = $1::uuid`, id).
		Scan(&state, &p.Round, &p.Theme, &published, &last, &p.Title, &p.CoverVideoID, &role, &composer, &outcome)
	if errors.Is(err, pgx.ErrNoRows) {
		return Pack{}, ErrNotFound
	}
	if err != nil {
		return Pack{}, err
	}
	p.State, p.ComposerRole = State(state), DisplayRole(role)
	rows, err := q.Query(ctx, `SELECT v.id::text, v.title, v.channel_title, v.duration_seconds, v.state FROM pack_items i
		JOIN videos v ON v.id = i.video_id WHERE i.pack_id = $1::uuid AND i.round = $2 ORDER BY i.position`, id, p.Round)
	if err != nil {
		return Pack{}, err
	}
	if p.Videos, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (PackVideo, error) {
		var v PackVideo
		var st string
		err := r.Scan(&v.ID, &v.Title, &v.ChannelTitle, &v.DurationSeconds, &st)
		v.State = State(st)
		return v, err
	}); err != nil {
		return Pack{}, err
	}
	for _, v := range p.Videos {
		p.TotalSeconds += v.DurationSeconds
	}
	if p.Reviews, err = packReviewsOf(ctx, q, id, p.Round); err != nil {
		return Pack{}, err
	}
	var reviewed bool
	if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pack_reviews WHERE pack_id = $1::uuid AND round = $2 AND curator_id = $3::uuid)`,
		id, p.Round, curatorID).Scan(&reviewed); err != nil {
		return Pack{}, err
	}
	own := composer != nil && *composer == curatorID
	p.Reviewable = outcome == "open" && p.State != Removed && !own && !reviewed
	if published != nil {
		if p.Provenance, err = roundProvenance(ctx, q, packLedger, id, *published, last); err != nil {
			return Pack{}, err
		}
	}
	return p, nil
}

// packReviewsOf lists a pack round's reviews in review order.
func packReviewsOf(ctx context.Context, q querier, packID string, round int) ([]PackReview, error) {
	rows, err := q.Query(ctx, `SELECT display_role, decision, coalesce(reason, ''), reviewed_at FROM pack_reviews
		WHERE pack_id = $1::uuid AND round = $2 ORDER BY reviewed_at, id`, packID, round)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (PackReview, error) {
		var x PackReview
		var role, dec string
		err := r.Scan(&role, &dec, &x.Reason, &x.ReviewedAt)
		x.DisplayRole, x.Decision, x.ReviewedAt = DisplayRole(role), Decision(dec), x.ReviewedAt.UTC()
		return x, err
	})
}

const packPage = 50 // packs per list page

// PackQueue lists the packs that are not removed, 50 a page. Those whose
// current round awaits review come first, the oldest round first. The
// rest follow, the latest update first. Each item is the full detail for
// curatorID, with Reviewable. more reports a further page at
// offset + 50.
func (s *Service) PackQueue(ctx context.Context, curatorID string, offset int) ([]Pack, bool, error) {
	if offset < 0 {
		return nil, false, ErrValidation
	}
	tx, err := s.d.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)
	rows, err := tx.Query(ctx, `SELECT p.id::text FROM packs p JOIN pack_rounds r ON r.pack_id = p.id AND r.round = p.round
		WHERE p.state <> 'removed'
		ORDER BY r.outcome = 'open' DESC, CASE WHEN r.outcome = 'open' THEN r.composed_at END, p.updated_at DESC, p.id
		LIMIT $1 OFFSET $2`, packPage+1, offset)
	if err != nil {
		return nil, false, err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, false, err
	}
	more := len(ids) > packPage
	if more {
		ids = ids[:packPage]
	}
	out := make([]Pack, 0, len(ids))
	for _, id := range ids {
		p, err := packOf(ctx, tx, curatorID, id)
		if err != nil {
			return nil, false, err
		}
		out = append(out, p)
	}
	return out, more, tx.Commit(ctx)
}
