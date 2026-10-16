package curation

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Suggestion is a video the account suggested.
type Suggestion struct {
	Video       Video
	SuggestedAt time.Time
}

// Suggest records the account's suggestion of a YouTube link.
// created reports a video new to the catalogue (201), as against one
// already in it (200). The checks run in the order of the plan's Global
// Constraints; nothing is stored unless all pass.
func (s *Service) Suggest(ctx context.Context, accountID, link string) (Video, bool, error) {
	if err := s.checkSuggestionLimit(ctx, accountID); err != nil {
		return Video{}, false, err
	}
	id, err := ParseLink(link)
	if err != nil {
		return Video{}, false, err
	}
	_, err = videoByYouTubeID(ctx, s.d.Pool, id)
	switch {
	case err == nil:
		// Stored: no YouTube call, so no key needed.
		return s.record(ctx, accountID, id, nil)
	case !errors.Is(err, pgx.ErrNoRows):
		return Video{}, false, err
	}
	if s.d.Source == nil {
		return Video{}, false, ErrSourceUnavailable // YOUTUBE_API_KEY is empty
	}
	m, err := s.d.Source.Video(ctx, id)
	if errors.Is(err, ErrVideoNotFound) {
		return Video{}, false, &RefusedError{Reason: RefusedNotFound}
	}
	if err != nil {
		// The source's errors carry neither the key nor the URL.
		s.d.Log.Error("curation: video source failed", "err", err)
		return Video{}, false, ErrSourceUnavailable
	}
	if reason := s.refusal(m); reason != "" {
		return Video{}, false, &RefusedError{Reason: reason}
	}
	return s.record(ctx, accountID, id, &m)
}

// record stores the account's suggestion of the video with that YouTube
// ID, once per account. A non-nil m first inserts the video; if another
// suggestion of it committed while this one waited on YouTube, the insert
// does nothing and the suggestion attaches to the stored video.
// created reports that this call inserted it.
func (s *Service) record(ctx context.Context, accountID, youtubeID string, m *Metadata) (v Video, created bool, err error) {
	now := s.now()
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		if m != nil {
			tag, err := tx.Exec(ctx, `INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds,
				state, round, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, 'pending', 1, $6, $6)
				ON CONFLICT (youtube_id) DO NOTHING`,
				youtubeID, m.Title, m.ChannelID, m.ChannelTitle, int(m.Duration/time.Second), now)
			if err != nil {
				return err
			}
			created = tag.RowsAffected() == 1
		}
		// FOR SHARE: an admin's concurrent removal waits for this
		// suggestion, or this one sees the video removed.
		if v, err = scanVideo(tx.QueryRow(ctx, `SELECT `+videoCols+` FROM videos v WHERE v.youtube_id = $1 FOR SHARE OF v`,
			youtubeID)); err != nil {
			return err
		}
		if v.State == Removed {
			return &RefusedError{Reason: RefusedRemoved}
		}
		_, err = tx.Exec(ctx, `INSERT INTO video_suggestions (video_id, account_id, suggested_at)
			VALUES ($1::uuid, $2::uuid, $3) ON CONFLICT DO NOTHING`, v.ID, accountID, now)
		return err
	})
	if err != nil {
		return Video{}, false, err
	}
	return v, created, nil
}

func videoByYouTubeID(ctx context.Context, q querier, youtubeID string) (Video, error) {
	return scanVideo(q.QueryRow(ctx, `SELECT `+videoCols+` FROM videos v WHERE v.youtube_id = $1`, youtubeID))
}

// Suggestions lists the account's suggestions, newest first.
func (s *Service) Suggestions(ctx context.Context, accountID string) ([]Suggestion, error) {
	rows, err := s.d.Pool.Query(ctx, `SELECT `+videoCols+`, s.suggested_at
		FROM video_suggestions s JOIN videos v ON v.id = s.video_id
		WHERE s.account_id = $1::uuid ORDER BY s.suggested_at DESC, v.id`, accountID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Suggestion, error) {
		var x Suggestion
		var err error
		x.Video, err = scanVideo(r, &x.SuggestedAt)
		x.SuggestedAt = x.SuggestedAt.UTC()
		return x, err
	})
}

// refusal is the first refusal rule the video breaks, or "".
func (s *Service) refusal(m Metadata) string {
	switch {
	case !m.MadeForKids:
		return RefusedNotForKids
	case !m.Embeddable:
		return RefusedNotEmbeddable
	case m.Live != "none":
		return RefusedLive
	case m.Duration > s.d.MaxDuration:
		return RefusedTooLong
	}
	return ""
}

// checkSuggestionLimit spends one of a non-curator's 10 suggestion calls
// per 24 hours, before anything else, so a refused link spends it too and
// the budget protects the YouTube quota. Curators are not limited.
func (s *Service) checkSuggestionLimit(ctx context.Context, accountID string) error {
	curator, err := s.isCurator(ctx, accountID)
	if err != nil || curator {
		return err
	}
	if ok, wait := s.d.SuggestLimiter.Allow(accountID); !ok {
		return &ThrottledError{RetryAfter: wait}
	}
	return nil
}

// isCurator is the read seam's suggestion-limit read: curation
// reads platform_roles, staff writes it.
func (s *Service) isCurator(ctx context.Context, accountID string) (bool, error) {
	var ok bool
	err := s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM platform_roles WHERE account_id = $1::uuid AND role = 'curator')`,
		accountID).Scan(&ok)
	return ok, err
}
