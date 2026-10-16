package curation

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

// ReportUnavailable re-checks a video the child's player could not play
// and holds it when YouTube no longer passes it. Past the
// eligibility check it answers nil whether or not it checked: the
// child's app has nothing to do with the outcome. The child's budget is
// spent before the video's, so one child cannot use up the hourly check
// of every video.
func (s *Service) ReportUnavailable(ctx context.Context, c Child, videoID string) error {
	v, err := s.eligibleVideo(ctx, c, videoID)
	if err != nil {
		return err
	}
	if ok, _ := s.d.CheckChildLimiter.Allow(c.MinorID); !ok {
		return nil
	}
	if ok, _ := s.d.CheckVideoLimiter.Allow(v.ID); !ok {
		return nil
	}
	if s.d.Source == nil { // YOUTUBE_API_KEY is empty: no verdict, nothing held
		return nil
	}
	m, err := s.d.Source.Video(ctx, v.YouTubeID)
	switch {
	case errors.Is(err, ErrVideoNotFound):
	case err != nil:
		// The source's errors carry neither the key nor the URL.
		s.d.Log.Error("curation: video source failed", "err", err)
		return nil
	case s.refusal(m) == "":
		return nil
	}
	return s.holdApproved(ctx, v.ID, HeldByUnavailable, "")
}

// holdApproved holds a video that is still approved, for reason, and
// records it under actor ("" is the system). A video a curator or
// a report held meanwhile is left as it is.
func (s *Service) holdApproved(ctx context.Context, videoID, reason, actor string) error {
	tag, err := s.d.Pool.Exec(ctx, `UPDATE videos SET state = 'held', held_reason = $2, updated_at = $3
		WHERE id = $1::uuid AND state = 'approved'`, videoID, reason, s.now())
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 1 {
		s.d.Audit.Record(ctx, actor, audit.VideoHeld)
	}
	return nil
}
