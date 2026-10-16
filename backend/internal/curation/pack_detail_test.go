package curation_test

import (
	"errors"
	"maps"
	"reflect"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

func TestPackDetailOfAPendingPack(t *testing.T) { // packs, Contract (the pack detail)
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	v := f.approvedVideos(3)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, v[2])
	id := f.pendingPack(c1, v...)

	p := f.packDetail(c2, id)
	want := []curation.PackVideo{
		{ID: v[0], Title: "Vídeo " + nthID(0), ChannelTitle: "Canal", DurationSeconds: 300, State: curation.Approved},
		{ID: v[1], Title: "Vídeo " + nthID(1), ChannelTitle: "Canal", DurationSeconds: 300, State: curation.Approved},
		{ID: v[2], Title: "Vídeo " + nthID(2), ChannelTitle: "Canal", DurationSeconds: 300, State: curation.Held},
	}
	if p.ID != id || p.State != curation.Pending || p.Round != 1 || p.Theme != "" || p.Title != "Pacotinho" ||
		p.CoverVideoID != v[0] || p.ComposerRole != curation.MaePai || p.TotalSeconds != 900 ||
		!reflect.DeepEqual(p.Videos, want) || p.Reviews == nil || len(p.Reviews) != 0 || p.Provenance != nil || !p.Reviewable {
		t.Fatalf("pack %+v", p)
	}
	if f.packDetail(c1, id).Reviewable {
		t.Fatal("the composer may review their own round")
	}
}

func TestPackDetailOfAPublishedPack(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	id := f.publishedPack(f.approvedVideos(3)...)

	p := f.packDetail(c, id)
	want := map[curation.DisplayRole]int{curation.Pedagogo: 1}
	if p.State != curation.Approved || p.Reviewable || p.Provenance == nil || !maps.Equal(p.Provenance.Approvals, want) ||
		!p.Provenance.LastReviewedAt.Equal(f.now) {
		t.Fatalf("pack %+v, provenance %+v", p, p.Provenance)
	}
}

func TestPackDetailOfAnUnknownPack(t *testing.T) { // packs, Codes (not_found)
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.PackDetail(ctx, c, id); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", id, err)
		}
	}
}

func TestAnApprovedPackAlwaysHasAPublishedRound(t *testing.T) { // the migration's CHECK
	f := newFixture(t)
	if _, err := f.pool.Exec(ctx, `INSERT INTO packs (state, created_at, updated_at) VALUES ('approved', now(), now())`); err == nil {
		t.Fatal("an approved pack without a published round was stored")
	}
}
