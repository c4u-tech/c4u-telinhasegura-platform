package curation

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

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
// Any other held video keeps the reopen and remove of moderation. No one
// decides a round they reviewed in, as the doubter or beside them.
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
		var round, seconds int
		err := tx.QueryRow(ctx, `SELECT state, held_reason, round, duration_seconds FROM videos WHERE id = $1::uuid FOR UPDATE`, videoID).
			Scan(&st, &held, &round, &seconds)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if State(st) != Held || held == nil || *held != HeldByDoubt {
			return ErrStateConflict
		}
		if err := notReviewedBy(ctx, tx, videoID, round, m.ActorID); err != nil {
			return err
		}
		// A moderator is held to the rule the curators follow: no band
		// younger than the round's answers and the length allow.
		if d.Decision == Approve {
			band, err := s.roundBand(ctx, tx, videoID, round, seconds)
			if err != nil {
				return err
			}
			if bandRank(d.MinAgeBand) < bandRank(band) {
				return ErrChecklistBand
			}
		}
		// Either way the round is over, and the drafts of it with it.
		if err := closeDrafts(ctx, tx, videoID); err != nil {
			return err
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

// roundBand is the youngest band a round's answers allow for a video of
// that many seconds: the oldest any of its reviews allows. Each review is
// read under the list it was stored with, where a band question's yes
// allows from its own band up. Rejections store their answers as a list,
// so they bar nothing.
func (s *Service) roundBand(ctx context.Context, q querier, videoID string, round, seconds int) (family.AgeBand, error) {
	over := time.Duration(seconds)*time.Second > s.d.FamilyYoungestMaxDuration
	rows, err := q.Query(ctx, `SELECT coalesce(checklist_version, ''), checklist FROM video_reviews
		WHERE video_id = $1::uuid AND round = $2 AND jsonb_typeof(checklist) = 'object'`, videoID, round)
	if err != nil {
		return "", err
	}
	bands, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (family.AgeBand, error) {
		var version string
		var list []byte
		if err := r.Scan(&version, &list); err != nil {
			return "", err
		}
		var answers map[string]Answer
		if err := json.Unmarshal(list, &answers); err != nil {
			return "", err
		}
		return bandFrom(version, answers, over), nil
	})
	if err != nil {
		return "", err
	}
	band := bandFrom("", nil, over)
	for _, b := range bands {
		if bandRank(b) > bandRank(band) {
			band = b
		}
	}
	return band, nil
}
