package curation_test

import (
	"bytes"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
)

// nextPacificMidnight is the wait from the fixture's clock to the next
// midnight in Los Angeles, when YouTube's quota day turns.
func (f *fixture) nextPacificMidnight() time.Duration {
	now := f.now.In(losAngeles)
	y, m, d := now.Date()
	return time.Date(y, m, d+1, 0, 0, 0, 0, losAngeles).Sub(now)
}

func (f *fixture) find(accountID, q string) []curation.SearchResult {
	f.t.Helper()
	got, err := f.svc.Search(ctx, accountID, q)
	if err != nil {
		f.t.Fatalf("search %q: %v", q, err)
	}
	return got
}

func resultIDs(rs []curation.SearchResult) []string {
	ids := []string{}
	for _, r := range rs {
		ids = append(ids, r.ID)
	}
	return ids
}

func TestSearchMarksEachHit(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	notForKids := curationtest.Kids("n1", "Não infantil")
	notForKids.MadeForKids = false
	live := curationtest.Kids("l1", "Ao vivo")
	live.Live = "live"
	long := curationtest.Kids("t1", "Longo")
	long.Duration = 45*time.Minute + time.Second
	notEmbeddable := curationtest.Kids("e1", "Sem incorporar")
	notEmbeddable.Embeddable = false
	videos := []curation.Metadata{curationtest.Kids("k1", "Baby Shark"), notForKids, live, long, notEmbeddable}
	for _, m := range videos {
		f.source.Add(m)
	}
	f.search.Add("baby shark", "k1", "n1", "l1", "t1", "e1", "gone")

	got := f.find(ana, "baby shark")

	if ids := resultIDs(got); !slices.Equal(ids, []string{"k1", "n1", "l1", "t1", "e1"}) {
		t.Fatalf("results: %v", ids)
	}
	refusals := []string{"", curation.RefusedNotForKids, curation.RefusedLive, curation.RefusedTooLong, curation.RefusedNotEmbeddable}
	for i, r := range got {
		if r.Refusal != refusals[i] || r.State != "" || r.Metadata != videos[i] {
			t.Errorf("result %d: %+v", i, r)
		}
	}
	if b := f.source.Batches(); len(b) != 1 || !slices.Equal(b[0], []string{"k1", "n1", "l1", "t1", "e1", "gone"}) {
		t.Fatalf("videos.list batches: %v", b)
	}
}

func TestSearchWithNoHits(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")

	if got := f.find(ana, "nada"); got == nil || len(got) != 0 {
		t.Fatalf("results: %#v", got)
	}
	if got := f.find(ana, "nada"); len(got) != 0 {
		t.Fatalf("second results: %v", got)
	}
	if n := len(f.source.Batches()); n != 0 {
		t.Fatalf("%d videos.list calls for no hits", n)
	}
	if c := f.search.Calls(); len(c) != 1 {
		t.Fatalf("the empty answer was not cached: %v", c)
	}
}

func TestSearchShowsTheCatalogueState(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	notForKids := curationtest.Kids("n1", "Não infantil")
	notForKids.MadeForKids = false
	f.source.Add(curationtest.Kids("k1", "Baby Shark"))
	f.source.Add(notForKids)
	f.source.Add(curationtest.Kids("r1", "Removido"))
	f.search.Add("baby shark", "k1", "n1", "r1")
	f.published("k1", "bichos", family.AgeUpTo4)
	f.video("n1")
	f.exec(`UPDATE videos SET state = 'removed' WHERE id = $1::uuid`, f.video("r1"))

	got := f.find(ana, "baby shark")

	want := []struct {
		refusal string
		state   curation.State
	}{{"", curation.Approved}, {"", curation.Pending}, {curation.RefusedRemoved, curation.Removed}}
	if len(got) != len(want) {
		t.Fatalf("results: %v", resultIDs(got))
	}
	for i, w := range want {
		if got[i].Refusal != w.refusal || got[i].State != w.state {
			t.Errorf("result %s: refusal %q, state %q", got[i].ID, got[i].Refusal, got[i].State)
		}
	}
}

func TestSearchValidatesTheQuery(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	for _, q := range []string{"", "   ", "a", " \t a \n ", strings.Repeat("á", 101), "\xff\xfe"} {
		if _, err := f.svc.Search(ctx, ana, q); !errors.Is(err, curation.ErrValidation) {
			t.Errorf("%q: %v", q, err)
		}
	}
	if c := f.search.Calls(); len(c) != 0 {
		t.Fatalf("an invalid query reached the source: %v", c)
	}

	for _, q := range []string{"ão", "  oi  ", "baby \t  shark", strings.Repeat("á", 100)} {
		f.find(ana, q)
	}
	if c := f.search.Calls(); !slices.Equal(c, []string{"ão", "oi", "baby shark", strings.Repeat("á", 100)}) {
		t.Fatalf("the source received %q", c)
	}

	// The invalid queries spent nothing: 16 more valid searches pass.
	for i := range 16 {
		f.find(ana, fmt.Sprintf("busca %d", i))
	}
	var throttled *curation.ThrottledError
	if _, err := f.svc.Search(ctx, ana, "mais uma"); !errors.As(err, &throttled) {
		t.Fatalf("the 21st valid search: %v", err)
	}
}

func TestSearchAccountLimit(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	cur := f.curator("bia@example.com", curation.MaePai)
	start := f.now
	f.search.Add("baby shark", "k1")
	f.source.Add(curationtest.Kids("k1", "Baby Shark"))

	// Cache hits spend the limit too: the same query 20 times.
	for range 20 {
		f.find(ana, "baby shark")
		f.now = f.now.Add(time.Minute)
	}
	var throttled *curation.ThrottledError
	if _, err := f.svc.Search(ctx, ana, "baby shark"); !errors.As(err, &throttled) ||
		throttled.RetryAfter != start.Add(24*time.Hour).Sub(f.now) {
		t.Fatalf("21st search: %v", err)
	}
	for i := range 25 {
		if _, err := f.svc.Search(ctx, cur, "baby shark"); err != nil {
			t.Fatalf("a curator was limited on search %d: %v", i+1, err)
		}
	}
	f.now = start.Add(24 * time.Hour)
	f.find(ana, "baby shark")
}

func TestSearchCacheIsSharedAndStateIsFresh(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	f.source.Add(curationtest.Kids("k1", "Baby Shark"))
	f.search.Add("Baby Shark", "k1")
	f.search.Add("baby shark", "k1")

	if got := f.find(ana, "Baby  Shark"); len(got) != 1 || got[0].State != "" {
		t.Fatalf("ana: %+v", got)
	}
	f.video("k1")
	if got := f.find(bia, "baby shark"); len(got) != 1 || got[0].State != curation.Pending || got[0].Refusal != "" {
		t.Fatalf("bia: %+v", got)
	}
	if c := f.search.Calls(); !slices.Equal(c, []string{"Baby Shark"}) {
		t.Fatalf("source calls: %q", c)
	}
	if n := len(f.source.Batches()); n != 1 {
		t.Fatalf("%d videos.list calls", n)
	}

	f.now = f.now.Add(24 * time.Hour)
	f.find(bia, "baby shark")
	if c := f.search.Calls(); len(c) != 2 {
		t.Fatalf("an expired entry was served: %q", c)
	}
}

func TestSearchWithoutSource(t *testing.T) {
	for name, change := range map[string]func(*curation.Deps){
		"no search source": func(d *curation.Deps) { d.Search = nil },
		"no video source":  func(d *curation.Deps) { d.Source = nil },
	} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			ana := f.account("ana@example.com")
			f.search.Add("baby shark", "k1")
			f.rebuild(change)
			var unavailable *curation.SearchUnavailableError
			if _, err := f.svc.Search(ctx, ana, "baby shark"); !errors.As(err, &unavailable) || unavailable.RetryAfter != 0 ||
				!errors.Is(err, curation.ErrSearchUnavailable) {
				t.Fatalf("%v", err)
			}
		})
	}
}

func TestSearchBudget(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.rebuild(func(d *curation.Deps) { d.SearchBudget = ratelimit.NewDaily(2, losAngeles, d.Now) })
	f.search.Add("um", "k1")
	f.source.Add(curationtest.Kids("k1", "Um"))

	f.find(ana, "um")
	f.find(ana, "dois")
	var unavailable *curation.SearchUnavailableError
	if _, err := f.svc.Search(ctx, ana, "tres"); !errors.As(err, &unavailable) ||
		unavailable.RetryAfter != f.nextPacificMidnight() {
		t.Fatalf("over the budget: %v", err)
	}
	if c := f.search.Calls(); len(c) != 2 {
		t.Fatalf("source calls: %q", c)
	}
	if got := f.find(ana, "um"); len(got) != 1 {
		t.Fatalf("a cached query: %+v", got)
	}
}

func TestSearchQuotaErrorClosesTheDay(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.search.Err = curation.ErrSearchQuota

	var unavailable *curation.SearchUnavailableError
	if _, err := f.svc.Search(ctx, ana, "um"); !errors.As(err, &unavailable) ||
		unavailable.RetryAfter != f.nextPacificMidnight() {
		t.Fatalf("quota error: %v", err)
	}
	f.search.Err = nil
	f.now = f.now.Add(time.Hour)
	if _, err := f.svc.Search(ctx, ana, "dois"); !errors.As(err, &unavailable) ||
		unavailable.RetryAfter != f.nextPacificMidnight() {
		t.Fatalf("after the quota error: %v", err)
	}
	if c := f.search.Calls(); len(c) != 1 {
		t.Fatalf("source calls: %q", c)
	}
	f.now = f.now.Add(f.nextPacificMidnight())
	f.find(ana, "dois")
	if c := f.search.Calls(); len(c) != 2 {
		t.Fatalf("after midnight: %q", c)
	}
}

func TestSearchFailureLogsNoQuery(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.search.Err = fmt.Errorf("%w: status 500", curation.ErrSearchUnavailable)

	var unavailable *curation.SearchUnavailableError
	if _, err := f.svc.Search(ctx, ana, "segredo da vovó"); !errors.As(err, &unavailable) || unavailable.RetryAfter != 0 {
		t.Fatalf("search failure: %v", err)
	}
	if f.logs.Len() == 0 {
		t.Fatal("the failure was not logged")
	}
	if strings.Contains(f.logs.String(), "segredo") {
		t.Fatalf("the query reached the log: %s", f.logs)
	}

	f.logs.Reset()
	f.search.Err = nil
	f.search.Add("segredo da vovó", "k1")
	f.source.Err = fmt.Errorf("%w: status 500", curation.ErrSourceUnavailable)
	if _, err := f.svc.Search(ctx, ana, "segredo da vovó"); !errors.As(err, &unavailable) || unavailable.RetryAfter != 0 {
		t.Fatalf("videos failure: %v", err)
	}
	if f.logs.Len() == 0 {
		t.Fatal("the failure was not logged")
	}
	if strings.Contains(f.logs.String(), "segredo") {
		t.Fatalf("the query reached the log: %s", f.logs)
	}
}

func TestSearchKeepsTheReadableItems(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.source.Add(curationtest.Kids("k1", "Um"))
	f.source.Add(curationtest.Kids("k2", "Dois"))
	f.source.Unreadable = map[string]bool{"k2": true}
	f.search.Add("baby shark", "k1", "k2")

	if got := f.find(ana, "baby shark"); !slices.Equal(resultIDs(got), []string{"k1"}) {
		t.Fatalf("results: %v", resultIDs(got))
	}
}

func TestSearchThumbnailOnlyForLiveResults(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.source.Add(curationtest.Kids("k1", "Baby Shark"))
	f.search.Add("baby shark", "k1")
	f.thumbs.Add("k1", []byte("jpeg"))

	if _, err := f.svc.SearchThumbnail(ctx, "k1"); !errors.Is(err, curation.ErrNotFound) {
		t.Fatalf("before a search: %v", err)
	}
	if c := f.thumbs.Calls(); len(c) != 0 {
		t.Fatalf("fetched before a search: %v", c)
	}

	f.find(ana, "baby shark")
	if b, err := f.svc.SearchThumbnail(ctx, "k1"); err != nil || !bytes.Equal(b, []byte("jpeg")) {
		t.Fatalf("after a search: %q %v", b, err)
	}
	if _, err := f.svc.SearchThumbnail(ctx, "x1"); !errors.Is(err, curation.ErrNotFound) {
		t.Fatalf("an ID no search returned: %v", err)
	}

	f.thumbs.Err = fmt.Errorf("%w: status 500", curation.ErrThumbnailUnavailable)
	if _, err := f.svc.SearchThumbnail(ctx, "k1"); !errors.Is(err, curation.ErrThumbnailUnavailable) {
		t.Fatalf("a failed fetch: %v", err)
	}
	f.thumbs.Err = nil

	f.now = f.now.Add(25 * time.Hour)
	if _, err := f.svc.SearchThumbnail(ctx, "k1"); !errors.Is(err, curation.ErrNotFound) {
		t.Fatalf("25 hours later: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM video_thumbnails`); n != 0 {
		t.Fatalf("%d thumbnails stored", n)
	}
}
