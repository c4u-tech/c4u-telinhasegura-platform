package curation

import (
	"context"
	"errors"
	"slices"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5"
)

// HeldVideo is a held video with its held round's rejections and
// why it is held.
type HeldVideo struct {
	Video      Video
	Rejections []Review
	Reports    ReportSummary // since the latest reopen
	HeldReason string        // HeldByReview, HeldByReports or HeldByUnavailable
}

// HeldVideos lists the held videos, the longest held first, each with
// the rejections of the round that held it (videos.round).
func (s *Service) HeldVideos(ctx context.Context) ([]HeldVideo, error) {
	rows, err := s.d.Pool.Query(ctx, `SELECT `+videoCols+`, v.held_reason FROM videos v WHERE v.state = 'held' ORDER BY v.updated_at, v.id`)
	if err != nil {
		return nil, err
	}
	out, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (HeldVideo, error) {
		var h HeldVideo
		var err error
		h.Video, err = scanVideo(r, &h.HeldReason)
		return h, err
	})
	if err != nil {
		return nil, err
	}
	for i := range out {
		if out[i].Rejections, err = reviewsOf(ctx, s.d.Pool, out[i].Video.ID, out[i].Video.Round, Reject); err != nil {
			return nil, err
		}
		if out[i].Reports, err = reportsOf(ctx, s.d.Pool, out[i].Video.ID); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// Moderation is who moderates a video, under which platform role, and
// why. httpapi sets ActorRole to the role its
// moderator route matched.
type Moderation struct {
	ActorID   string
	ActorRole staff.Role
	Reason    string
}

// ModerateRemove removes a held video for good; it is then refused as a
// suggestion. The reason is recorded once, as an action on
// the video.
func (s *Service) ModerateRemove(ctx context.Context, m Moderation, videoID string) error {
	return s.moderate(ctx, m, videoID, []State{Held}, Removed, 0, audit.VideoRemoved)
}

// ModerateReopen makes a held or removed video pending in a new round,
// with a reason. The earlier rounds' reviews stay
// and count for nothing in it.
func (s *Service) ModerateReopen(ctx context.Context, m Moderation, videoID string) error {
	return s.moderate(ctx, m, videoID, []State{Held, Removed}, Pending, 1, audit.VideoReopened)
}

// moderate checks the reason before anything else, decides, then records
// the write's one action.
func (s *Service) moderate(ctx context.Context, m Moderation, videoID string, from []State, to State, nextRound int, e audit.Event) error {
	reason, err := staff.CheckReason(m.Reason)
	if err != nil {
		return err
	}
	if err := s.decide(ctx, videoID, from, to, nextRound); err != nil {
		return err
	}
	s.d.Audit.RecordAction(ctx, audit.Action{Actor: m.ActorID, ActorRole: string(m.ActorRole), Event: e,
		SubjectKind: audit.SubjectVideo, SubjectID: strings.ToLower(videoID), Reason: reason})
	return nil
}

// decide moves a video from one of the states in from to state to,
// adding nextRound to its round, under the video row lock that reviews
// take too. Its callers record the decision.
func (s *Service) decide(ctx context.Context, videoID string, from []State, to State, nextRound int) error {
	if !validID(videoID) {
		return ErrNotFound
	}
	return s.inTx(ctx, func(tx pgx.Tx) error {
		var st string
		err := tx.QueryRow(ctx, `SELECT state FROM videos WHERE id = $1::uuid FOR UPDATE`, videoID).Scan(&st)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if !slices.Contains(from, State(st)) {
			return ErrStateConflict
		}
		// A reopen clears the hold and marks where report counting
		// restarts.
		_, err = tx.Exec(ctx, `UPDATE videos SET state = $2::text, round = round + $3, updated_at = $4,
			held_reason = CASE WHEN $2::text = 'pending' THEN NULL ELSE held_reason END,
			reopened_at = CASE WHEN $2::text = 'pending' THEN $4 ELSE reopened_at END
			WHERE id = $1::uuid`, videoID, string(to), nextRound, s.now())
		return err
	})
}
