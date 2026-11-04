package curation

import (
	"context"
	"errors"
	"strings"
	"unicode/utf8"
)

// SearchResult is a YouTube video a search found, marked for the guardian:
// Refusal is the reason it cannot be suggested ("" when it can), State its
// place in the catalogue ("" when it is not stored).
type SearchResult struct {
	Metadata
	Refusal string
	State   State
}

// Search looks YouTube up by title words for videos the account could
// suggest. The query is what a person typed, so it is never stored, logged
// or put in an error. The cheapest checks run first: the query, the
// account's limit, the shared cache, the day's budget, and only then
// YouTube. The catalogue state is read fresh on every answer, cached or not.
func (s *Service) Search(ctx context.Context, accountID, q string) ([]SearchResult, error) {
	q, ok := normalizeQuery(q)
	if !ok {
		return nil, ErrValidation
	}
	if err := s.checkSearchLimit(ctx, accountID); err != nil {
		return nil, err
	}
	key := strings.ToLower(q)
	hits, ok := s.search.get(key)
	if !ok {
		var err error
		if hits, err = s.searchYouTube(ctx, q); err != nil {
			return nil, err
		}
		s.search.put(key, hits)
	}
	return s.markHits(ctx, hits)
}

// normalizeQuery trims q and collapses its inner whitespace to one space;
// ok is false unless the result is valid UTF-8 of 2 to 100 characters.
func normalizeQuery(q string) (string, bool) {
	if !utf8.ValidString(q) {
		return "", false
	}
	q = strings.Join(strings.Fields(q), " ")
	n := utf8.RuneCountInString(q)
	return q, n >= 2 && n <= 100
}

// checkSearchLimit spends one of a non-curator's searches, cache hits
// included, so the limit does not tell a cached query from a new one.
// Curators are not limited.
func (s *Service) checkSearchLimit(ctx context.Context, accountID string) error {
	curator, err := s.isCurator(ctx, accountID)
	if err != nil || curator {
		return err
	}
	if ok, wait := s.d.SearchLimiter.Allow(accountID); !ok {
		return &ThrottledError{RetryAfter: wait}
	}
	return nil
}

// searchYouTube asks search.list for q, within the day's budget, then
// videos.list for the hits' metadata. It answers the hits videos.list
// knows, in the search's order. Failures are logged by their error alone:
// the errors carry neither the key, the URL nor the query.
func (s *Service) searchYouTube(ctx context.Context, q string) ([]Metadata, error) {
	if s.d.Search == nil || s.d.Source == nil {
		return nil, &SearchUnavailableError{} // YOUTUBE_API_KEY is empty
	}
	if ok, wait := s.d.SearchBudget.Take(); !ok {
		return nil, &SearchUnavailableError{RetryAfter: wait}
	}
	ids, err := s.d.Search.Search(ctx, q)
	if err != nil {
		s.d.Log.Error("curation: search source failed", "err", err)
		if errors.Is(err, ErrSearchQuota) {
			// YouTube's own quota is spent: ask no more until it renews.
			return nil, &SearchUnavailableError{RetryAfter: s.d.SearchBudget.Exhaust()}
		}
		return nil, &SearchUnavailableError{}
	}
	hits := []Metadata{}
	if len(ids) == 0 {
		return hits, nil
	}
	got, err := s.d.Source.Videos(ctx, ids)
	var unreadable *BatchItemsError
	if errors.As(err, &unreadable) {
		// The readable items still answer; the rest are left out.
		s.d.Log.Warn("curation: search results partly unreadable", "err", err)
	} else if err != nil {
		s.d.Log.Error("curation: video source failed", "err", err)
		return nil, &SearchUnavailableError{}
	}
	for _, id := range ids {
		if m, ok := got[id]; ok {
			hits = append(hits, m)
		}
	}
	return hits, nil
}

// markHits marks each hit with its refusal and its stored state, read now.
// A stored video that is not removed can be suggested whatever YouTube
// says of it, as a suggestion of a stored video does not ask YouTube.
func (s *Service) markHits(ctx context.Context, hits []Metadata) ([]SearchResult, error) {
	out := make([]SearchResult, 0, len(hits))
	if len(hits) == 0 {
		return out, nil
	}
	ids := make([]string, len(hits))
	for i, m := range hits {
		ids[i] = m.ID
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT youtube_id, state FROM videos WHERE youtube_id = ANY($1)`, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	states := map[string]State{}
	for rows.Next() {
		var id, state string
		if err := rows.Scan(&id, &state); err != nil {
			return nil, err
		}
		states[id] = State(state)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for _, m := range hits {
		r := SearchResult{Metadata: m, State: states[m.ID]}
		switch r.State {
		case "":
			r.Refusal = s.refusal(m)
		case Removed:
			r.Refusal = RefusedRemoved
		}
		out = append(out, r)
	}
	return out, nil
}

// SearchThumbnail serves the thumbnail of a video a live search answer
// holds, fetched each time and never stored: a search hit is not in the
// catalogue. Any other ID is ErrNotFound, so the route cannot fetch
// arbitrary images.
func (s *Service) SearchThumbnail(ctx context.Context, youtubeID string) ([]byte, error) {
	if !s.search.has(youtubeID) {
		return nil, ErrNotFound
	}
	b, err := s.d.Thumbs.Thumbnail(ctx, youtubeID)
	if err != nil {
		// The source's errors carry no URL.
		s.d.Log.Warn("curation: search thumbnail fetch failed", "err", err)
		return nil, ErrThumbnailUnavailable
	}
	return b, nil
}
