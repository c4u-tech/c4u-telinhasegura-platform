package curation_test

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func (f *fixture) checkedAt(videoID string) *time.Time {
	f.t.Helper()
	var at *time.Time
	if err := f.pool.QueryRow(ctx, `SELECT source_checked_at FROM videos WHERE id = $1::uuid`, videoID).Scan(&at); err != nil {
		f.t.Fatal(err)
	}
	return at
}

func TestRefreshSources(t *testing.T) {
	f := newFixture(t)
	fresh := f.published("aaaaaaaaaaa", "bichos", family.Age5To8)
	refused := f.published("bbbbbbbbbbb", "bichos", family.Age5To8)
	gone := f.published("ccccccccccc", "bichos", family.Age5To8)
	recent := f.published("ddddddddddd", "bichos", family.Age5To8)
	f.exec(`UPDATE videos SET source_checked_at = $2 WHERE id = $1::uuid`, recent, f.now.Add(-24*24*time.Hour))
	f.exec(`INSERT INTO video_thumbnails (video_id, bytes, fetched_at) VALUES ($1::uuid, 'x', $2)`, gone, f.now)
	m := curationtest.Kids("aaaaaaaaaaa", "Novo título")
	f.source.Add(m)
	notKids := curationtest.Kids("bbbbbbbbbbb", "Agora não é para crianças")
	notKids.MadeForKids = false
	f.source.Add(notKids)

	if err := f.svc.RefreshSources(ctx); err != nil {
		t.Fatal(err)
	}
	var title, channel string
	var secs int
	f.pool.QueryRow(ctx, `SELECT title, channel_title, duration_seconds FROM videos WHERE id = $1::uuid`, fresh).Scan(&title, &channel, &secs)
	if title != "Novo título" || channel != "Canal Novo título" || secs != 300 || f.checkedAt(fresh) == nil {
		t.Fatalf("refreshed %q %q %d", title, channel, secs)
	}
	if s, why := f.state(refused); s != "held" || why != curation.HeldByUnavailable {
		t.Fatalf("refused: %s %s", s, why)
	}
	if s, why := f.state(gone); s != "held" || why != curation.HeldByUnavailable {
		t.Fatalf("gone: %s %s", s, why)
	}
	if n := f.count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND title = '' AND channel_id = '' AND channel_title = ''
		AND source_checked_at IS NOT NULL`, gone); n != 1 {
		t.Fatal("the gone video's data was kept")
	}
	if n := f.count(`SELECT count(*) FROM video_thumbnails WHERE video_id = $1::uuid`, gone); n != 0 {
		t.Fatal("the gone video's thumbnail was kept")
	}
	if f.audited(audit.VideoHeld) != 2 {
		t.Fatalf("held audited %d", f.audited(audit.VideoHeld))
	}
	for _, id := range f.source.Calls() {
		if id == "ddddddddddd" {
			t.Fatal("a video checked 24 days ago was checked again")
		}
	}
}

func TestRefreshSourcesWhileYouTubeIsDown(t *testing.T) {
	f := newFixture(t)
	v := f.published("aaaaaaaaaaa", "bichos", family.Age5To8)
	f.source.Err = fmt.Errorf("%w: status 500", curation.ErrSourceUnavailable)
	if err := f.svc.RefreshSources(ctx); err == nil {
		t.Fatal("no error")
	}
	if f.checkedAt(v) != nil {
		t.Fatal("stamped while YouTube was down")
	}
	if s, _ := f.state(v); s != "approved" {
		t.Fatal("changed while YouTube was down")
	}
	f.rebuild(func(d *curation.Deps) { d.Source = nil })
	if err := f.svc.RefreshSources(ctx); err != nil || f.checkedAt(v) != nil {
		t.Fatalf("without a key: %v", err)
	}
}

func TestRefreshSourcesBatchesOf50(t *testing.T) {
	f := newFixture(t)
	for i := range 120 {
		f.published(nthID(i), "bichos", family.Age5To8)
		f.source.Add(curationtest.Kids(nthID(i), "V"))
	}
	if err := f.svc.RefreshSources(ctx); err != nil {
		t.Fatal(err)
	}
	b := f.source.Batches()
	if len(b) != 3 || len(b[0]) != 50 || len(b[1]) != 50 || len(b[2]) != 20 {
		t.Fatalf("batches %d", len(b))
	}
}

func TestTwoSweepsNeverCheckTheSameVideo(t *testing.T) {
	f := newFixture(t)
	for i := range 60 {
		f.published(nthID(i), "bichos", family.Age5To8)
		f.source.Add(curationtest.Kids(nthID(i), "V"))
	}
	var wg sync.WaitGroup
	for range 2 {
		wg.Go(func() { _ = f.svc.RefreshSources(ctx) })
	}
	wg.Wait()
	if n := len(f.source.Calls()); n != 60 {
		t.Fatalf("%d checks for 60 videos", n)
	}
}

func TestExpireThumbnails(t *testing.T) {
	f := newFixture(t)
	old := f.published("aaaaaaaaaaa", "bichos", family.Age5To8)
	recent := f.published("bbbbbbbbbbb", "bichos", family.Age5To8)
	f.exec(`INSERT INTO video_thumbnails (video_id, bytes, fetched_at) VALUES ($1::uuid, 'x', $3), ($2::uuid, 'y', $4)`,
		old, recent, f.now.Add(-25*24*time.Hour-time.Minute), f.now.Add(-24*24*time.Hour))
	if err := f.svc.ExpireThumbnails(ctx); err != nil {
		t.Fatal(err)
	}
	if f.count(`SELECT count(*) FROM video_thumbnails WHERE video_id = $1::uuid`, old) != 0 ||
		f.count(`SELECT count(*) FROM video_thumbnails WHERE video_id = $1::uuid`, recent) != 1 {
		t.Fatal("expiry")
	}
}

func TestRefreshSourcesSkipsUnreadableItems(t *testing.T) {
	f := newFixture(t)
	a := f.published("aaaaaaaaaaa", "bichos", family.Age5To8)
	bad := f.published("bbbbbbbbbbb", "bichos", family.Age5To8)
	c := f.published("ccccccccccc", "bichos", family.Age5To8)
	f.source.Add(curationtest.Kids("aaaaaaaaaaa", "Novo A"))
	f.source.Add(curationtest.Kids("bbbbbbbbbbb", "Novo B"))
	f.source.Add(curationtest.Kids("ccccccccccc", "Novo C"))
	f.source.Unreadable = map[string]bool{"bbbbbbbbbbb": true}
	if err := f.svc.RefreshSources(ctx); err != nil {
		t.Fatal(err)
	}
	if f.checkedAt(a) == nil || f.checkedAt(c) == nil {
		t.Fatal("readable videos not stamped")
	}
	var title string
	f.pool.QueryRow(ctx, `SELECT title FROM videos WHERE id = $1::uuid`, bad).Scan(&title)
	if s, _ := f.state(bad); f.checkedAt(bad) != nil || s != "approved" || title == "" || title == "Novo B" {
		t.Fatalf("unreadable changed: %s %q", s, title)
	}
	done := make(chan error, 1)
	go func() { done <- f.svc.RefreshSources(ctx) }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("second sweep did not terminate")
	}
}
