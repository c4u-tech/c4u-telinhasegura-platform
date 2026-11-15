package curation

import (
	"context"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// PublishReady publishes every video whose current round already holds
// MinApprovals approvals. The count is checked when a review lands, so a
// lowered threshold would otherwise leave such a video waiting for a review
// it no longer needs. Each video goes through the rule a review applies,
// under its row lock, so a review landing at the same time publishes it
// once. It is idempotent, so every replica may run it.
func (s *Service) PublishReady(ctx context.Context) error {
	return s.publishReadyVideos(ctx)
}

func (s *Service) publishReadyVideos(ctx context.Context) error {
	rows, err := s.d.Pool.Query(ctx, `SELECT v.id::text FROM videos v
		WHERE (v.state = 'pending' OR v.state = 'approved' AND v.review_due_at <= $1)
		AND (SELECT count(*) FROM video_reviews r
			JOIN platform_roles p ON p.account_id = r.curator_id AND p.role = 'curator'
			WHERE r.video_id = v.id AND r.round = v.round AND r.decision = 'approve') >= $2
		ORDER BY v.id`, s.now(), s.d.MinApprovals)
	if err != nil {
		return err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err := s.publishReadyVideo(ctx, id); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) publishReadyVideo(ctx context.Context, videoID string) error {
	now := s.now()
	var published, held bool
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var st string
		var round int
		var due *time.Time
		if err := tx.QueryRow(ctx, `SELECT state, round, review_due_at FROM videos WHERE id = $1::uuid FOR UPDATE`, videoID).
			Scan(&st, &round, &due); err != nil {
			return err
		}
		// A review may have published or held it since the selection.
		revisitDue := State(st) == Approved && due != nil && !due.After(now)
		if State(st) != Pending && !revisitDue {
			return nil
		}
		var err error
		published, held, err = s.publishIfComplete(ctx, tx, videoID, round, now)
		return err
	})
	switch {
	case err != nil:
		return err
	case held:
		s.d.Audit.Record(ctx, "", audit.VideoHeld)
	case published:
		s.d.Audit.Record(ctx, "", audit.VideoPublished)
	}
	return nil
}
