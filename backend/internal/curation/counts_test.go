package curation_test

import (
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func TestPublishedCounts(t *testing.T) {
	f := newFixture(t)
	a := f.published(nthID(1), "bichos", family.AgeUpTo4)
	b := f.published(nthID(2), "bichos", family.AgeUpTo4)
	f.video(nthID(3)) // pending
	held := f.published(nthID(4), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, held)
	f.publishedPack(a, b)
	f.pendingPack(f.account("caio@example.com"), a, b)
	removed := f.publishedPack(b, a)
	f.exec(`UPDATE packs SET state = 'removed' WHERE id = $1::uuid`, removed)

	if n, err := f.svc.CountPublishedVideos(ctx); err != nil || n != 2 {
		t.Fatalf("published videos %d %v", n, err)
	}
	if n, err := f.svc.CountPublishedPacks(ctx); err != nil || n != 1 {
		t.Fatalf("published packs %d %v", n, err)
	}
}

func TestCountReportsSince(t *testing.T) {
	f := newFixture(t)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	fams, _ := f.families(3)
	since := f.now.Add(-7 * 24 * time.Hour)
	for i, at := range []time.Time{since, since.Add(-time.Microsecond), f.now} {
		f.exec(`INSERT INTO video_reports (video_id, family_id, reason, reported_at) VALUES ($1::uuid, $2::uuid, 'outro', $3)`,
			v, fams[i], at)
	}
	if n, err := f.svc.CountReportsSince(ctx, since); err != nil || n != 2 {
		t.Fatalf("reports since the window opened %d %v, want the edge and the newest", n, err)
	}
}
