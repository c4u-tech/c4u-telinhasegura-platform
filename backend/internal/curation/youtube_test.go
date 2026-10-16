package curation_test

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

const apiKey = "AIza-test-key-never-logged"

// babyShark is a real videos.list response, trimmed.
const babyShark = `{
  "kind": "youtube#videoListResponse",
  "items": [{
    "kind": "youtube#video",
    "id": "dQw4w9WgXcQ",
    "snippet": {
      "publishedAt": "2016-06-17T00:00:00Z",
      "channelId": "UCcdwLMPsaU2ezNSJU1nFoBQ",
      "title": "Baby Shark Dance",
      "channelTitle": "Pinkfong Baby Shark - Kids' Songs & Stories",
      "liveBroadcastContent": "none"
    },
    "contentDetails": {"duration": "PT2M17S", "definition": "hd"},
    "status": {"uploadStatus": "processed", "privacyStatus": "public", "embeddable": true, "madeForKids": true}
  }],
  "pageInfo": {"totalResults": 1, "resultsPerPage": 1}
}`

func youTube(t *testing.T, h http.HandlerFunc) curation.YouTube {
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return curation.YouTube{Client: srv.Client(), BaseURL: srv.URL + "/youtube/v3/videos", Key: apiKey}
}

// answer checks the request is the fixed videos.list call, then answers.
func answer(t *testing.T, status int, body string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		if r.URL.Path != "/youtube/v3/videos" || q.Get("part") != "snippet,contentDetails,status" ||
			q.Get("id") != "dQw4w9WgXcQ" || q.Get("key") != apiKey {
			t.Errorf("request %s", r.URL)
		}
		w.WriteHeader(status)
		fmt.Fprint(w, body)
	}
}

func TestYouTubeReadsAVideo(t *testing.T) {
	m, err := youTube(t, answer(t, http.StatusOK, babyShark)).Video(context.Background(), "dQw4w9WgXcQ")
	if err != nil {
		t.Fatal(err)
	}
	want := curation.Metadata{
		ID: "dQw4w9WgXcQ", Title: "Baby Shark Dance", ChannelID: "UCcdwLMPsaU2ezNSJU1nFoBQ",
		ChannelTitle: "Pinkfong Baby Shark - Kids' Songs & Stories", Duration: 2*time.Minute + 17*time.Second,
		MadeForKids: true, Embeddable: true, Live: "none",
	}
	if m != want {
		t.Fatalf("got %+v", m)
	}
}

func TestYouTubeEmptyItemsIsNotFound(t *testing.T) {
	y := youTube(t, answer(t, http.StatusOK, `{"kind":"youtube#videoListResponse","items":[],"pageInfo":{"totalResults":0}}`))
	if _, err := y.Video(context.Background(), "dQw4w9WgXcQ"); !errors.Is(err, curation.ErrVideoNotFound) {
		t.Fatalf("got %v", err)
	}
}

func TestYouTubeFailuresAreUnavailable(t *testing.T) {
	quota := `{"error":{"code":403,"message":"You have exceeded your quota.","errors":[{"reason":"quotaExceeded"}]}}`
	slow := youTube(t, func(_ http.ResponseWriter, r *http.Request) { <-r.Context().Done() })
	slow.Timeout = 50 * time.Millisecond
	for name, y := range map[string]curation.YouTube{
		"quota":        youTube(t, answer(t, http.StatusForbidden, quota)),
		"garbled":      youTube(t, answer(t, http.StatusOK, `{"items": [`)),
		"bad duration": youTube(t, answer(t, http.StatusOK, strings.Replace(babyShark, "PT2M17S", "2 minutes", 1))),
		"timeout":      slow,
		"unreachable":  {Client: http.DefaultClient, BaseURL: "http://127.0.0.1:1/youtube/v3/videos", Key: apiKey},
	} {
		_, err := y.Video(context.Background(), "dQw4w9WgXcQ")
		if !errors.Is(err, curation.ErrSourceUnavailable) {
			t.Errorf("%s: %v", name, err)
			continue
		}
		for _, leak := range []string{apiKey, "key=", "/youtube/v3/videos", "http://", "127.0.0.1"} {
			if strings.Contains(err.Error(), leak) {
				t.Errorf("%s: the error carries %q: %v", name, leak, err)
			}
		}
	}
}

func TestYouTubeMapsEachFlagOnItsOwn(t *testing.T) {
	for name, tc := range map[string]struct {
		kids, embed string
		live        string
	}{
		"not for kids":   {"false", "true", "none"},
		"not embeddable": {"true", "false", "none"},
		"live":           {"true", "true", "live"},
		"upcoming":       {"true", "true", "upcoming"},
	} {
		body := strings.NewReplacer(`"embeddable": true`, `"embeddable": `+tc.embed,
			`"madeForKids": true`, `"madeForKids": `+tc.kids,
			`"liveBroadcastContent": "none"`, `"liveBroadcastContent": "`+tc.live+`"`).Replace(babyShark)
		m, err := youTube(t, answer(t, http.StatusOK, body)).Video(context.Background(), "dQw4w9WgXcQ")
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		want := curation.Metadata{
			ID: "dQw4w9WgXcQ", Title: "Baby Shark Dance", ChannelID: "UCcdwLMPsaU2ezNSJU1nFoBQ",
			ChannelTitle: "Pinkfong Baby Shark - Kids' Songs & Stories", Duration: 2*time.Minute + 17*time.Second,
			MadeForKids: tc.kids == "true", Embeddable: tc.embed == "true", Live: tc.live,
		}
		if m != want {
			t.Errorf("%s: got %+v", name, m)
		}
	}
}

func TestParseDuration(t *testing.T) {
	for in, want := range map[string]time.Duration{
		"PT2M17S":  2*time.Minute + 17*time.Second,
		"PT20M":    20 * time.Minute,
		"PT45S":    45 * time.Second,
		"PT1H2M3S": time.Hour + 2*time.Minute + 3*time.Second,
		"P1DT2H":   26 * time.Hour,
		"P0D":      0,
	} {
		if got, err := curation.ParseDuration(in); err != nil || got != want {
			t.Errorf("%s: %v %v", in, got, err)
		}
	}
	for _, in := range []string{"", "P", "PT", "P1DT", "2M", "PT2.5S", "PT-1S", "P1W", "PT99999999999999S", "P999999999999D", "PT9223372036854775807S", "P106751DT24H"} {
		if _, err := curation.ParseDuration(in); err == nil {
			t.Errorf("%q accepted", in)
		}
	}
}

func TestYouTubeVideosAsksOnceForABatch(t *testing.T) {
	var asked string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked = r.URL.Query().Get("id")
		_, _ = io.WriteString(w, `{"items":[{"id":"aaaaaaaaaaa","snippet":{"title":"A","channelId":"UC1","channelTitle":"C",
			"liveBroadcastContent":"none"},"contentDetails":{"duration":"PT1M"},"status":{"embeddable":true,"madeForKids":true}}]}`)
	}))
	defer srv.Close()
	y := curation.YouTube{Client: srv.Client(), BaseURL: srv.URL, Key: "k"}
	got, err := y.Videos(ctx, []string{"aaaaaaaaaaa", "bbbbbbbbbbb"})
	if err != nil {
		t.Fatal(err)
	}
	if asked != "aaaaaaaaaaa,bbbbbbbbbbb" || len(got) != 1 || got["aaaaaaaaaaa"].Duration != time.Minute {
		t.Fatalf("asked %q, got %v", asked, got)
	}
}

func TestYouTubeVideosSkipsAnUnreadableItem(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, `{"items":[
			{"id":"aaaaaaaaaaa","snippet":{"title":"A"},"contentDetails":{"duration":"PT1M"},"status":{}},
			{"id":"bbbbbbbbbbb","snippet":{"title":"B"},"contentDetails":{"duration":"PT"},"status":{}}]}`)
	}))
	defer srv.Close()
	y := curation.YouTube{Client: srv.Client(), BaseURL: srv.URL, Key: "k"}
	got, err := y.Videos(ctx, []string{"aaaaaaaaaaa", "bbbbbbbbbbb"})
	var bad *curation.BatchItemsError
	if !errors.As(err, &bad) || len(bad.IDs) != 1 || bad.IDs[0] != "bbbbbbbbbbb" || !errors.Is(err, curation.ErrSourceUnavailable) {
		t.Fatalf("err %v", err)
	}
	if len(got) != 1 || got["aaaaaaaaaaa"].Title != "A" {
		t.Fatalf("got %v", got)
	}
	if _, err := y.Video(ctx, "bbbbbbbbbbb"); !errors.Is(err, curation.ErrSourceUnavailable) {
		t.Fatalf("Video: %v", err)
	}
}
