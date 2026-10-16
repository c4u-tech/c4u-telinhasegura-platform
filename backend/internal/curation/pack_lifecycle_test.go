package curation_test

import (
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestRecomposeAPendingPack(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Cuidador)
	v := f.approvedVideos(6)
	id := f.compose(c1, v[:3]...).ID
	f.now = f.now.Add(time.Hour)

	p, err := f.svc.Recompose(ctx, c2, id, curation.PackInput{Title: "Outro", VideoIDs: v[3:], CoverVideoID: v[5], Theme: "musica"})
	if err != nil {
		t.Fatal(err)
	}
	if p.State != curation.Pending || p.Round != 2 || p.Title != "Outro" || p.CoverVideoID != v[5] || p.Theme != "musica" ||
		p.ComposerRole != curation.Cuidador || p.Videos[0].ID != v[3] || p.Reviewable {
		t.Fatalf("recomposed %+v", p)
	}
	if !f.packDetail(c1, id).Reviewable {
		t.Fatal("round 1's composer may not review round 2")
	}
	if n := f.count(`SELECT count(*) FROM pack_rounds WHERE pack_id = $1::uuid`, id); n != 2 {
		t.Fatalf("%d rounds, want round 1 kept beside round 2", n)
	}
}

func TestRecomposeAHeldPackMakesItPending(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	id := f.compose(c, v...).ID
	f.exec(`UPDATE pack_rounds SET outcome = 'rejected' WHERE pack_id = $1::uuid`, id)
	f.exec(`UPDATE packs SET state = 'held' WHERE id = $1::uuid`, id)

	p, err := f.svc.Recompose(ctx, c, id, curation.PackInput{Title: "De novo", VideoIDs: v})
	if err != nil || p.State != curation.Pending || p.Round != 2 {
		t.Fatalf("recomposed %+v %v", p, err)
	}
}

func TestRecomposeAnApprovedPackKeepsItsPublishedRound(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.Cuidador)
	v := f.approvedVideos(6)
	id := f.publishedPack(v[:3]...)

	p, err := f.svc.Recompose(ctx, c, id, curation.PackInput{Title: "Outro", VideoIDs: v[3:]})
	if err != nil {
		t.Fatal(err)
	}
	if p.State != curation.Approved || p.Round != 2 || p.Title != "Outro" || p.Videos[0].ID != v[3] ||
		p.ComposerRole != curation.Cuidador || p.Reviewable || p.Provenance == nil {
		t.Fatalf("recomposed %+v", p)
	}
	if n := f.count(`SELECT count(*) FROM packs WHERE id = $1::uuid AND published_round = 1`, id); n != 1 {
		t.Fatal("the published round moved before the new round was published")
	}
}

func TestRecomposeRefusals(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("adm@example.com")
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	id := f.compose(c, v...).ID

	var invalid *curation.PackInvalidError
	if _, err := f.svc.Recompose(ctx, c, id, curation.PackInput{Title: "Curto", VideoIDs: v[:2]}); !errors.As(err, &invalid) ||
		invalid.Reason != curation.PackInvalidCount {
		t.Fatalf("a broken composition: %v", err)
	}
	if err := f.svc.RemovePack(ctx, admin, id); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Recompose(ctx, c, id, curation.PackInput{Title: "De novo", VideoIDs: v}); !errors.Is(err, curation.ErrStateConflict) {
		t.Fatalf("a removed pack: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM pack_rounds WHERE pack_id = $1::uuid`, id); n != 1 {
		t.Fatalf("a refused recompose stored a round: %d rounds", n)
	}
	for _, bad := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.Recompose(ctx, c, bad, curation.PackInput{Title: "De novo", VideoIDs: v}); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", bad, err)
		}
	}
}

func TestRemovePack(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("adm@example.com")
	c := f.curator("c1@example.com", curation.MaePai)
	id := f.compose(c, f.approvedVideos(3)...).ID

	if err := f.svc.RemovePack(ctx, admin, id); err != nil {
		t.Fatal(err)
	}
	if p := f.packDetail(c, id); p.State != curation.Removed || p.Reviewable {
		t.Fatalf("removed %+v", p)
	}
	if err := f.svc.RemovePack(ctx, admin, id); !errors.Is(err, curation.ErrStateConflict) {
		t.Fatalf("remove twice: %v", err)
	}
	for _, bad := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if err := f.svc.RemovePack(ctx, admin, bad); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", bad, err)
		}
	}
	if !f.audit.Has(admin, audit.PackRemoved) || f.audited(audit.PackRemoved) != 1 {
		t.Fatal("pack_removed must be recorded once, under the admin")
	}
}

func TestPackQueue(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("adm@example.com")
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	approved := f.publishedPack(v...) // updated now
	f.now = f.now.Add(time.Minute)
	first := f.compose(c1, v...).ID // open since now + 1 min
	f.now = f.now.Add(time.Minute)
	held := f.compose(c2, v...).ID
	f.exec(`UPDATE pack_rounds SET outcome = 'rejected' WHERE pack_id = $1::uuid`, held)
	f.exec(`UPDATE packs SET state = 'held', updated_at = $2 WHERE id = $1::uuid`, held, f.now) // updated now + 2 min
	f.now = f.now.Add(time.Minute)
	second := f.compose(c2, v...).ID // open since now + 3 min
	f.now = f.now.Add(time.Minute)
	removed := f.compose(c1, v...).ID
	if err := f.svc.RemovePack(ctx, admin, removed); err != nil {
		t.Fatal(err)
	}

	items, more, err := f.svc.PackQueue(ctx, c1, 0)
	if err != nil || more {
		t.Fatalf("queue: %v %v", more, err)
	}
	var ids []string
	var reviewable []bool
	for _, p := range items {
		ids, reviewable = append(ids, p.ID), append(reviewable, p.Reviewable)
	}
	if want := []string{first, second, held, approved}; !slices.Equal(ids, want) {
		t.Fatalf("queue %v, want %v", ids, want)
	}
	if want := []bool{false, true, false, false}; !slices.Equal(reviewable, want) {
		t.Fatalf("reviewable %v, want %v", reviewable, want)
	}
}

func TestPackQueuePages(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	var first string
	for i := range 51 {
		p := f.compose(c, v...)
		if i == 0 {
			first = p.ID
		}
		f.now = f.now.Add(time.Second)
	}
	page, more, err := f.svc.PackQueue(ctx, c, 0)
	if err != nil || len(page) != 50 || !more || page[0].ID != first {
		t.Fatalf("first page: %d %v %v", len(page), more, err)
	}
	page, more, err = f.svc.PackQueue(ctx, c, 50)
	if err != nil || len(page) != 1 || more {
		t.Fatalf("second page: %d %v %v", len(page), more, err)
	}
	if _, _, err := f.svc.PackQueue(ctx, c, -1); !errors.Is(err, curation.ErrValidation) {
		t.Fatalf("negative offset: %v", err)
	}
}
