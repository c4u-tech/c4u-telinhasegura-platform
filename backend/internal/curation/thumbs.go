package curation

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

// ThumbSource fetches a video's thumbnail. Any failure is an error
// wrapping ErrThumbnailUnavailable, without the URL.
type ThumbSource interface {
	Thumbnail(ctx context.Context, youtubeID string) ([]byte, error)
}

const (
	ThumbBaseURL  = "https://i.ytimg.com/vi/"
	maxThumbBytes = 256 << 10
)

// YouTubeThumbs reads hqdefault.jpg from YouTube's image host, without a
// key. It never follows a redirect, whatever the client does: a redirect
// answers as a failure.
type YouTubeThumbs struct {
	Client  *http.Client
	BaseURL string
	Timeout time.Duration // 0 is 5 s
}

func (y YouTubeThumbs) Thumbnail(ctx context.Context, youtubeID string) ([]byte, error) {
	if !videoID.MatchString(youtubeID) { // the path is built only from a valid ID
		return nil, fmt.Errorf("%w: malformed id", ErrThumbnailUnavailable)
	}
	timeout := y.Timeout
	if timeout == 0 {
		timeout = 5 * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, y.BaseURL+youtubeID+"/hqdefault.jpg", nil)
	if err != nil {
		return nil, ErrThumbnailUnavailable
	}
	base := y.Client
	if base == nil {
		base = http.DefaultClient
	}
	noRedirect := *base // a copy: the caller's client stays as it is
	noRedirect.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, err := noRedirect.Do(req)
	if err != nil {
		// The transport error carries the URL: say only what kind of
		// failure it was.
		if errors.Is(err, context.DeadlineExceeded) {
			return nil, fmt.Errorf("%w: request timed out", ErrThumbnailUnavailable)
		}
		return nil, fmt.Errorf("%w: request failed", ErrThumbnailUnavailable)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: status %d", ErrThumbnailUnavailable, resp.StatusCode)
	}
	if mt, _, err := mime.ParseMediaType(resp.Header.Get("Content-Type")); err != nil || mt != "image/jpeg" {
		return nil, fmt.Errorf("%w: not a JPEG", ErrThumbnailUnavailable)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxThumbBytes+1))
	switch {
	case err != nil:
		return nil, fmt.Errorf("%w: body read failed", ErrThumbnailUnavailable)
	case len(body) == 0:
		return nil, fmt.Errorf("%w: empty body", ErrThumbnailUnavailable)
	case len(body) > maxThumbBytes:
		return nil, fmt.Errorf("%w: body over %d bytes", ErrThumbnailUnavailable, maxThumbBytes)
	}
	return body, nil
}

// ChildThumbnail serves the thumbnail of a video the child may see.
func (s *Service) ChildThumbnail(ctx context.Context, c Child, videoID string) ([]byte, error) {
	v, err := s.eligibleVideo(ctx, c, videoID)
	if err != nil {
		return nil, err
	}
	return s.thumbnail(ctx, v)
}

// FamilyThumbnail serves a guardian the thumbnail of an approved or held
// video; any other is ErrNotFound.
func (s *Service) FamilyThumbnail(ctx context.Context, videoID string) ([]byte, error) {
	if !validID(videoID) {
		return nil, ErrNotFound
	}
	v, err := scanVideo(s.d.Pool.QueryRow(ctx, `SELECT `+videoCols+` FROM videos v
		WHERE v.id = $1::uuid AND v.state IN ('approved', 'held')`, videoID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return s.thumbnail(ctx, v)
}

// thumbnail reads the cache, else fetches and stores a success only, so
// a failure is tried again on the next request.
// Concurrent first requests may each fetch; ON CONFLICT keeps one row.
func (s *Service) thumbnail(ctx context.Context, v Video) ([]byte, error) {
	var b []byte
	err := s.d.Pool.QueryRow(ctx, `SELECT bytes FROM video_thumbnails WHERE video_id = $1::uuid`, v.ID).Scan(&b)
	if err == nil {
		return b, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}
	if b, err = s.d.Thumbs.Thumbnail(ctx, v.YouTubeID); err != nil {
		// The source's errors carry no URL.
		s.d.Log.Warn("curation: thumbnail fetch failed", "video", v.ID, "err", err)
		return nil, ErrThumbnailUnavailable
	}
	if _, err := s.d.Pool.Exec(ctx, `INSERT INTO video_thumbnails (video_id, bytes, fetched_at) VALUES ($1::uuid, $2, $3)
		ON CONFLICT (video_id) DO NOTHING`, v.ID, b, s.now()); err != nil {
		return nil, err
	}
	return b, nil
}
