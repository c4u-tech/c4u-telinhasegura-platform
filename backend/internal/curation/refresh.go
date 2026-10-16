package curation

import (
	"context"
	"errors"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// sourceMaxAge keeps stored YouTube data inside the 30 days YouTube
// allows (Developer Policies III.E.4), with a margin for missed sweeps.
const (
	sourceMaxAge = 25 * 24 * time.Hour
	refreshBatch = 50 // videos.list takes at most 50 IDs
)

// RefreshSources re-checks, in batches, every video whose YouTube data is
// older than sourceMaxAge or was never checked. A video YouTube
// still returns is refreshed, and held if it now fails a refusal rule. A
// video YouTube no longer returns is held, its title and channel blanked,
// its thumbnail deleted. While YouTube is unavailable nothing changes.
// Each batch is selected FOR NO KEY UPDATE SKIP LOCKED, so replicas
// sweeping at once never check the same video; NO KEY keeps plays and
// thumbnails (FOR KEY SHARE on their FK checks) from waiting on the
// YouTube call.
func (s *Service) RefreshSources(ctx context.Context) error {
	if s.d.Source == nil { // YOUTUBE_API_KEY is empty: no verdict, nothing changes
		return nil
	}
	for {
		n, stamped, err := s.refreshBatch(ctx)
		if err != nil || n < refreshBatch || stamped == 0 {
			return err
		}
	}
}

func (s *Service) refreshBatch(ctx context.Context) (selected, stamped int, err error) {
	type row struct{ id, youtubeID, state string }
	var batch []row
	held := 0
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		now := s.now()
		rows, err := tx.Query(ctx, `SELECT id::text, youtube_id, state FROM videos
			WHERE source_checked_at IS NULL OR source_checked_at < $1
			ORDER BY source_checked_at NULLS FIRST, id LIMIT $2 FOR NO KEY UPDATE SKIP LOCKED`, now.Add(-sourceMaxAge), refreshBatch)
		if err != nil {
			return err
		}
		batch, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (row, error) {
			var x row
			return x, r.Scan(&x.id, &x.youtubeID, &x.state)
		})
		if err != nil || len(batch) == 0 {
			return err
		}
		ids := make([]string, len(batch))
		for i, x := range batch {
			ids[i] = x.youtubeID
		}
		got, err := s.d.Source.Videos(ctx, ids)
		skip := map[string]bool{}
		var unreadable *BatchItemsError
		if errors.As(err, &unreadable) {
			s.d.Log.Warn("curation: unreadable items in a video batch", "count", len(unreadable.IDs))
			for _, id := range unreadable.IDs {
				skip[id] = true
			}
		} else if err != nil {
			s.d.Log.Error("curation: video source failed", "err", err) // carries neither key nor URL
			return err
		}
		for _, x := range batch {
			if skip[x.youtubeID] {
				continue
			}
			stamped++
			m, ok := got[x.youtubeID]
			if ok {
				_, err = tx.Exec(ctx, `UPDATE videos SET title = $2, channel_id = $3, channel_title = $4,
					duration_seconds = $5, source_checked_at = $6 WHERE id = $1::uuid`,
					x.id, m.Title, m.ChannelID, m.ChannelTitle, int(m.Duration/time.Second), now)
			} else {
				_, err = tx.Exec(ctx, `UPDATE videos SET title = '', channel_id = '', channel_title = '',
					source_checked_at = $2 WHERE id = $1::uuid`, x.id, now)
				if err == nil {
					_, err = tx.Exec(ctx, `DELETE FROM video_thumbnails WHERE video_id = $1::uuid`, x.id)
				}
			}
			if err != nil {
				return err
			}
			if x.state == string(Approved) && (!ok || s.refusal(m) != "") {
				tag, err := tx.Exec(ctx, `UPDATE videos SET state = 'held', held_reason = $2, updated_at = $3
					WHERE id = $1::uuid AND state = 'approved'`, x.id, HeldByUnavailable, now)
				if err != nil {
					return err
				}
				held += int(tag.RowsAffected())
			}
		}
		return nil
	})
	if err != nil {
		return 0, 0, err
	}
	for range held {
		s.d.Audit.Record(ctx, "", audit.VideoHeld)
	}
	return len(batch), stamped, nil
}

// ExpireThumbnails deletes cached thumbnails older than sourceMaxAge; the
// lazy fill fetches them again on demand.
func (s *Service) ExpireThumbnails(ctx context.Context) error {
	_, err := s.d.Pool.Exec(ctx, `DELETE FROM video_thumbnails WHERE fetched_at < $1`, s.now().Add(-sourceMaxAge))
	return err
}
