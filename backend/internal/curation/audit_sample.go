package curation

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5"
)

const (
	// auditSampleSize is how many approvals a moderator checks at a time:
	// enough to notice a curator who misreads the criteria, few enough to
	// watch each video.
	auditSampleSize = 10
	// auditWindow is how far back a sample reaches: a recent approval can
	// still be put right before many children watch it.
	auditWindow = 30 * 24 * time.Hour
)

type Verdict string

const (
	Agree    Verdict = "agree"
	Disagree Verdict = "disagree"
)

// AuditCandidate is a published round offered to an audit: the video and
// the approvals that published it, with their answers and displayed roles,
// never the curators' accounts.
type AuditCandidate struct {
	Video     Video
	Round     int
	Approvals []Review
}

// AuditInput is one audit of a published round. Hold, on a disagreement
// only, takes the video off the shelves while it is still approved.
type AuditInput struct {
	VideoID string
	Round   int
	Verdict Verdict
	Hold    bool
}

// AuditSample draws, at random, up to auditSampleSize videos still in the
// catalogue whose last publication is within auditWindow, holds at least
// one curator's approval, and was never audited. A round the auditor
// reviewed is left out: an account may both curate and moderate, and no
// one checks their own work.
func (s *Service) AuditSample(ctx context.Context, auditorID string) ([]AuditCandidate, error) {
	rows, err := s.d.Pool.Query(ctx, `SELECT `+videoCols+` FROM videos v
		WHERE v.state = 'approved' AND v.published_round IS NOT NULL AND v.last_reviewed_at >= $1
		AND EXISTS (SELECT 1 FROM video_reviews r WHERE r.video_id = v.id AND r.round = v.published_round AND r.decision = 'approve')
		AND NOT EXISTS (SELECT 1 FROM approval_audits a WHERE a.video_id = v.id AND a.round = v.published_round)
		AND NOT EXISTS (SELECT 1 FROM video_reviews o WHERE o.video_id = v.id AND o.round = v.published_round AND o.curator_id = $3::uuid)
		ORDER BY random() LIMIT $2`, s.now().Add(-auditWindow), auditSampleSize, auditorID)
	if err != nil {
		return nil, err
	}
	videos, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Video, error) { return scanVideo(r) })
	if err != nil {
		return nil, err
	}
	out := make([]AuditCandidate, 0, len(videos))
	for _, v := range videos {
		approvals, err := reviewsOf(ctx, s.d.Pool, v.ID, *v.PublishedRound, Approve)
		if err != nil {
			return nil, err
		}
		out = append(out, AuditCandidate{Video: v, Round: *v.PublishedRound, Approvals: approvals})
	}
	return out, nil
}

// AuditApproval records a moderator's or an admin's check of a published
// round, once. A disagreement carries its reason and may hold the video;
// an agreement may carry one. The round must be the one that last
// published the video, and one the auditor did not review.
func (s *Service) AuditApproval(ctx context.Context, m Moderation, in AuditInput) error {
	reason := strings.TrimSpace(m.Reason)
	switch {
	case in.Verdict == Disagree, in.Verdict == Agree && !in.Hold && reason != "":
		r, err := staff.CheckReason(reason)
		if err != nil {
			return err
		}
		reason = r
	case in.Verdict == Agree && !in.Hold:
	default:
		return ErrValidation
	}
	if !validID(in.VideoID) {
		return ErrNotFound
	}
	now := s.now()
	held := false
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var st string
		var published *int
		err := tx.QueryRow(ctx, `SELECT state, published_round FROM videos WHERE id = $1::uuid FOR UPDATE`, in.VideoID).
			Scan(&st, &published)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if published == nil || *published != in.Round {
			return ErrStateConflict
		}
		if err := notReviewedBy(ctx, tx, in.VideoID, in.Round, m.ActorID); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `INSERT INTO approval_audits (video_id, round, auditor_id, verdict, reason, audited_at)
			VALUES ($1::uuid, $2, $3::uuid, $4, nullif($5::text, ''), $6) ON CONFLICT (video_id, round) DO NOTHING`,
			in.VideoID, in.Round, m.ActorID, string(in.Verdict), reason, now)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrAlreadyAudited
		}
		if !in.Hold || State(st) != Approved {
			return nil
		}
		held = true
		_, err = tx.Exec(ctx, `UPDATE videos SET state = 'held', held_reason = $2, updated_at = $3 WHERE id = $1::uuid`,
			in.VideoID, HeldByAudit, now)
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.RecordAction(ctx, audit.Action{Actor: m.ActorID, ActorRole: string(m.ActorRole), Event: audit.ApprovalAudited,
		SubjectKind: audit.SubjectVideo, SubjectID: strings.ToLower(in.VideoID), Reason: reason,
		Metadata: map[string]string{"verdict": string(in.Verdict), "round": strconv.Itoa(in.Round), "held": strconv.FormatBool(held)}})
	if held {
		s.d.Audit.Record(ctx, m.ActorID, audit.VideoHeld)
	}
	return nil
}

// notReviewedBy refuses with ErrOwnReview when account reviewed the
// video's round, whatever it decided: a moderator who also curates never
// judges a round they took part in.
func notReviewedBy(ctx context.Context, tx pgx.Tx, videoID string, round int, account string) error {
	var own bool
	err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM video_reviews WHERE video_id = $1::uuid AND round = $2
		AND curator_id = $3::uuid)`, videoID, round, account).Scan(&own)
	if err != nil {
		return err
	}
	if own {
		return ErrOwnReview
	}
	return nil
}
