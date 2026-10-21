package curation

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Metadata is what suggestion reads of a YouTube video.
type Metadata struct {
	ID           string
	Title        string
	ChannelID    string
	ChannelTitle string
	Duration     time.Duration
	MadeForKids  bool
	Embeddable   bool
	Live         string // snippet.liveBroadcastContent: "none", "live" or "upcoming"
}

// VideoSource reads videos' metadata. Video answers ErrVideoNotFound for
// an unknown ID; Videos leaves unknown IDs out of its map. Anything else
// that went wrong is an error wrapping ErrSourceUnavailable.
type VideoSource interface {
	Video(ctx context.Context, id string) (Metadata, error)
	Videos(ctx context.Context, ids []string) (map[string]Metadata, error)
}

// BatchItemsError reports items of a videos.list answer that could not be
// read; Videos returns it beside the map of the items that could.
type BatchItemsError struct{ IDs []string }

func (e *BatchItemsError) Error() string {
	return "curation: unreadable items in a videos.list answer"
}

func (e *BatchItemsError) Unwrap() error { return ErrSourceUnavailable }

const YouTubeBaseURL = "https://www.googleapis.com/youtube/v3/videos"

// YouTube calls the Data API's videos.list with a server-side key, the
// only outbound call of a suggestion. Its errors never carry the key or
// the URL.
type YouTube struct {
	Client  *http.Client
	BaseURL string
	Key     string
	Timeout time.Duration // 0 is 5 s
}

func (y YouTube) Videos(ctx context.Context, ids []string) (map[string]Metadata, error) {
	timeout := y.Timeout
	if timeout == 0 {
		timeout = 5 * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	q := url.Values{"part": {"snippet,contentDetails,status"}, "id": {strings.Join(ids, ",")}, "key": {y.Key}}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, y.BaseURL+"?"+q.Encode(), nil)
	if err != nil {
		return nil, ErrSourceUnavailable
	}
	resp, err := y.Client.Do(req)
	if err != nil {
		// The transport error carries the URL (and so the key) and the
		// host: say only what kind of failure it was.
		if errors.Is(err, context.DeadlineExceeded) {
			return nil, fmt.Errorf("%w: request timed out", ErrSourceUnavailable)
		}
		return nil, fmt.Errorf("%w: request failed", ErrSourceUnavailable)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: status %d", ErrSourceUnavailable, resp.StatusCode)
	}
	var body struct {
		Items []struct {
			ID      string `json:"id"`
			Snippet struct {
				Title                string `json:"title"`
				ChannelID            string `json:"channelId"`
				ChannelTitle         string `json:"channelTitle"`
				LiveBroadcastContent string `json:"liveBroadcastContent"`
			} `json:"snippet"`
			ContentDetails struct {
				Duration string `json:"duration"`
			} `json:"contentDetails"`
			Status struct {
				Embeddable  bool `json:"embeddable"`
				MadeForKids bool `json:"madeForKids"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&body); err != nil {
		return nil, errors.Join(ErrSourceUnavailable, err)
	}
	out := make(map[string]Metadata, len(body.Items))
	var skipped []string
	for _, it := range body.Items {
		d, err := ParseDuration(it.ContentDetails.Duration)
		if err != nil {
			skipped = append(skipped, it.ID)
			continue
		}
		out[it.ID] = Metadata{
			ID:           it.ID,
			Title:        it.Snippet.Title,
			ChannelID:    it.Snippet.ChannelID,
			ChannelTitle: it.Snippet.ChannelTitle,
			Duration:     d,
			MadeForKids:  it.Status.MadeForKids,
			Embeddable:   it.Status.Embeddable,
			Live:         it.Snippet.LiveBroadcastContent,
		}
	}
	if len(skipped) > 0 {
		return out, &BatchItemsError{IDs: skipped}
	}
	return out, nil
}

func (y YouTube) Video(ctx context.Context, id string) (Metadata, error) {
	got, err := y.Videos(ctx, []string{id})
	if err != nil {
		return Metadata{}, err // a BatchItemsError is ErrSourceUnavailable, not NotFound
	}
	m, ok := got[id]
	if !ok {
		return Metadata{}, ErrVideoNotFound
	}
	return m, nil
}

var isoDuration = regexp.MustCompile(`^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$`)

// ParseDuration reads the ISO 8601 durations videos.list returns
// (`PT2M17S`, `P1DT2H`, `P0D` for a live stream).
func ParseDuration(s string) (time.Duration, error) {
	m := isoDuration.FindStringSubmatch(s)
	if m == nil || strings.HasSuffix(s, "T") || m[1]+m[2]+m[3]+m[4] == "" {
		return 0, fmt.Errorf("curation: bad ISO 8601 duration %q", s)
	}
	var d time.Duration
	for i, unit := range []time.Duration{24 * time.Hour, time.Hour, time.Minute, time.Second} {
		if m[i+1] == "" {
			continue
		}
		n, err := strconv.ParseInt(m[i+1], 10, 64)
		if err != nil || n > math.MaxInt64/int64(unit) || time.Duration(n)*unit > math.MaxInt64-d {
			return 0, fmt.Errorf("curation: bad ISO 8601 duration %q", s)
		}
		d += time.Duration(n) * unit
	}
	return d, nil
}
