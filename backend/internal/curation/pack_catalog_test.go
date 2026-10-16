package curation_test

import (
	"errors"
	"reflect"
	"slices"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func TestKidPacksServeOnlyApprovedPacks(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("adm@example.com")
	c := f.curator("c1@example.com", curation.MaePai)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	if got := f.kidPacks(lia); got == nil || len(got) != 0 {
		t.Fatalf("packs %#v, want an empty, non-nil list", got)
	}
	v := f.approvedVideos(3)
	f.compose(c, v...) // pending: never served
	id := f.publishedPack(v...)

	want := []curation.KidPack{{ID: id, Title: "Pacotinho", CoverVideoID: v[0], Videos: []curation.KidVideo{
		{ID: v[0], Title: "Vídeo " + nthID(0), DurationSeconds: 300},
		{ID: v[1], Title: "Vídeo " + nthID(1), DurationSeconds: 300},
		{ID: v[2], Title: "Vídeo " + nthID(2), DurationSeconds: 300},
	}}}
	if got := f.kidPacks(lia); !reflect.DeepEqual(got, want) {
		t.Fatalf("packs %+v, want %+v", got, want)
	}
	if err := f.svc.RemovePack(ctx, admin, id); err != nil {
		t.Fatal(err)
	}
	if got := f.kidPacks(lia); len(got) != 0 {
		t.Fatalf("a removed pack reached a child: %+v", got)
	}
}

func TestAPackShowsOnlyWhenEveryApprovedVideoFitsTheBand(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	big := f.minor(fam, family.Age9To12)
	a := f.published(nthID(1), "bichos", family.AgeUpTo4)
	b := f.published(nthID(2), "bichos", family.Age5To8)
	old := f.published(nthID(3), "bichos", family.Age9To12)
	id := f.publishedPack(a, b, old)

	if got := f.kidPacks(lia); len(got) != 0 {
		t.Fatalf("a 9-12 video let a 5-8 child see the pack: %+v", got)
	}
	if got := f.kidPacks(big); len(got) != 1 || got[0].ID != id {
		t.Fatalf("9-12 child: %+v", got)
	}
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'reports' WHERE id = $1::uuid`, old)
	if got := f.kidPacks(lia); len(got) != 1 || !slices.Equal(packVideoIDs(got[0]), []string{a, b}) {
		t.Fatalf("a held video still blocked the band: %+v", got)
	}
}

func TestKidPacksSkipHiddenAndReportedVideos(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	teo := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(3)
	f.publishedPack(v...)

	if err := f.svc.Hide(ctx, owner, lia.MinorID, v[1]); err != nil {
		t.Fatal(err)
	}
	if got := f.kidPacks(lia); len(got) != 1 || !slices.Equal(packVideoIDs(got[0]), []string{v[0], v[2]}) {
		t.Fatalf("lia after a hide: %+v", got)
	}
	if got := f.kidPacks(teo); len(got) != 1 || !slices.Equal(packVideoIDs(got[0]), v) {
		t.Fatalf("a hide for lia reached teo: %+v", got)
	}
	if _, err := f.svc.Report(ctx, owner, v[2], curation.ReportOutro, ""); err != nil {
		t.Fatal(err)
	}
	if got := f.kidPacks(lia); len(got) != 0 {
		t.Fatalf("a pack with one playable video was shown: %+v", got)
	}
	if got := f.kidPacks(teo); len(got) != 1 || !slices.Equal(packVideoIDs(got[0]), []string{v[0], v[1]}) {
		t.Fatalf("teo after the family's report: %+v", got)
	}
}

func TestAHeldVideoLeavesAPackAndReturnsToItsPlace(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(4)
	f.publishedPack(v...)

	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, v[1])
	if got := f.kidPacks(lia); len(got) != 1 || !slices.Equal(packVideoIDs(got[0]), []string{v[0], v[2], v[3]}) {
		t.Fatalf("while held: %+v", got)
	}
	f.exec(`UPDATE videos SET state = 'approved', held_reason = NULL WHERE id = $1::uuid`, v[1])
	if got := f.kidPacks(lia); len(got) != 1 || !slices.Equal(packVideoIDs(got[0]), v) {
		t.Fatalf("approved again: %+v", got)
	}
}

func TestAPackCoverFallsBackToTheFirstPlayableVideo(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(4)
	id := f.publishedPack(v...)
	f.exec(`UPDATE pack_rounds SET cover_video_id = $2::uuid WHERE pack_id = $1::uuid`, id, v[1])

	cover := func() string {
		t.Helper()
		got := f.kidPacks(lia)
		if len(got) != 1 {
			t.Fatalf("packs %+v", got)
		}
		return got[0].CoverVideoID
	}
	if got := cover(); got != v[1] {
		t.Fatalf("cover %s, want the composition's %s", got, v[1])
	}
	if err := f.svc.Hide(ctx, owner, lia.MinorID, v[1]); err != nil {
		t.Fatal(err)
	}
	if got := cover(); got != v[0] {
		t.Fatalf("cover %s, want the first playable %s", got, v[0])
	}
	if err := f.svc.Hide(ctx, owner, lia.MinorID, v[0]); err != nil {
		t.Fatal(err)
	}
	if got := cover(); got != v[2] {
		t.Fatalf("cover %s, want the first playable %s", got, v[2])
	}
}

func TestPackRowRotatesAtTheFamilysMidnight(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *curation.Deps) { d.PackRowSize = 3 })
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(3)
	for range 30 {
		f.publishedPack(v...)
	}
	ids := func(loc *time.Location) []string {
		t.Helper()
		ps, err := f.svc.KidPacks(ctx, lia, loc)
		if err != nil {
			t.Fatal(err)
		}
		out := []string{}
		for _, p := range ps {
			out = append(out, p.ID)
		}
		return out
	}

	f.now = time.Date(2026, 10, 4, 3, 0, 0, 0, time.UTC) // 00:00 on the 4th in São Paulo
	dayStart := ids(saoPaulo)
	if len(dayStart) != 3 {
		t.Fatalf("a row of %d, want the row size 3", len(dayStart))
	}
	f.now = time.Date(2026, 10, 5, 2, 59, 0, 0, time.UTC) // 23:59 on the 4th
	dayEnd := ids(saoPaulo)
	f.now = time.Date(2026, 10, 5, 3, 0, 0, 0, time.UTC) // 00:00 on the 5th
	nextDay := ids(saoPaulo)
	if !slices.Equal(dayStart, dayEnd) {
		t.Fatalf("the 4th changed rows: %v then %v", dayStart, dayEnd)
	}
	if slices.Equal(dayEnd, nextDay) {
		t.Fatalf("the row did not turn at São Paulo midnight: %v", nextDay)
	}
	manaus, _ := time.LoadLocation("America/Manaus")
	if got := ids(manaus); !slices.Equal(got, dayEnd) { // 23:00 on the 4th in Manaus
		t.Fatalf("Manaus's 4th rotated at São Paulo's midnight: %v", got)
	}
}

func TestARecomposedPackServesItsPublishedRound(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	c3 := f.curator("c3@example.com", curation.MaePai)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(6)
	id := f.publishedPack(v[:3]...)

	if _, err := f.svc.Recompose(ctx, c1, id, curation.PackInput{Title: "Outro", VideoIDs: v[3:]}); err != nil {
		t.Fatal(err)
	}
	if got := f.kidPacks(lia); len(got) != 1 || got[0].Title != "Pacotinho" || !slices.Equal(packVideoIDs(got[0]), v[:3]) {
		t.Fatalf("while round 2 is reviewed: %+v", got)
	}
	f.reviewPack(c2, id, approvePack())
	f.reviewPack(c3, id, approvePack())
	if got := f.kidPacks(lia); len(got) != 1 || got[0].Title != "Outro" || !slices.Equal(packVideoIDs(got[0]), v[3:]) {
		t.Fatalf("once round 2 is published: %+v", got)
	}
}

func TestAnApprovedVideoWithNoBandBlocksThePack(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(4)
	f.publishedPack(v...)
	f.exec(`UPDATE videos SET min_age_band = NULL WHERE id = $1::uuid`, v[1])

	got, err := f.svc.KidPacks(ctx, lia, saoPaulo)
	if err != nil {
		t.Fatalf("a video with no band failed the catalogue: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("a video with no band let the pack through: %+v", got)
	}
}

func TestAHiddenOutOfBandVideoStillBlocksThePack(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	a := f.published(nthID(1), "bichos", family.AgeUpTo4)
	b := f.published(nthID(2), "bichos", family.Age5To8)
	c := f.published(nthID(3), "bichos", family.Age5To8)
	old := f.published(nthID(4), "bichos", family.Age9To12)
	f.publishedPack(a, b, c, old)

	if err := f.svc.Hide(ctx, owner, lia.MinorID, old); err != nil {
		t.Fatal(err)
	}
	if got := f.kidPacks(lia); len(got) != 0 {
		t.Fatalf("hiding a 9-12 video let a 5-8 child see the pack: %+v", got)
	}
}

func TestKidPacksOfAGoneChild(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	gone := f.minor(fam, family.Age5To8)
	f.exec(`DELETE FROM minors WHERE id = $1::uuid`, gone.MinorID)
	if _, err := f.svc.KidPacks(ctx, gone, saoPaulo); !errors.Is(err, curation.ErrProfileGone) {
		t.Fatalf("gone child: %v", err)
	}
}
