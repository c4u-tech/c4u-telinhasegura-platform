package curation

import (
	"context"
	"encoding/json"
	"errors"
	"maps"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

const (
	queuePage = 50  // videos per queue page
	maxReason = 500 // runes in a rejection's or a doubt's note
)

type Decision string

const (
	Approve Decision = "approve"
	Reject  Decision = "reject"
	Doubt   Decision = "doubt" // stored, never sent: an approval with a doubt becomes one
)

// ReviewInput is an approval with a theme, a band and every answer of the
// list, or a rejection with the questions it failed. Note is the
// curator's own words: a rejection's, or a doubt's.
type ReviewInput struct {
	Decision         Decision
	Theme            string
	MinAgeBand       family.AgeBand
	ChecklistVersion string
	Answers          map[string]Answer // an approval's, every question
	FailedItems      []string          // a rejection's
	Note             string
}

// Review is one review as curators see it: the displayed role at review
// time, never the account.
type Review struct {
	DisplayRole      DisplayRole
	Decision         Decision
	Theme            string
	MinAgeBand       family.AgeBand
	Reason           string
	ChecklistVersion string            // "" for a review written before the list
	Answers          map[string]Answer // an approval's or a doubt's; nil otherwise
	FailedItems      []string          // a rejection's; nil otherwise
	ReviewedAt       time.Time
}

type QueueItem struct {
	Video   Video
	Revisit bool // an approved video whose revisit fell due
}

// Provenance is the approvals, by displayed role, of the last round that
// published the video, whatever its state now. The guardian catalogue serves it.
type Provenance struct {
	Approvals      map[DisplayRole]int
	LastReviewedAt time.Time
}

type VideoDetail struct {
	Video      Video
	Reviews    []Review    // the current round's, in review order
	Provenance *Provenance // nil until the video is first published
}

// Queue lists, oldest first, the videos curatorID may review: pending
// ones and approved ones whose revisit fell due, less those they
// suggested or already reviewed in the current round. more
// reports a further page at offset + 50.
func (s *Service) Queue(ctx context.Context, curatorID string, offset int) ([]QueueItem, bool, error) {
	if offset < 0 {
		return nil, false, ErrValidation
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT `+videoCols+`, v.state = 'approved' FROM videos v
		WHERE (v.state = 'pending' OR v.state = 'approved' AND v.review_due_at <= $2)
		AND NOT EXISTS (SELECT 1 FROM video_suggestions s WHERE s.video_id = v.id AND s.account_id = $1::uuid)
		AND NOT EXISTS (SELECT 1 FROM video_reviews r WHERE r.video_id = v.id AND r.round = v.round AND r.curator_id = $1::uuid)
		ORDER BY CASE WHEN v.state = 'approved' THEN v.review_due_at ELSE v.updated_at END, v.id
		LIMIT $3 OFFSET $4`, curatorID, s.now(), queuePage+1, offset)
	if err != nil {
		return nil, false, err
	}
	items, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (QueueItem, error) {
		var q QueueItem
		var err error
		q.Video, err = scanVideo(r, &q.Revisit)
		return q, err
	})
	if err != nil {
		return nil, false, err
	}
	if len(items) > queuePage {
		return items[:queuePage], true, nil
	}
	return items, false, nil
}

// Review stores a curator's review and applies its effect in the same
// transaction. The video row lock comes first, so the reviews
// of one video run one at a time: the approval count sees every earlier
// review, and two last approvals publish once.
func (s *Service) Review(ctx context.Context, curatorID, videoID string, in ReviewInput) (Review, State, error) {
	if !validID(videoID) {
		return Review{}, "", ErrNotFound
	}
	in.Note = strings.TrimSpace(in.Note)
	e, err := prepare(in)
	if err != nil {
		return Review{}, "", err
	}
	now := s.now()
	rv := Review{Decision: e.decision, Theme: in.Theme, MinAgeBand: in.MinAgeBand, Reason: e.reason,
		ChecklistVersion: ChecklistVersion, FailedItems: e.failed, ReviewedAt: now}
	if e.decision != Reject {
		rv.Answers = maps.Clone(in.Answers)
	}
	var state State
	var event audit.Event
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		var st string
		var round int
		var due *time.Time
		err := tx.QueryRow(ctx, `SELECT state, round, review_due_at FROM videos WHERE id = $1::uuid FOR UPDATE`, videoID).
			Scan(&st, &round, &due)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		state = State(st)
		var own, reviewed bool
		if err := tx.QueryRow(ctx, `SELECT
			EXISTS (SELECT 1 FROM video_suggestions WHERE video_id = $1::uuid AND account_id = $2::uuid),
			EXISTS (SELECT 1 FROM video_reviews WHERE video_id = $1::uuid AND round = $3 AND curator_id = $2::uuid)`,
			videoID, curatorID, round).Scan(&own, &reviewed); err != nil {
			return err
		}
		revisitDue := state == Approved && due != nil && !due.After(now)
		switch {
		case own:
			return ErrOwnSuggestion
		case state != Pending && !revisitDue:
			return ErrNotReviewable
		case reviewed:
			return ErrAlreadyReviewed
		}
		// FOR SHARE: a removal waits for this review, and no review lands
		// for a curator removed meanwhile.
		var role string
		err = tx.QueryRow(ctx, `SELECT display_role FROM platform_roles WHERE account_id = $1::uuid AND role = 'curator' FOR SHARE`,
			curatorID).Scan(&role)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotCurator
		}
		if err != nil {
			return err
		}
		rv.DisplayRole = DisplayRole(role)
		if _, err := tx.Exec(ctx, `INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme,
			min_age_band, reason, reviewed_at, checklist_version, checklist) VALUES ($1::uuid, $2, $3::uuid, $4, $5,
			nullif($6::text, ''), nullif($7::text, ''), nullif($8::text, ''), $9, $10, $11::text::jsonb)`,
			videoID, round, curatorID, role, string(e.decision), in.Theme, string(in.MinAgeBand), e.reason, now,
			ChecklistVersion, string(e.checklist)); err != nil {
			return err
		}
		// A rejection or a doubt holds the video at once, pending or in a
		// revisit: one is enough.
		if e.decision != Approve {
			why := HeldByReview
			if e.decision == Doubt {
				why = HeldByDoubt
			}
			state, event = Held, audit.VideoHeld
			_, err := tx.Exec(ctx, `UPDATE videos SET state = 'held', held_reason = $3, updated_at = $2 WHERE id = $1::uuid`,
				videoID, now, why)
			return err
		}
		published, held, err := s.publishIfComplete(ctx, tx, videoID, round, now)
		switch {
		case held:
			state, event = Held, audit.VideoHeld
		case published:
			state, event = Approved, audit.VideoPublished
		}
		return err
	})
	if err != nil {
		return Review{}, "", err
	}
	if event != "" {
		s.d.Audit.Record(ctx, curatorID, event)
	}
	return rv, state, nil
}

type approval struct {
	theme string
	band  family.AgeBand
}

// publishIfComplete publishes the video once its round holds
// MinApprovals approvals by curators who still hold the role: the
// approvals of removed or erased curators stay in the round but do not
// count. No rejection can be in the round: a rejection
// holds the video at once, and a held video takes no review. Publishing
// moves the round on, so the next round is the revisit.
// It returns whether the video was published and whether its reports
// then held it.
func (s *Service) publishIfComplete(ctx context.Context, tx pgx.Tx, videoID string, round int, now time.Time) (bool, bool, error) {
	reached, err := s.approvalsReached(ctx, tx, videoLedger, videoID, round)
	if err != nil || !reached {
		return false, false, err
	}
	// The theme and the band come from the same approvals the rule counted.
	rows, err := tx.Query(ctx, `SELECT r.theme, r.min_age_band FROM video_reviews r
		JOIN platform_roles p ON p.account_id = r.curator_id AND p.role = 'curator'
		WHERE r.video_id = $1::uuid AND r.round = $2 AND r.decision = 'approve' ORDER BY r.reviewed_at, r.id`, videoID, round)
	if err != nil {
		return false, false, err
	}
	approvals, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (approval, error) {
		var a approval
		var band string
		err := r.Scan(&a.theme, &band)
		a.band = family.AgeBand(band)
		return a, err
	})
	if err != nil {
		return false, false, err
	}
	// The count and this read are two statements: a curator removed in
	// between would leave fewer approvals than were counted. Publish only
	// on as many as the rule requires.
	if len(approvals) < s.d.MinApprovals {
		return false, false, nil
	}
	theme, band := published(approvals)
	if _, err = tx.Exec(ctx, `UPDATE videos SET state = 'approved', round = round + 1, theme = $2, min_age_band = $3,
		published_round = round, last_reviewed_at = $4, review_due_at = $5, updated_at = $4 WHERE id = $1::uuid`,
		videoID, theme, string(band), now, now.Add(s.d.RevisitAfter)); err != nil {
		return false, false, err
	}
	// Reports made while the video waited were stored but not acted on:
	// a video already at the threshold is held as it is published.
	n, err := reportsSinceReopen(ctx, tx, videoID)
	if err != nil || n < s.d.ReportThreshold {
		return true, false, err
	}
	_, err = tx.Exec(ctx, `UPDATE videos SET state = 'held', held_reason = $2 WHERE id = $1::uuid`, videoID, HeldByReports)
	return true, err == nil, err
}

// published picks the strictest band and the most approved theme, a tie
// going to the theme approved first. approvals are in review
// order.
func published(approvals []approval) (string, family.AgeBand) {
	counts := map[string]int{}
	band := approvals[0].band
	for _, a := range approvals {
		counts[a.theme]++
		if bandRank(a.band) > bandRank(band) {
			band = a.band
		}
	}
	theme := approvals[0].theme
	for _, a := range approvals {
		if counts[a.theme] > counts[theme] {
			theme = a.theme
		}
	}
	return theme, band
}

// entry is a review as the ledger stores it.
type entry struct {
	decision  Decision
	reason    string   // a rejection's failed questions and note; a doubt's note
	checklist []byte   // the answers, or the failed questions
	failed    []string // a rejection's questions, in the list's order
}

// prepare checks a review before any lookup and turns it into its ledger
// entry. A refused review stores nothing.
func prepare(in ReviewInput) (entry, error) {
	if in.Decision != Approve && in.Decision != Reject {
		return entry{}, ErrValidation
	}
	if in.ChecklistVersion != ChecklistVersion {
		return entry{}, ErrChecklistOutdated
	}
	if utf8.RuneCountInString(in.Note) > maxReason {
		return entry{}, ErrValidation
	}
	if in.Decision == Reject {
		if in.Theme != "" || in.MinAgeBand != "" || in.Answers != nil {
			return entry{}, ErrValidation
		}
		items, err := failedItems(in.FailedItems)
		if err != nil {
			return entry{}, err
		}
		ids := make([]string, len(items))
		for i, it := range items {
			ids[i] = it.ID
		}
		list, err := json.Marshal(ids)
		return entry{decision: Reject, reason: composeReason(items, in.Note), checklist: list, failed: ids}, err
	}
	if !validTheme(in.Theme) || bandRank(in.MinAgeBand) == 0 || in.FailedItems != nil {
		return entry{}, ErrValidation
	}
	doubt, err := judge(in.Answers, in.MinAgeBand)
	if err != nil {
		return entry{}, err
	}
	// A note travels only with a doubt: a plain approval has nothing to explain.
	if !doubt && in.Note != "" {
		return entry{}, ErrValidation
	}
	list, err := json.Marshal(in.Answers)
	if doubt {
		return entry{decision: Doubt, reason: in.Note, checklist: list}, err
	}
	return entry{decision: Approve, checklist: list}, err
}

// VideoDetail reads a video, its current round's reviews and its
// provenance, in one snapshot.
func (s *Service) VideoDetail(ctx context.Context, id string) (VideoDetail, error) {
	if !validID(id) {
		return VideoDetail{}, ErrNotFound
	}
	tx, err := s.d.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return VideoDetail{}, err
	}
	defer tx.Rollback(ctx)
	var d VideoDetail
	d.Video, err = scanVideo(tx.QueryRow(ctx, `SELECT `+videoCols+` FROM videos v WHERE v.id = $1::uuid`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return VideoDetail{}, ErrNotFound
	}
	if err != nil {
		return VideoDetail{}, err
	}
	if d.Reviews, err = reviewsOf(ctx, tx, id, d.Video.Round, ""); err != nil {
		return VideoDetail{}, err
	}
	if d.Video.PublishedRound != nil {
		if d.Provenance, err = provenance(ctx, tx, d.Video); err != nil {
			return VideoDetail{}, err
		}
	}
	return d, tx.Commit(ctx)
}

// provenance counts, by displayed role, the approvals of the round that
// last published the video (published_round, not the round under
// review), with when it was published.
func provenance(ctx context.Context, q querier, v Video) (*Provenance, error) {
	return roundProvenance(ctx, q, videoLedger, v.ID, *v.PublishedRound, v.LastReviewedAt)
}

// reviewsOf lists a round's reviews in review order; decision "" is all
// of them.
func reviewsOf(ctx context.Context, q querier, videoID string, round int, decision Decision) ([]Review, error) {
	rows, err := q.Query(ctx, `SELECT display_role, decision, coalesce(theme, ''), coalesce(min_age_band, ''),
		coalesce(reason, ''), reviewed_at, coalesce(checklist_version, ''), checklist FROM video_reviews
		WHERE video_id = $1::uuid AND round = $2 AND ($3::text = '' OR decision = $3::text) ORDER BY reviewed_at, id`,
		videoID, round, string(decision))
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Review, error) {
		var x Review
		var role, dec, band string
		var list []byte
		if err := r.Scan(&role, &dec, &x.Theme, &band, &x.Reason, &x.ReviewedAt, &x.ChecklistVersion, &list); err != nil {
			return x, err
		}
		x.DisplayRole, x.Decision, x.MinAgeBand, x.ReviewedAt = DisplayRole(role), Decision(dec), family.AgeBand(band), x.ReviewedAt.UTC()
		switch {
		case list == nil: // written before the list
		case x.Decision == Reject:
			return x, json.Unmarshal(list, &x.FailedItems)
		default:
			return x, json.Unmarshal(list, &x.Answers)
		}
		return x, nil
	})
}
