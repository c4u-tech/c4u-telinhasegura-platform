package curation

import (
	"context"
	"errors"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5"
)

// DoubtDecision is a moderator's answer to a curator's doubt: publish the
// video with a theme and a band, or remove it.
type DoubtDecision struct {
	Decision   Decision // Approve or Reject
	Theme      string
	MinAgeBand family.AgeBand
}

// DecideDoubt settles a video held by a curator's doubt. Volunteers do not
// interpret the criteria on their own: an unsure case is decided by the
// team, with a recorded reason. Publishing closes the round as the
// curators' approvals would; removing works as a moderator's removal.
// Publishing also restarts the report count, as a reopen does: the
// moderator saw the reports filed while the video was held.
// Any other held video keeps the reopen and remove of moderation.
func (s *Service) DecideDoubt(ctx context.Context, m Moderation, videoID string, d DoubtDecision) error {
	reason, err := staff.CheckReason(m.Reason)
	if err != nil {
		return err
	}
	switch d.Decision {
	case Approve:
		if !validTheme(d.Theme) || bandRank(d.MinAgeBand) == 0 {
			return ErrValidation
		}
	case Reject:
		if d.Theme != "" || d.MinAgeBand != "" {
			return ErrValidation
		}
	default:
		return ErrValidation
	}
	if !validID(videoID) {
		return ErrNotFound
	}
	now := s.now()
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		var st string
		var held *string
		err := tx.QueryRow(ctx, `SELECT state, held_reason FROM videos WHERE id = $1::uuid FOR UPDATE`, videoID).Scan(&st, &held)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if State(st) != Held || held == nil || *held != HeldByDoubt {
			return ErrStateConflict
		}
		if d.Decision == Reject {
			_, err = tx.Exec(ctx, `UPDATE videos SET state = 'removed', updated_at = $2 WHERE id = $1::uuid`, videoID, now)
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE videos SET state = 'approved', held_reason = NULL, round = round + 1,
			published_round = round, theme = $2, min_age_band = $3, last_reviewed_at = $4, review_due_at = $5, reopened_at = $4,
			updated_at = $4 WHERE id = $1::uuid`, videoID, d.Theme, string(d.MinAgeBand), now, now.Add(s.d.RevisitAfter))
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.RecordAction(ctx, audit.Action{Actor: m.ActorID, ActorRole: string(m.ActorRole), Event: audit.VideoDoubtDecided,
		SubjectKind: audit.SubjectVideo, SubjectID: strings.ToLower(videoID), Reason: reason,
		Metadata: map[string]string{"decision": string(d.Decision)}})
	return nil
}
