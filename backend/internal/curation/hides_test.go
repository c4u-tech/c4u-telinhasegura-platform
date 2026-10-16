package curation_test

import (
	"errors"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestHideTakesEffectForThatChildOnly(t *testing.T) {
	f := newFixture(t)
	fam, ana := f.family("ana@example.com")
	bia := f.join(fam, "bia@example.com")
	lia, teo := f.minor(fam, family.Age5To8), f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	f.thumbs.Add(nthID(1), []byte("jpeg"))

	if err := f.svc.Hide(ctx, bia, lia.MinorID, v); err != nil { // any guardian of the family
		t.Fatal(err)
	}
	if got := f.catalog(lia); len(got) != 0 {
		t.Fatalf("lia still sees it: %+v", got)
	}
	if got := f.catalog(teo); len(got) != 1 {
		t.Fatalf("teo lost it: %+v", got)
	}
	if _, err := f.svc.Play(ctx, lia, v); !errors.Is(err, curation.ErrVideoNotAllowed) {
		t.Fatalf("play: %v", err)
	}
	if _, err := f.svc.ChildThumbnail(ctx, lia, v); !errors.Is(err, curation.ErrVideoNotAllowed) {
		t.Fatalf("thumbnail: %v", err)
	}
	if !f.audit.Has(bia, audit.VideoHidden) {
		t.Fatal("no video_hidden")
	}
	if n := f.count(`SELECT count(*) FROM video_hides WHERE minor_id = $1::uuid AND hidden_by = $2::uuid`, lia.MinorID, bia); n != 1 {
		t.Fatalf("%d hides by bia", n)
	}

	if err := f.svc.Hide(ctx, ana, lia.MinorID, v); err != nil { // already hidden
		t.Fatal(err)
	}
	if n := f.audited(audit.VideoHidden); n != 1 {
		t.Fatalf("%d video_hidden, want 1", n)
	}
	for range 2 {
		if err := f.svc.Unhide(ctx, ana, lia.MinorID, v); err != nil {
			t.Fatal(err)
		}
	}
	if n := f.audited(audit.VideoUnhidden); n != 1 {
		t.Fatalf("%d video_unhidden, want 1", n)
	}
	if got := f.catalog(lia); len(got) != 1 {
		t.Fatalf("unhidden but missing: %+v", got)
	}
}

func TestHideAcceptsAnyStoredVideoThatIsNotRemoved(t *testing.T) {
	f := newFixture(t)
	fam, ana := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	if err := f.svc.Hide(ctx, ana, lia.MinorID, f.video(nthID(1))); err != nil { // pending: hidden ahead of its publication
		t.Fatal(err)
	}
}

func TestHideRefusals(t *testing.T) {
	f := newFixture(t)
	fam, ana := f.family("ana@example.com")
	other, _ := f.family("bia@example.com")
	lia := f.minor(fam, family.Age5To8)
	teo := f.minor(other, family.Age5To8)
	lonely := f.account("solo@example.com")
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	removed := f.published(nthID(2), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'removed' WHERE id = $1::uuid`, removed)

	for _, c := range []struct{ name, account, minor, video string }{
		{"another family's child", ana, teo.MinorID, v},
		{"malformed minor", ana, "abc", v},
		{"no family", lonely, lia.MinorID, v},
		{"malformed video", ana, lia.MinorID, "abc"},
		{"unknown video", ana, lia.MinorID, "00000000-0000-0000-0000-000000000000"},
		{"removed video", ana, lia.MinorID, removed},
	} {
		if err := f.svc.Hide(ctx, c.account, c.minor, c.video); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("hide, %s: %v", c.name, err)
		}
	}
	for _, c := range []struct{ name, account, minor, video string }{
		{"another family's child", ana, teo.MinorID, v},
		{"no family", lonely, lia.MinorID, v},
		{"malformed video", ana, lia.MinorID, "abc"},
	} {
		if err := f.svc.Unhide(ctx, c.account, c.minor, c.video); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("unhide, %s: %v", c.name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_hides`); n != 0 {
		t.Fatalf("%d hides stored", n)
	}
}

func TestFamilyCatalogShowsWhatTheChildCanSee(t *testing.T) {
	f := newFixture(t)
	fam, ana := f.family("ana@example.com")
	_, bia := f.family("bia@example.com")
	lia := f.minor(fam, family.Age5To8)
	music := f.published(nthID(1), "musica", family.Age5To8)
	animals := f.published(nthID(2), "bichos", family.AgeUpTo4)
	f.published(nthID(3), "bichos", family.Age9To12)
	f.video(nthID(4))
	if err := f.svc.Hide(ctx, ana, lia.MinorID, music); err != nil {
		t.Fatal(err)
	}

	page, more, err := f.svc.FamilyCatalog(ctx, ana, lia.MinorID, 0)
	if err != nil || more {
		t.Fatalf("more %v, err %v", more, err)
	}
	if len(page) != 2 || page[0].Video.ID != animals || page[0].Hidden || page[1].Video.ID != music || !page[1].Hidden {
		t.Fatalf("page %+v", page)
	}
	p := page[0].Provenance
	if p == nil || p.Approvals[curation.MaePai] != 1 || len(p.Approvals) != 1 || !p.LastReviewedAt.Equal(f.now) {
		t.Fatalf("provenance %+v", p)
	}
	if _, _, err := f.svc.FamilyCatalog(ctx, bia, lia.MinorID, 0); !errors.Is(err, curation.ErrNotFound) {
		t.Fatalf("another family: %v", err)
	}
	if _, _, err := f.svc.FamilyCatalog(ctx, ana, lia.MinorID, -1); !errors.Is(err, curation.ErrValidation) {
		t.Fatalf("negative offset: %v", err)
	}
}

func TestFamilyCatalogPagesByFifty(t *testing.T) {
	f := newFixture(t)
	fam, ana := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	for i := range 55 {
		f.published(nthID(i), "bichos", family.AgeUpTo4)
	}
	first, more, err := f.svc.FamilyCatalog(ctx, ana, lia.MinorID, 0)
	if err != nil || len(first) != 50 || !more {
		t.Fatalf("first page: %d, more %v, %v", len(first), more, err)
	}
	rest, more, err := f.svc.FamilyCatalog(ctx, ana, lia.MinorID, 50)
	if err != nil || len(rest) != 5 || more {
		t.Fatalf("second page: %d, more %v, %v", len(rest), more, err)
	}
}
