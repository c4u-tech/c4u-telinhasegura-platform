package httpapi_test

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
)

type searchHit struct {
	YouTubeID       string  `json:"youtube_id"`
	Title           string  `json:"title"`
	ChannelTitle    string  `json:"channel_title"`
	DurationSeconds int     `json:"duration_seconds"`
	Suggestible     bool    `json:"suggestible"`
	Refusal         *string `json:"refusal"`
	State           *string `json:"state"`
}

func (a *api) find(tok mobileTokens, q string) resp {
	return a.do(http.MethodPost, "/v1/suggestions/search", map[string]string{"q": q}, bearer(tok)...)
}

func TestSearchOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	a.videos.Add(curationtest.Kids(ytID, "Baby Shark"))
	noKids := curationtest.Kids("nokids00000", "Adultos")
	noKids.MadeForKids = false
	a.videos.Add(noKids)
	a.search.Add("baby shark", ytID, "nokids00000")

	r := a.find(ana, "baby shark")
	if r.Code != http.StatusOK {
		t.Fatalf("search: %d %s", r.Code, r.Body)
	}
	var body struct {
		Results []searchHit `json:"results"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &body); err != nil || len(body.Results) != 2 {
		t.Fatalf("body %s: %v", r.Body, err)
	}
	if h := body.Results[0]; h.YouTubeID != ytID || h.Title != "Baby Shark" || h.ChannelTitle != "Canal Baby Shark" ||
		h.DurationSeconds != 300 || !h.Suggestible || h.Refusal != nil || h.State != nil {
		t.Fatalf("first %+v", h)
	}
	if h := body.Results[1]; h.Suggestible || h.Refusal == nil || *h.Refusal != "not_for_kids" || h.State != nil {
		t.Fatalf("second %+v", h)
	}
	if !json.Valid(r.Body.Bytes()) || !strings.Contains(r.Body.String(), `"refusal":null`) || !strings.Contains(r.Body.String(), `"state":null`) {
		t.Fatalf("null members missing: %s", r.Body)
	}

	a.suggest(ana, ytID)
	r = a.find(ana, "baby shark")
	_ = json.Unmarshal(r.Body.Bytes(), &body)
	if h := body.Results[0]; !h.Suggestible || h.State == nil || *h.State != "pending" {
		t.Fatalf("stored %+v", h)
	}
}

func TestSearchErrorsOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")

	if r := a.find(ana, "a"); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("short: %d %q", r.Code, r.problemCode())
	}
	for i := 0; i < 20; i++ {
		if r := a.find(ana, "baby shark"); r.Code != http.StatusOK {
			t.Fatalf("search %d: %d %s", i, r.Code, r.Body)
		}
	}
	if r := a.find(ana, "baby shark"); r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") == "" {
		t.Fatalf("21st: %d %q %q", r.Code, r.problemCode(), r.Header().Get("Retry-After"))
	}

	bia := a.familyOwner("bia@example.com")
	a.search.Err = curation.ErrSearchQuota
	r := a.find(bia, "peppa pig")
	secs, err := strconv.Atoi(r.Header().Get("Retry-After"))
	if r.Code != http.StatusServiceUnavailable || r.problemCode() != "search_unavailable" || err != nil || secs <= 0 {
		t.Fatalf("quota: %d %q %q", r.Code, r.problemCode(), r.Header().Get("Retry-After"))
	}

	// A quota error closes the day for everyone, so another failure needs
	// a fresh server to be seen on its own.
	b := newAPI(t)
	cai := b.familyOwner("cai@example.com")
	b.search.Err = errors.New("boom")
	r = b.find(cai, "peppa pig")
	if r.Code != http.StatusServiceUnavailable || r.problemCode() != "search_unavailable" || r.Header().Get("Retry-After") != "" {
		t.Fatalf("other: %d %q %q", r.Code, r.problemCode(), r.Header().Get("Retry-After"))
	}
}

func TestSearchIsGuardianOnly(t *testing.T) {
	a := newAPI(t)
	if r := a.do(http.MethodPost, "/v1/suggestions/search", map[string]string{"q": "baby shark"}); r.Code != http.StatusUnauthorized {
		t.Fatalf("search without session: %d", r.Code)
	}
	if r := a.do(http.MethodGet, "/v1/suggestions/thumbs/"+ytID, nil); r.Code != http.StatusUnauthorized {
		t.Fatalf("thumb without session: %d", r.Code)
	}
	tok, _ := a.lockedSession("ana@example.com")
	if r := a.find(tok, "baby shark"); r.Code != http.StatusForbidden || r.problemCode() != "kid_mode" {
		t.Fatalf("locked search: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/suggestions/thumbs/"+ytID, nil, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "kid_mode" {
		t.Fatalf("locked thumb: %d %q", r.Code, r.problemCode())
	}
}

func TestSearchThumbOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	path := "/v1/suggestions/thumbs/" + ytID
	if r := a.do(http.MethodGet, path, nil, bearer(ana)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("unknown: %d %q", r.Code, r.problemCode())
	}
	a.videos.Add(curationtest.Kids(ytID, "Baby Shark"))
	a.search.Add("baby shark", ytID)
	a.thumbs.Add(ytID, []byte("jpeg-bytes"))
	if r := a.find(ana, "baby shark"); r.Code != http.StatusOK {
		t.Fatalf("search: %d %s", r.Code, r.Body)
	}
	r := a.do(http.MethodGet, path, nil, bearer(ana)...)
	if r.Code != http.StatusOK || r.Header().Get("Content-Type") != "image/jpeg" ||
		r.Header().Get("Cache-Control") != "private, max-age=86400" || r.Body.String() != "jpeg-bytes" {
		t.Fatalf("thumb: %d %q %q %q", r.Code, r.Header().Get("Content-Type"), r.Header().Get("Cache-Control"), r.Body)
	}
}
