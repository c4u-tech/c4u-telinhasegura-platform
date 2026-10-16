package curation

import (
	"context"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// PackReviewInput is an approval, or a rejection with a reason (packs,
// Contract).
type PackReviewInput struct {
	Decision Decision
	Reason   string
}

func validPackReview(in PackReviewInput) bool {
	switch in.Decision {
	case Approve:
		return in.Reason == ""
	case Reject:
		n := utf8.RuneCountInString(in.Reason)
		return n >= 1 && n <= maxReason
	}
	return false
}

// ReviewPack stores a curator's review of a pack's current round and
// applies its effect in the same transaction. The pack
// row lock comes first, so the reviews of one pack run one at a time: the
// count sees every earlier review, and two last approvals publish once.
// It answers the review and the pack's state after it.
func (s *Service) ReviewPack(ctx context.Context, curatorID, packID string, in PackReviewInput) (PackReview, State, error) {
	if !validID(packID) {
		return PackReview{}, "", ErrNotFound
	}
	in.Reason = strings.TrimSpace(in.Reason)
	if !validPackReview(in) {
		return PackReview{}, "", ErrValidation
	}
	now := s.now()
	rv := PackReview{Decision: in.Decision, Reason: in.Reason, ReviewedAt: now}
	var state State
	var event audit.Event
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var st string
		var round int
		err := tx.QueryRow(ctx, `SELECT state, round FROM packs WHERE id = $1::uuid FOR UPDATE`, packID).Scan(&st, &round)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		state = State(st)
		var outcome string
		var own, reviewed bool
		if err := tx.QueryRow(ctx, `SELECT r.outcome, coalesce(r.composer_id = $3::uuid, false),
			EXISTS (SELECT 1 FROM pack_reviews x WHERE x.pack_id = r.pack_id AND x.round = r.round AND x.curator_id = $3::uuid)
			FROM pack_rounds r WHERE r.pack_id = $1::uuid AND r.round = $2`, packID, round, curatorID).
			Scan(&outcome, &own, &reviewed); err != nil {
			return err
		}
		switch {
		case own:
			return ErrOwnComposition
		case state == Removed || outcome != "open":
			return ErrNotReviewable
		case reviewed:
			return ErrAlreadyReviewed
		}
		role, err := curatorRole(ctx, tx, curatorID)
		if err != nil {
			return err
		}
		rv.DisplayRole = DisplayRole(role)
		if _, err := tx.Exec(ctx, `INSERT INTO pack_reviews (pack_id, round, curator_id, display_role, decision, reason, reviewed_at)
			VALUES ($1::uuid, $2, $3::uuid, $4, $5, nullif($6::text, ''), $7)`,
			packID, round, curatorID, role, string(in.Decision), in.Reason, now); err != nil {
			return err
		}
		if in.Decision == Reject {
			// A pending pack is held; an approved one keeps its published
			// round and takes no review until the next recompose.
			if state == Pending {
				state, event = Held, audit.PackHeld
			}
			if _, err := tx.Exec(ctx, `UPDATE pack_rounds SET outcome = 'rejected' WHERE pack_id = $1::uuid AND round = $2`,
				packID, round); err != nil {
				return err
			}
			_, err := tx.Exec(ctx, `UPDATE packs SET state = $2, updated_at = $3 WHERE id = $1::uuid`, packID, string(state), now)
			return err
		}
		reached, err := s.approvalsReached(ctx, tx, packLedger, packID, round)
		if err != nil || !reached {
			return err
		}
		state, event = Approved, audit.PackPublished
		if _, err := tx.Exec(ctx, `UPDATE pack_rounds SET outcome = 'published' WHERE pack_id = $1::uuid AND round = $2`,
			packID, round); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE packs SET state = 'approved', published_round = round, last_reviewed_at = $2,
			updated_at = $2 WHERE id = $1::uuid`, packID, now)
		return err
	})
	if err != nil {
		return PackReview{}, "", err
	}
	if event != "" {
		s.d.Audit.Record(ctx, curatorID, event)
	}
	return rv, state, nil
}
