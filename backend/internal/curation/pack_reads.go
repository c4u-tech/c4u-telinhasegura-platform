package curation

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// ApprovedVideos lists the approved videos of theme, by title then id, 50
// a page, for a curator composing a pack. It does
// not depend on the caller. more reports a further page at offset + 50.
func (s *Service) ApprovedVideos(ctx context.Context, theme string, offset int) ([]Video, bool, error) {
	if !validTheme(theme) || offset < 0 {
		return nil, false, ErrValidation
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT `+videoCols+` FROM videos v
		WHERE v.state = 'approved' AND v.theme = $1
		ORDER BY v.title, v.id LIMIT $2 OFFSET $3`, theme, queuePage+1, offset)
	if err != nil {
		return nil, false, err
	}
	vs, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Video, error) { return scanVideo(r) })
	if err != nil {
		return nil, false, err
	}
	if len(vs) > queuePage {
		return vs[:queuePage], true, nil
	}
	return vs, false, nil
}

// PackLimits are the composition rules Compose enforces.
type PackLimits struct {
	MinVideos, MaxVideos int
	MaxDuration          time.Duration
}

func (s *Service) PackLimits() PackLimits {
	return PackLimits{MinVideos: packMinVideos, MaxVideos: packMaxVideos, MaxDuration: s.d.PackMaxDuration}
}

// AdminPacks lists the packs that are not removed, in the curator list's
// order and pages, for an admin who need not be a curator. An admin read
// is never a review: Reviewable is false.
func (s *Service) AdminPacks(ctx context.Context, adminID string, offset int) ([]Pack, bool, error) {
	ps, more, err := s.PackQueue(ctx, adminID, offset)
	for i := range ps {
		ps[i].Reviewable = false
	}
	return ps, more, err
}

// AdminPack reads one pack in any state, a removed one included, with
// Reviewable false.
func (s *Service) AdminPack(ctx context.Context, adminID, id string) (Pack, error) {
	p, err := s.PackDetail(ctx, adminID, id)
	p.Reviewable = false
	return p, err
}
