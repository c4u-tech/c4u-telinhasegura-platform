package curation

// Platform totals for the staff metrics. staff
// cannot import curation (curation imports staff), so these answer plain
// counts through staff's ContentCounter interface.

import (
	"context"
	"time"
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

func (s *Service) countRows(ctx context.Context, sql string, args ...any) (int, error) {
	var n int
	err := s.d.Pool.QueryRow(ctx, sql, args...).Scan(&n)
	return n, err
}
