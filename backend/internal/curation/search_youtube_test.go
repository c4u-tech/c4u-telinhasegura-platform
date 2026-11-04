package curation_test

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

func youTubeSearch(t *testing.T, h http.HandlerFunc) curation.YouTubeSearch {
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return curation.YouTubeSearch{Client: srv.Client(), BaseURL: srv.URL + "/youtube/v3/search", Key: apiKey}
}

func TestYouTubeSearchSendsTheFixedParameters(t *testing.T) {
	s := youTubeSearch(t, func(w http.ResponseWriter, r *http.Request) {
		want := url.Values{
			"part": {"snippet"}, "type": {"video"}, "safeSearch": {"strict"},
			"videoEmbeddable": {"true"}, "regionCode": {"BR"}, "relevanceLanguage": {"pt"},
			"maxResults": {"10"}, "q": {"baby shark"}, "key": {apiKey},
		}
		got := r.URL.Query()
		if !strings.HasSuffix(r.URL.Path, "/search") || len(got) != len(want) {
			t.Errorf("request %s", r.URL)
		}
		for k, v := range want {
			if got.Get(k) != v[0] {
				t.Errorf("%s = %q, want %q", k, got.Get(k), v[0])
			}
		}
		if got.Has("pageToken") {
			t.Error("pageToken sent")
		}
		fmt.Fprint(w, `{"items":[
			{"id":{"kind":"youtube#video","videoId":"aaaaaaaaaaa"}},
			{"id":{"videoId":"bbbbbbbbbbb"}}]}`)
	})
	ids, err := s.Search(context.Background(), "baby shark")
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(ids, ","); got != "aaaaaaaaaaa,bbbbbbbbbbb" {
		t.Errorf("ids = %v", ids)
	}
}

func TestYouTubeSearchSkipsNonVideoIDs(t *testing.T) {
	s := youTubeSearch(t, func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"items":[
			{"id":{"kind":"youtube#channel","channelId":"UCcdwLMPsaU2ezNSJU1nFoBQ"}},
			{"id":{"videoId":""}},
			{"id":{"videoId":"short"}},
			{"id":{"videoId":"aaaaaaaaaaa/../x"}},
			{"id":{"videoId":"ccccccccccc"}}]}`)
	})
	ids, err := s.Search(context.Background(), "x")
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 1 || ids[0] != "ccccccccccc" {
		t.Errorf("ids = %v", ids)
	}
}

func TestYouTubeSearchQuotaErrors(t *testing.T) {
	for _, tc := range []struct {
		reason string
		quota  bool
	}{{"quotaExceeded", true}, {"dailyLimitExceeded", true}, {"forbidden", false}} {
		t.Run(tc.reason, func(t *testing.T) {
			s := youTubeSearch(t, func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusForbidden)
				fmt.Fprintf(w, `{"error":{"errors":[{"reason":%q}]}}`, tc.reason)
			})
			_, err := s.Search(context.Background(), "x")
			if !errors.Is(err, curation.ErrSearchUnavailable) {
				t.Fatalf("err = %v", err)
			}
			if got := errors.Is(err, curation.ErrSearchQuota); got != tc.quota {
				t.Errorf("quota = %v, want %v", got, tc.quota)
			}
		})
	}
}

func TestYouTubeSearchErrorsCarryNoSecrets(t *testing.T) {
	for name, h := range map[string]http.HandlerFunc{
		"500": func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusInternalServerError) },
		"timeout": func(w http.ResponseWriter, r *http.Request) {
			select {
			case <-r.Context().Done():
			case <-time.After(2 * time.Second):
			}
		},
		"redirect": func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, "http://elsewhere.invalid/x", http.StatusFound)
		},
		"bad body": func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "not json") },
	} {
		t.Run(name, func(t *testing.T) {
			srv := httptest.NewServer(h)
			t.Cleanup(srv.Close)
			s := curation.YouTubeSearch{Client: srv.Client(), BaseURL: srv.URL + "/youtube/v3/search", Key: apiKey, Timeout: 50 * time.Millisecond}
			_, err := s.Search(context.Background(), "baby shark")
			if !errors.Is(err, curation.ErrSearchUnavailable) {
				t.Fatalf("err = %v", err)
			}
			for _, secret := range []string{apiKey, srv.URL, "baby"} {
				if strings.Contains(err.Error(), secret) {
					t.Errorf("error %q leaks %q", err, secret)
				}
			}
		})
	}
}
