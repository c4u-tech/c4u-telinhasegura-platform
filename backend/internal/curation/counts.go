package curation

// Platform totals for the staff metrics. staff
// cannot import curation (curation imports staff), so these answer plain
// counts through staff's ContentCounter interface.

import (
	"context"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// CountPublishedVideos counts the videos in state approved.
func (s *Service) CountPublishedVideos(ctx context.Context) (int, error) {
	return s.countRows(ctx, `SELECT count(*) FROM videos WHERE state = 'approved'`)
}

// CountPublishedPacks counts the pacotinhos in state approved.
func (s *Service) CountPublishedPacks(ctx context.Context) (int, error) {
	return s.countRows(ctx, `SELECT count(*) FROM packs WHERE state = 'approved'`)
}

// CountReportsSince counts the video reports made at or after since.
func (s *Service) CountReportsSince(ctx context.Context, since time.Time) (int, error) {
	return s.countRows(ctx, `SELECT count(*) FROM video_reports WHERE reported_at >= $1`, since)
}

// ReviewMeasuresSince reads the reviews made at or after since: how long
// approvals took, how many reviews were doubts, how often the stated band
// was older than the computed one, and how often two approvals of one
// video round computed different bands.
func (s *Service) ReviewMeasuresSince(ctx context.Context, since time.Time) (staff.ReviewMeasures, error) {
	var m staff.ReviewMeasures
	err := s.d.Pool.QueryRow(ctx, `
		SELECT count(*) FILTER (WHERE decision = 'approve' AND began_at IS NOT NULL),
		       coalesce(round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM reviewed_at - began_at)::float8)
		           FILTER (WHERE decision = 'approve' AND began_at IS NOT NULL))::numeric), 0)::int,
		       count(*),
		       count(*) FILTER (WHERE decision = 'doubt'),
		       count(*) FILTER (WHERE computed_band IS NOT NULL),
		       count(*) FILTER (WHERE computed_band IS NOT NULL
		           AND array_position(ARRAY['ate-4','5-8','9-12'], min_age_band) > array_position(ARRAY['ate-4','5-8','9-12'], computed_band))
		FROM video_reviews WHERE reviewed_at >= $1`, since).
		Scan(&m.TimedApprovals, &m.ApprovalMedianSeconds, &m.Reviews, &m.Doubts, &m.ComputedApprovals, &m.OlderStated)
	if err != nil {
		return m, err
	}
	err = s.d.Pool.QueryRow(ctx, `
		SELECT count(*), count(*) FILTER (WHERE bands > 1) FROM (
			SELECT count(DISTINCT computed_band) AS bands FROM video_reviews
			WHERE reviewed_at >= $1 AND computed_band IS NOT NULL
			GROUP BY video_id, round HAVING count(*) >= 2) rounds`, since).
		Scan(&m.PairedVideos, &m.SplitVideos)
	return m, err
}

func (s *Service) countRows(ctx context.Context, sql string, args ...any) (int, error) {
	var n int
	err := s.d.Pool.QueryRow(ctx, sql, args...).Scan(&n)
	return n, err
}
