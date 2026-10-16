package curation_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func TestComposeStoresAPendingPack(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.Pedagogo)
	c2 := f.curator("c2@example.com", curation.MaePai)
	v := f.approvedVideos(3)

	p, err := f.svc.Compose(ctx, c1, curation.PackInput{Title: "  Bichos e música  ", VideoIDs: v, CoverVideoID: v[1], Theme: "bichos"})
	if err != nil {
		t.Fatal(err)
	}
	if p.State != curation.Pending || p.Round != 1 || p.Theme != "bichos" || p.Title != "Bichos e música" || p.CoverVideoID != v[1] ||
		p.ComposerRole != curation.Pedagogo || p.TotalSeconds != 900 || len(p.Videos) != 3 || p.Videos[2].ID != v[2] || p.Reviewable {
		t.Fatalf("pack %+v", p)
	}
	if n := f.count(`SELECT count(*) FROM pack_rounds WHERE pack_id = $1::uuid AND round = 1 AND composer_id = $2::uuid
		AND composer_role = 'pedagogo' AND outcome = 'open'`, p.ID, c1); n != 1 {
		t.Fatal("round 1 must hold the composer and a snapshot of their displayed role")
	}
	if !f.packDetail(c2, p.ID).Reviewable {
		t.Fatal("another curator may not review the new pack")
	}
	q, err := f.svc.Compose(ctx, c1, curation.PackInput{Title: "Sem capa", VideoIDs: v})
	if err != nil || q.CoverVideoID != v[0] || q.Theme != "" {
		t.Fatalf("the cover defaults to the first video: %+v %v", q, err)
	}
}

func TestCompositionRules(t *testing.T) {
	f := newFixture(t)
	cur := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideos(6)
	pending := f.video(nthID(90))
	held := f.published(nthID(91), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, held)
	unknown := "00000000-0000-0000-0000-000000000000"
	in := func(title string, ids ...string) curation.PackInput {
		return curation.PackInput{Title: title, VideoIDs: ids}
	}
	cover := func(title, cover string, ids ...string) curation.PackInput {
		p := in(title, ids...)
		p.CoverVideoID = cover
		return p
	}

	for name, tc := range map[string]struct {
		in     curation.PackInput
		reason string
	}{
		"no videos":                             {in("Bichos"), curation.PackInvalidCount},
		"two videos":                            {in("Bichos", v[:2]...), curation.PackInvalidCount},
		"six videos":                            {in("Bichos", v...), curation.PackInvalidCount},
		"a repeat":                              {in("Bichos", v[0], v[1], v[0]), curation.PackInvalidRepeat},
		"the same video in another letter case": {in("Bichos", v[0], v[1], strings.ToUpper(v[0])), curation.PackInvalidRepeat},
		"a pending video":                       {in("Bichos", v[0], v[1], pending), curation.PackInvalidNotApproved},
		"a held video":                          {in("Bichos", v[0], v[1], held), curation.PackInvalidNotApproved},
		"an unknown video":                      {in("Bichos", v[0], v[1], unknown), curation.PackInvalidNotApproved},
		"a malformed id":                        {in("Bichos", v[0], v[1], "abc"), curation.PackInvalidNotApproved},
		"over the duration":                     {in("Bichos", v[:5]...), curation.PackInvalidDuration},
		"a cover outside":                       {cover("Bichos", v[5], v[:3]...), curation.PackInvalidCover},
		"a blank title":                         {in("   ", v[:3]...), curation.PackInvalidTitle},
		"a long title":                          {in(strings.Repeat("é", 41), v[:3]...), curation.PackInvalidTitle},
		"a control character":                   {in("Bichos\x00", v[:3]...), curation.PackInvalidTitle},
		"count before repeat":                   {in("Bichos", v[0], v[0]), curation.PackInvalidCount},
		"repeat before not_approved":            {in("Bichos", pending, pending, v[0]), curation.PackInvalidRepeat},
		"not_approved before duration":          {in("Bichos", v[0], v[1], v[2], v[3], pending), curation.PackInvalidNotApproved},
		"duration before cover":                 {cover("Bichos", v[5], v[:5]...), curation.PackInvalidDuration},
		"cover before title":                    {cover("", v[5], v[:3]...), curation.PackInvalidCover},
	} {
		var invalid *curation.PackInvalidError
		if _, err := f.svc.Compose(ctx, cur, tc.in); !errors.As(err, &invalid) || invalid.Reason != tc.reason {
			t.Errorf("%s: %v, want %s", name, err, tc.reason)
		}
	}
	if _, err := f.svc.Compose(ctx, cur, curation.PackInput{Title: "Bichos", VideoIDs: v[:3], Theme: "carros"}); !errors.Is(err, curation.ErrValidation) {
		t.Errorf("unknown theme: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM packs`); n != 0 {
		t.Fatalf("refused compositions stored %d packs", n)
	}
}

func TestCompositionBoundaries(t *testing.T) {
	f := newFixture(t)
	cur := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideos(5)
	f.exec(`UPDATE videos SET duration_seconds = 150 WHERE id = $1::uuid OR id = $2::uuid`, v[3], v[4]) // 3×300 + 2×150 = 20:00

	p, err := f.svc.Compose(ctx, cur, curation.PackInput{Title: "  " + strings.Repeat("é", 40) + "  ", VideoIDs: v})
	if err != nil || p.TotalSeconds != 1200 || p.Title != strings.Repeat("é", 40) {
		t.Fatalf("five videos of exactly 20:00 and a 40-rune title: %+v %v", p, err)
	}
	f.exec(`UPDATE videos SET duration_seconds = 151 WHERE id = $1::uuid`, v[4]) // 20:01
	var invalid *curation.PackInvalidError
	if _, err := f.svc.Compose(ctx, cur, curation.PackInput{Title: "Bichos", VideoIDs: v}); !errors.As(err, &invalid) ||
		invalid.Reason != curation.PackInvalidDuration {
		t.Fatalf("20:01: %v", err)
	}
	f.rebuild(func(d *curation.Deps) { d.PackMaxDuration = 10 * time.Minute })
	if _, err := f.svc.Compose(ctx, cur, curation.PackInput{Title: "Bichos", VideoIDs: v[:3]}); !errors.As(err, &invalid) ||
		invalid.Reason != curation.PackInvalidDuration {
		t.Fatalf("15:00 under a 10-minute limit: %v", err)
	}
}

func TestComposeByARemovedCurator(t *testing.T) {
	f := newFixture(t)
	cur := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	f.exec(`DELETE FROM platform_roles WHERE account_id = $1::uuid`, cur)
	if _, err := f.svc.Compose(ctx, cur, curation.PackInput{Title: "Bichos", VideoIDs: v}); !errors.Is(err, curation.ErrNotCurator) {
		t.Fatalf("removed curator: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM packs`); n != 0 {
		t.Fatal("a removed curator's composition was stored")
	}
}
