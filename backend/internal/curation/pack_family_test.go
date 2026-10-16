package curation_test

import (
	"errors"
	"maps"
	"reflect"
	"slices"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func (f *fixture) familyPacks(accountID, minorID string) []curation.FamilyPack {
	f.t.Helper()
	ps, err := f.svc.FamilyPacks(ctx, accountID, minorID, saoPaulo)
	if err != nil {
		f.t.Fatalf("family packs: %v", err)
	}
	return ps
}

func TestFamilyPacksShowEveryApprovedVideoAndTheSkippedOnes(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(4)
	id := f.publishedPack(v...)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, v[3])
	if err := f.svc.Hide(ctx, owner, lia.MinorID, v[1]); err != nil {
		t.Fatal(err)
	}

	got := f.familyPacks(owner, lia.MinorID)
	kid := f.kidPacks(lia)
	if len(got) != 1 || len(kid) != 1 || got[0].ID != id || got[0].ID != kid[0].ID || got[0].Title != "Pacotinho" ||
		got[0].CoverVideoID != kid[0].CoverVideoID || got[0].ComposerRole != curation.MaePai {
		t.Fatalf("family %+v, kid %+v", got, kid)
	}
	want := []curation.FamilyPackVideo{
		{Video: curation.KidVideo{ID: v[0], Title: "Vídeo " + nthID(0), DurationSeconds: 300}},
		{Video: curation.KidVideo{ID: v[1], Title: "Vídeo " + nthID(1), DurationSeconds: 300}, Hidden: true},
		{Video: curation.KidVideo{ID: v[2], Title: "Vídeo " + nthID(2), DurationSeconds: 300}},
	}
	if !reflect.DeepEqual(got[0].Videos, want) {
		t.Fatalf("videos %+v, want %+v", got[0].Videos, want)
	}
	if p := got[0].Provenance; !maps.Equal(p.Approvals, map[curation.DisplayRole]int{curation.Pedagogo: 1}) || !p.LastReviewedAt.Equal(f.now) {
		t.Fatalf("provenance %+v", p)
	}
}

func TestFamilyPacksAreExactlyTheChildsRow(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *curation.Deps) { d.PackRowSize = 3 })
	fam, owner := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(3)
	for range 30 {
		f.publishedPack(v...)
	}
	strict := f.published(nthID(50), "bichos", family.Age9To12)
	f.publishedPack(v[0], v[1], strict) // never lia's

	var kidIDs, familyIDs []string
	for _, p := range f.kidPacks(lia) {
		kidIDs = append(kidIDs, p.ID)
	}
	for _, p := range f.familyPacks(owner, lia.MinorID) {
		familyIDs = append(familyIDs, p.ID)
	}
	if len(kidIDs) != 3 || !slices.Equal(kidIDs, familyIDs) {
		t.Fatalf("kid %v, family %v", kidIDs, familyIDs)
	}
}

func TestFamilyPacksGuardTheMinor(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	_, bia := f.family("bia@example.com")
	solo := f.account("solo@example.com")
	for name, c := range map[string][2]string{
		"another family": {bia, lia.MinorID},
		"malformed":      {owner, "abc"},
		"unknown":        {owner, "00000000-0000-0000-0000-000000000000"},
		"no family":      {solo, lia.MinorID},
	} {
		if _, err := f.svc.FamilyPacks(ctx, c[0], c[1], saoPaulo); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%s: %v", name, err)
		}
	}
}
