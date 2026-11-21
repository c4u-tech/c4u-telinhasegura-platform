package curation_test

import (
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
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

func TestReviewMeasuresSince(t *testing.T) {
	f := newFixture(t)
	vids := f.approvedVideos(4)
	f.exec(`DELETE FROM video_reviews`) // the fixture's own approvals
	since := f.now.Add(-30 * 24 * time.Hour)
	approve := func(video, stated, computed string, round, minutes int) {
		f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band,
			computed_band, reviewed_at, began_at) VALUES ($1::uuid, $2, NULL, 'pedagogo', 'approve', 'bichos', $3, $4, $5, $6)`,
			video, round, stated, computed, f.now, f.now.Add(-time.Duration(minutes)*time.Minute))
	}
	approve(vids[0], "ate-4", "ate-4", 1, 2)
	approve(vids[0], "5-8", "5-8", 1, 4)
	approve(vids[1], "5-8", "5-8", 1, 6)
	approve(vids[1], "5-8", "5-8", 1, 8)
	approve(vids[2], "9-12", "5-8", 1, 10)
	// Outside the window, and an approval from before the band was computed.
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band,
		computed_band, reviewed_at, began_at) VALUES ($1::uuid, 2, NULL, 'pedagogo', 'approve', 'bichos', '5-8', '5-8', $2, $3)`,
		vids[2], since.Add(-time.Second), since.Add(-time.Hour))
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band, reviewed_at)
		VALUES ($1::uuid, 3, NULL, 'pedagogo', 'approve', 'bichos', '5-8', $2)`, vids[3], f.now)
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, reason, reviewed_at,
		checklist_version, checklist) VALUES
		($1::uuid, 4, NULL, 'pedagogo', 'doubt', 'Não sei.', $2, '2026-11-20', '{}'),
		($1::uuid, 4, NULL, 'psicologo', 'doubt', 'Não sei.', $2, '2026-11-20', '{}'),
		($1::uuid, 4, NULL, 'pedagogo', 'reject', 'Motivo.', $2, NULL, NULL)`, vids[3], f.now)

	got, err := f.svc.ReviewMeasuresSince(ctx, since)
	if err != nil {
		t.Fatal(err)
	}
	want := staff.ReviewMeasures{TimedApprovals: 5, ApprovalMedianSeconds: 360, Reviews: 9, Doubts: 2,
		ComputedApprovals: 5, OlderStated: 1, PairedVideos: 2, SplitVideos: 1}
	if got != want {
		t.Fatalf("measures %+v, want %+v", got, want)
	}
}
