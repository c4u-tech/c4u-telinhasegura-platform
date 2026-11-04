package curation

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// SearchSource looks videos up by title words. Search answers YouTube video
// IDs in the source's order; a failure wraps ErrSearchUnavailable.
type SearchSource interface {
	Search(ctx context.Context, q string) ([]string, error)
}

const YouTubeSearchURL = "https://www.googleapis.com/youtube/v3/search"

// YouTubeSearch calls the Data API's search.list with a server-side key.
// Its errors never carry the key, the URL or the query.
type YouTubeSearch struct {
	Client  *http.Client
	BaseURL string
	Key     string
	Timeout time.Duration // 0 is 5 s
}

func (y YouTubeSearch) Search(ctx context.Context, q string) ([]string, error) {
	timeout := y.Timeout
	if timeout == 0 {
		timeout = 5 * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	params := url.Values{
		"part":              {"snippet"},
		"type":              {"video"},
		"safeSearch":        {"strict"},
		"videoEmbeddable":   {"true"},
		"regionCode":        {"BR"},
		"relevanceLanguage": {"pt"},
		"maxResults":        {"10"},
		"q":                 {q},
		"key":               {y.Key},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, y.BaseURL+"?"+params.Encode(), nil)
	if err != nil {
		return nil, ErrSearchUnavailable
	}
	// A redirect would carry the key to another host: take the first answer.
	client := http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	if y.Client != nil {
		client = *y.Client
		client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	}
	resp, err := client.Do(req)
	if err != nil {
		// The transport error carries the URL (and so the key and the
		// query): say only what kind of failure it was.
		if errors.Is(err, context.DeadlineExceeded) {
			return nil, fmt.Errorf("%w: request timed out", ErrSearchUnavailable)
		}
		return nil, fmt.Errorf("%w: request failed", ErrSearchUnavailable)
	}
	defer resp.Body.Close()
	body := io.LimitReader(resp.Body, 1<<20)
	if resp.StatusCode != http.StatusOK {
		if resp.StatusCode == http.StatusForbidden && searchQuotaSpent(body) {
			return nil, ErrSearchQuota
		}
		return nil, fmt.Errorf("%w: status %d", ErrSearchUnavailable, resp.StatusCode)
	}
	var out struct {
		Items []struct {
			ID struct {
				VideoID string `json:"videoId"`
			} `json:"id"`
		} `json:"items"`
	}
	if err := json.NewDecoder(body).Decode(&out); err != nil {
		return nil, fmt.Errorf("%w: unreadable answer", ErrSearchUnavailable)
	}
	ids := make([]string, 0, len(out.Items))
	for _, it := range out.Items {
		if videoID.MatchString(it.ID.VideoID) {
			ids = append(ids, it.ID.VideoID)
		}
	}
	return ids, nil
}

// searchQuotaSpent reads a 403 body for the reasons that mean the daily
// quota is gone, as opposed to a key that is refused.
func searchQuotaSpent(body io.Reader) bool {
	var e struct {
		Error struct {
			Errors []struct {
				Reason string `json:"reason"`
			} `json:"errors"`
		} `json:"error"`
	}
	if json.NewDecoder(body).Decode(&e) != nil {
		return false
	}
	for _, it := range e.Error.Errors {
		if it.Reason == "quotaExceeded" || it.Reason == "dailyLimitExceeded" {
			return true
		}
	}
	return false
}
