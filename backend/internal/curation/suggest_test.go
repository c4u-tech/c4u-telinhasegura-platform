package curation_test

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
)

const ytID = "dQw4w9WgXcQ"

func refusal(err error) string {
	var refused *curation.RefusedError
	if errors.As(err, &refused) {
		return refused.Reason
	}
	return ""
}

func TestSuggestNewVideo(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.source.Add(curationtest.Kids(ytID, "Baby Shark"))

	v, created, err := f.svc.Suggest(ctx, ana, "https://www.youtube.com/watch?v="+ytID)
	if err != nil || !created {
		t.Fatalf("suggest: %v %v", created, err)
	}
	if v.YouTubeID != ytID || v.State != curation.Pending || v.Round != 1 || v.Title != "Baby Shark" ||
		v.ChannelTitle != "Canal Baby Shark" || v.ChannelID != "UC"+ytID || v.DurationSeconds != 300 ||
		v.Theme != "" || v.MinAgeBand != "" || v.LastReviewedAt != nil || !v.CreatedAt.Equal(f.now) {
		t.Fatalf("video %+v", v)
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions WHERE video_id = $1::uuid AND account_id = $2::uuid`, v.ID, ana); n != 1 {
		t.Fatal("the suggestion was not recorded")
	}
	if calls := f.source.Calls(); len(calls) != 1 || calls[0] != ytID {
		t.Fatalf("YouTube calls %v", calls)
	}
}

func TestSuggestRefusals(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	cases := map[string]func(*curation.Metadata){
		curation.RefusedNotForKids:    func(m *curation.Metadata) { m.MadeForKids = false },
		curation.RefusedNotEmbeddable: func(m *curation.Metadata) { m.Embeddable = false },
		curation.RefusedLive:          func(m *curation.Metadata) { m.Live = "upcoming" },
		curation.RefusedTooLong:       func(m *curation.Metadata) { m.Duration = 20*time.Minute + time.Second },
	}
	i := 0
	for reason, change := range cases {
		id := fmt.Sprintf("refused%04d", i)
		i++
		m := curationtest.Kids(id, reason)
		change(&m)
		f.source.Add(m)
		if _, _, err := f.svc.Suggest(ctx, ana, "https://youtu.be/"+id); refusal(err) != reason {
			t.Errorf("%s: %v", reason, err)
		}
	}
	if _, _, err := f.svc.Suggest(ctx, ana, "https://youtu.be/missing0000"); refusal(err) != curation.RefusedNotFound {
		t.Errorf("unknown video: %v", err)
	}
	calls := len(f.source.Calls())
	if _, _, err := f.svc.Suggest(ctx, ana, "https://www.youtube.com/shorts/"+ytID); refusal(err) != curation.RefusedShorts {
		t.Errorf("shorts: %v", err)
	}
	if _, _, err := f.svc.Suggest(ctx, ana, "https://vimeo.com/1"); !errors.Is(err, curation.ErrInvalidLink) {
		t.Errorf("not YouTube: %v", err)
	}
	if len(f.source.Calls()) != calls {
		t.Fatal("a refused link reached YouTube")
	}
	if n := f.count(`SELECT (SELECT count(*) FROM videos) + (SELECT count(*) FROM video_suggestions)`); n != 0 {
		t.Fatalf("a refusal stored %d rows", n)
	}

	limit := curationtest.Kids("exactly20mi", "Vinte minutos")
	limit.Duration = 20 * time.Minute
	f.source.Add(limit)
	if _, created, err := f.svc.Suggest(ctx, ana, "https://youtu.be/exactly20mi"); err != nil || !created {
		t.Fatalf("a 20:00 video: %v %v", created, err)
	}
}

func TestSuggestExistingVideo(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	f.source.Add(curationtest.Kids(ytID, "Baby Shark"))
	first, _, err := f.svc.Suggest(ctx, ana, "https://www.youtube.com/watch?v="+ytID)
	if err != nil {
		t.Fatal(err)
	}

	for _, who := range []string{bia, bia, ana} {
		v, created, err := f.svc.Suggest(ctx, who, "https://youtu.be/"+ytID)
		if err != nil || created || v.ID != first.ID || v.State != curation.Pending {
			t.Fatalf("again: %+v %v %v", v, created, err)
		}
	}
	if calls := f.source.Calls(); len(calls) != 1 {
		t.Fatalf("a stored video reached YouTube again: %v", calls)
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions`); n != 2 {
		t.Fatalf("%d suggestions, want one per account", n)
	}

	f.exec(`UPDATE videos SET state = 'removed' WHERE id = $1::uuid`, first.ID)
	caio := f.account("caio@example.com")
	if _, _, err := f.svc.Suggest(ctx, caio, "https://youtu.be/"+ytID); refusal(err) != curation.RefusedRemoved {
		t.Fatalf("a removed video: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions WHERE account_id = $1::uuid`, caio); n != 0 {
		t.Fatal("a refused suggestion was recorded")
	}
}

func TestSuggestSameVideoConcurrently(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.source.Add(curationtest.Kids(ytID, "Baby Shark"))
	// Another guardian's suggestion of the same video commits while ana's
	// waits on YouTube.
	f.source.OnCall = func() {
		f.exec(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, created_at, updated_at)
			VALUES ($1, 'Baby Shark', 'UC1', 'Canal', 300, 'pending', $2, $2)`, ytID, f.now)
	}
	v, created, err := f.svc.Suggest(ctx, ana, "https://youtu.be/"+ytID)
	if err != nil || created || v.YouTubeID != ytID {
		t.Fatalf("suggest: %+v %v %v", v, created, err)
	}
	if n := f.count(`SELECT count(*) FROM videos`); n != 1 {
		t.Fatalf("%d videos", n)
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions WHERE account_id = $1::uuid AND video_id = $2::uuid`, ana, v.ID); n != 1 {
		t.Fatal("the suggestion was not attached to the existing video")
	}
}

func TestSuggestWhileTheSourceIsUnavailable(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	link := "https://www.youtube.com/watch?v=" + ytID

	f.source.Err = errors.New("boom")
	if _, _, err := f.svc.Suggest(ctx, ana, link); !errors.Is(err, curation.ErrSourceUnavailable) {
		t.Fatalf("source down: %v", err)
	}
	if !strings.Contains(f.logs.String(), "boom") {
		t.Fatal("the failure was not logged")
	}
	if strings.Contains(f.logs.String(), "youtube.com") || strings.Contains(f.logs.String(), ytID) {
		t.Fatalf("the log carries the link: %s", f.logs)
	}
	if n := f.count(`SELECT (SELECT count(*) FROM videos) + (SELECT count(*) FROM video_suggestions)`); n != 0 {
		t.Fatalf("stored %d rows while unavailable", n)
	}

	stored := f.video("stored00000")
	f.rebuild(func(d *curation.Deps) { d.Source = nil }) // YOUTUBE_API_KEY empty
	calls := len(f.source.Calls())
	if _, _, err := f.svc.Suggest(ctx, bia, link); !errors.Is(err, curation.ErrSourceUnavailable) {
		t.Fatalf("a new video without the key: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM videos WHERE youtube_id = $1`, ytID); n != 0 {
		t.Fatal("a new video was stored without the key")
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions`); n != 0 {
		t.Fatalf("%d suggestions stored without the key", n)
	}
	// What needs no YouTube call is answered without the key.
	if _, _, err := f.svc.Suggest(ctx, bia, "https://www.youtube.com/shorts/"+ytID); refusal(err) != curation.RefusedShorts {
		t.Fatalf("a Shorts link without the key: %v", err)
	}
	if _, _, err := f.svc.Suggest(ctx, bia, "https://vimeo.com/1"); !errors.Is(err, curation.ErrInvalidLink) {
		t.Fatalf("not YouTube, without the key: %v", err)
	}
	v, created, err := f.svc.Suggest(ctx, bia, "https://youtu.be/stored00000")
	if err != nil || created || v.ID != stored {
		t.Fatalf("a stored video without the key: %+v %v %v", v, created, err)
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions WHERE account_id = $1::uuid AND video_id = $2::uuid`, bia, stored); n != 1 {
		t.Fatal("the stored video's suggestion was not recorded without the key")
	}
	if len(f.source.Calls()) != calls {
		t.Fatal("a source was called while the key is empty")
	}
}

func TestSuggestionLimit(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	cur := f.curator("bia@example.com", curation.MaePai)
	start := f.now
	f.source.Add(curationtest.Kids(ytID, "Baby Shark"))
	// Refused calls spend the budget too: it protects the YouTube quota.
	for i, link := range []string{
		"https://vimeo.com/1", "https://www.youtube.com/shorts/" + ytID, "https://youtu.be/missing0000",
		"https://vimeo.com/2", "https://vimeo.com/3", "https://vimeo.com/4", "https://vimeo.com/5",
		"https://vimeo.com/6", "https://vimeo.com/7", "https://vimeo.com/8",
	} {
		if _, _, err := f.svc.Suggest(ctx, ana, link); err == nil {
			t.Fatalf("call %d (%s) was accepted", i+1, link)
		}
		f.now = f.now.Add(time.Minute)
	}
	var throttled *curation.ThrottledError
	if _, _, err := f.svc.Suggest(ctx, ana, "https://youtu.be/"+ytID); !errors.As(err, &throttled) ||
		throttled.RetryAfter != start.Add(24*time.Hour).Sub(f.now) {
		t.Fatalf("eleventh call: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions`); n != 0 {
		t.Fatal("a throttled call stored a suggestion")
	}
	for i := range 12 {
		id := fmt.Sprintf("video%06d", i)
		f.source.Add(curationtest.Kids(id, id))
		if _, _, err := f.svc.Suggest(ctx, cur, "https://youtu.be/"+id); err != nil {
			t.Fatalf("a curator was limited on call %d: %v", i+1, err)
		}
	}
	f.now = start.Add(24 * time.Hour)
	if _, created, err := f.svc.Suggest(ctx, ana, "https://youtu.be/"+ytID); err != nil || !created {
		t.Fatalf("after 24 hours: %v %v", created, err)
	}
}

func TestSuggestions(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	for i, who := range []string{ana, bia, ana} {
		id := fmt.Sprintf("video%06d", i)
		f.source.Add(curationtest.Kids(id, id))
		if _, _, err := f.svc.Suggest(ctx, who, "https://youtu.be/"+id); err != nil {
			t.Fatal(err)
		}
		f.now = f.now.Add(time.Minute)
	}
	list, err := f.svc.Suggestions(ctx, ana)
	if err != nil || len(list) != 2 {
		t.Fatalf("list %+v %v", list, err)
	}
	if list[0].Video.YouTubeID != "video000002" || list[1].Video.YouTubeID != "video000000" ||
		list[0].Video.State != curation.Pending || !list[1].SuggestedAt.Before(list[0].SuggestedAt) {
		t.Fatalf("order or fields %+v", list)
	}
	if list, err := f.svc.Suggestions(ctx, f.account("caio@example.com")); err != nil || list == nil || len(list) != 0 {
		t.Fatalf("none: %+v %v", list, err)
	}
}
