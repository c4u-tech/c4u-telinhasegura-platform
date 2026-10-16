package curation_test

import (
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func TestCatalogFiltersByBandAndOrdersThemes(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	bebe := f.minor(fam, family.AgeUpTo4)
	music := f.published(nthID(1), "musica", family.AgeUpTo4)
	animals := f.published(nthID(2), "bichos", family.Age5To8)
	f.published(nthID(3), "historias", family.Age9To12)
	f.video(nthID(4)) // pending
	held := f.published(nthID(5), "brincar", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, held)

	got := f.catalog(lia)
	want := []curation.Shelf{
		{Theme: "bichos", Videos: []curation.KidVideo{{ID: animals, Title: "Vídeo " + nthID(2), DurationSeconds: 300}}},
		{Theme: "musica", Videos: []curation.KidVideo{{ID: music, Title: "Vídeo " + nthID(1), DurationSeconds: 300}}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("5-8 shelves %+v, want %+v", got, want)
	}
	if got := f.catalog(bebe); len(got) != 1 || got[0].Theme != "musica" {
		t.Fatalf("under-4 shelves %+v", got)
	}
}

func TestCatalogWithNoVideosIsEmpty(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	if got := f.catalog(f.minor(fam, family.Age5To8)); got == nil || len(got) != 0 {
		t.Fatalf("shelves %#v, want an empty, non-nil list", got)
	}
}

func TestShelvesHoldAtMostTheShelfSizeAllDay(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *curation.Deps) { d.ShelfSize = 3 })
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	for i := range 10 {
		f.published(nthID(i), "bichos", family.AgeUpTo4)
	}

	first := f.catalog(lia)
	if len(first) != 1 || len(first[0].Videos) != 3 {
		t.Fatalf("shelves %+v", first)
	}
	f.now = f.now.Add(5 * time.Hour) // 12:00 UTC is 09:00 in São Paulo: still the same day
	if again := f.catalog(lia); !reflect.DeepEqual(again, first) {
		t.Fatalf("the shelf changed within the day: %+v then %+v", first, again)
	}
}

func TestRotationTurnsAtSaoPauloMidnight(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *curation.Deps) { d.ShelfSize = 3 })
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	for i := range 30 {
		f.published(nthID(i), "bichos", family.AgeUpTo4)
	}

	f.now = time.Date(2026, 10, 4, 3, 0, 0, 0, time.UTC) // 00:00 on the 4th in São Paulo
	dayStart := f.catalog(lia)
	f.now = time.Date(2026, 10, 5, 2, 59, 0, 0, time.UTC) // 23:59 on the 4th
	dayEnd := f.catalog(lia)
	f.now = time.Date(2026, 10, 5, 3, 0, 0, 0, time.UTC) // 00:00 on the 5th
	nextDay := f.catalog(lia)

	if !reflect.DeepEqual(dayStart, dayEnd) {
		t.Fatalf("the 4th changed shelves: %+v then %+v", dayStart, dayEnd)
	}
	if reflect.DeepEqual(dayEnd, nextDay) {
		t.Fatalf("the shelves did not turn at São Paulo midnight: %+v", nextDay)
	}
}

func TestTwoChildrenGetTheirOwnShelves(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *curation.Deps) { d.ShelfSize = 3 })
	fam, _ := f.family("ana@example.com")
	lia, teo := f.minor(fam, family.Age5To8), f.minor(fam, family.Age5To8)
	for i := range 30 {
		f.published(nthID(i), "bichos", family.AgeUpTo4)
	}
	if reflect.DeepEqual(f.catalog(lia), f.catalog(teo)) {
		t.Fatal("two children got the same shelves")
	}
}

func TestCatalogFollowsABandChange(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.Age5To8)
	if got := f.catalog(lia); len(got) != 1 {
		t.Fatalf("before: %+v", got)
	}
	f.exec(`UPDATE minors SET age_band = 'ate-4' WHERE id = $1::uuid`, lia.MinorID)
	if got := f.catalog(lia); len(got) != 0 {
		t.Fatalf("after the band change: %+v", got)
	}
	if _, err := f.svc.Play(ctx, lia, v); !errors.Is(err, curation.ErrVideoNotAllowed) {
		t.Fatalf("play after the band change: %v", err)
	}
}

func TestAGoneChildGetsProfileGone(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	other, _ := f.family("bia@example.com")
	lia := f.minor(fam, family.Age5To8)
	gone := f.minor(fam, family.Age5To8)
	f.exec(`DELETE FROM minors WHERE id = $1::uuid`, gone.MinorID)

	for name, c := range map[string]curation.Child{
		"no minor":       {FamilyID: fam},
		"no family":      {MinorID: lia.MinorID},
		"deleted minor":  gone,
		"another family": {FamilyID: other, MinorID: lia.MinorID},
	} {
		if _, err := f.svc.Catalog(ctx, c, saoPaulo); !errors.Is(err, curation.ErrProfileGone) {
			t.Errorf("%s: catalog %v", name, err)
		}
		if _, err := f.svc.Play(ctx, c, nthID(1)); !errors.Is(err, curation.ErrProfileGone) {
			t.Errorf("%s: play %v", name, err)
		}
	}
}

func TestPlayRechecksTheVideo(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	strict := f.published(nthID(2), "bichos", family.Age9To12)
	pending := f.video(nthID(3))

	yt, err := f.svc.Play(ctx, lia, v)
	if err != nil || yt != nthID(1) {
		t.Fatalf("play: %q %v", yt, err)
	}
	for name, id := range map[string]string{"stricter band": strict, "pending": pending, "malformed": "abc",
		"unknown": "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.Play(ctx, lia, id); !errors.Is(err, curation.ErrVideoNotAllowed) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if len(f.audit.Entries) != 0 {
		t.Fatalf("a play recorded %+v", f.audit.Entries)
	}
}

func TestCatalogRotatesOnTheGivenZone(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, family.Age5To8)
	for i := range 30 {
		f.published(nthID(i), "bichos", family.Age5To8)
	}
	f.rebuild(func(d *curation.Deps) { d.ShelfSize = 3 })
	manaus, _ := time.LoadLocation("America/Manaus")
	f.now = time.Date(2026, 10, 6, 3, 30, 0, 0, time.UTC) // the 6th in São Paulo, still the 5th in Manaus
	inManaus, _ := f.svc.Catalog(ctx, c, manaus)
	f.now = time.Date(2026, 10, 5, 23, 0, 0, 0, time.UTC) // the 5th in both
	before, _ := f.svc.Catalog(ctx, c, manaus)
	if !reflect.DeepEqual(inManaus, before) {
		t.Fatal("Manaus's 5th rotated at São Paulo's midnight")
	}
}
