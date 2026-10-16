package curation_test

import (
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func videoIDs(vs []curation.Video) []string {
	ids := []string{}
	for _, v := range vs {
		ids = append(ids, v.ID)
	}
	return ids
}

func TestApprovedVideosOfATheme(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	sapo := f.published(nthID(0), "bichos", family.AgeUpTo4)
	abelha := f.published(nthID(1), "bichos", family.Age5To8)
	f.exec(`UPDATE videos SET title = 'Sapo' WHERE id = $1::uuid`, sapo)
	f.exec(`UPDATE videos SET title = 'Abelha' WHERE id = $1::uuid`, abelha)
	f.published(nthID(2), "musica", family.AgeUpTo4)
	held := f.published(nthID(3), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, held)
	pending := f.published(nthID(4), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'pending' WHERE id = $1::uuid`, pending)
	removed := f.published(nthID(5), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'removed' WHERE id = $1::uuid`, removed)
	f.suggestedBy(c, sapo)

	vs, more, err := f.svc.ApprovedVideos(ctx, "bichos", 0)
	if err != nil || more || !slices.Equal(videoIDs(vs), []string{abelha, sapo}) {
		t.Fatalf("bichos: %v %v %v", videoIDs(vs), more, err)
	}
	if vs[0].ChannelTitle != "Canal" || vs[0].MinAgeBand != family.Age5To8 || vs[0].DurationSeconds != 300 {
		t.Fatalf("video %+v", vs[0])
	}
}

func TestApprovedVideosPageByFifty(t *testing.T) {
	f := newFixture(t)
	ids := f.approvedVideos(51) // titled "Vídeo vidNNNNNNNN", so in insertion order

	first, more, err := f.svc.ApprovedVideos(ctx, "bichos", 0)
	if err != nil || !more || !slices.Equal(videoIDs(first), ids[:50]) {
		t.Fatalf("first page: %d %v %v", len(first), more, err)
	}
	last, more, err := f.svc.ApprovedVideos(ctx, "bichos", 50)
	if err != nil || more || !slices.Equal(videoIDs(last), ids[50:]) {
		t.Fatalf("last page: %d %v %v", len(last), more, err)
	}
}

func TestApprovedVideosRefuseABadThemeOrOffset(t *testing.T) {
	f := newFixture(t)
	for _, tc := range []struct {
		theme  string
		offset int
	}{{"", 0}, {"esportes", 0}, {"Bichos", 0}, {"bichos", -1}} {
		if _, _, err := f.svc.ApprovedVideos(ctx, tc.theme, tc.offset); !errors.Is(err, curation.ErrValidation) {
			t.Errorf("%q at %d: %v", tc.theme, tc.offset, err)
		}
	}
}

func TestPackLimitsFollowTheConfiguration(t *testing.T) {
	f := newFixture(t)
	if got := f.svc.PackLimits(); got != (curation.PackLimits{MinVideos: 3, MaxVideos: 5, MaxDuration: 20 * time.Minute}) {
		t.Fatalf("limits %+v", got)
	}
	f.rebuild(func(d *curation.Deps) { d.PackMaxDuration = 15 * time.Minute })
	if got := f.svc.PackLimits().MaxDuration; got != 15*time.Minute {
		t.Fatalf("max duration %v", got)
	}
}

func TestAdminReadsPacks(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	f.exec(`INSERT INTO platform_roles (account_id, role, display_role, verified_professional, granted_at)
		VALUES ($1::uuid, 'curator', 'mae-pai', false, $2)`, admin, f.now)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	published := f.publishedPack(v...)
	pending := f.pendingPack(c, v...)
	gone := f.pendingPack(c, v...)
	f.exec(`UPDATE packs SET state = 'removed' WHERE id = $1::uuid`, gone)
	if !f.packDetail(admin, pending).Reviewable {
		t.Fatal("precondition: the admin, also a curator, may review the pending round")
	}

	ps, more, err := f.svc.AdminPacks(ctx, admin, 0)
	if err != nil || more || len(ps) != 2 || ps[0].ID != pending || ps[1].ID != published {
		t.Fatalf("admin packs: %+v %v %v", ps, more, err)
	}
	for _, p := range ps {
		if p.Reviewable {
			t.Errorf("%s reviewable on an admin read", p.ID)
		}
	}
	if _, _, err := f.svc.AdminPacks(ctx, admin, -1); !errors.Is(err, curation.ErrValidation) {
		t.Errorf("offset -1: %v", err)
	}

	p, err := f.svc.AdminPack(ctx, admin, pending)
	if err != nil || p.ID != pending || p.Reviewable || p.Videos[0].ChannelTitle != "Canal" {
		t.Fatalf("admin pack: %+v %v", p, err)
	}
	if p, err := f.svc.AdminPack(ctx, admin, gone); err != nil || p.State != curation.Removed {
		t.Fatalf("a removed pack: %+v %v", p, err)
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.AdminPack(ctx, admin, id); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", id, err)
		}
	}
}
