package staff_test

import (
	"fmt"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// counts shows the metrics in contract order, "null" for a suppressed one.
func counts(m staff.Metrics) []string {
	out := []string{}
	for _, p := range []*int{m.Accounts, m.Families, m.Minors, m.ActiveDevices, m.PublishedVideos, m.PublishedPacks, m.Reports7d,
		m.ApprovalMedianSeconds30d, m.DoubtPercent30d, m.OlderBandPercent30d, m.SplitBandPercent30d} {
		if p == nil {
			out = append(out, "null")
		} else {
			out = append(out, strconv.Itoa(*p))
		}
	}
	return out
}

func TestMetricsSuppressCountsBelowFive(t *testing.T) {
	f := newFixture(t)
	if m, err := f.svc.Metrics(ctx); err != nil || m != (staff.Metrics{}) {
		t.Fatalf("an empty platform must answer every count as null: %v %v", counts(m), err)
	}

	var owners, fams []string
	for i := range 5 {
		id := f.account(fmt.Sprintf("dono%d@example.com", i))
		owners, fams = append(owners, id), append(fams, f.owner(id))
	}
	lia := f.minor(owners[0])
	for range 3 {
		f.minor(owners[1]) // 4 minors in all: suppressed
	}
	idle := 180 * 24 * time.Hour
	f.device(fams[0], lia, f.now.Add(-idle+time.Second))
	for range 4 {
		f.device(fams[0], lia, f.now)
	}
	f.device(fams[0], lia, f.now.Add(-idle)) // seen exactly 180 days ago: not active
	var videos []string
	for i := range 5 {
		videos = append(videos, f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state,
			published_round, created_at, updated_at) VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'approved', 1, $2, $2) RETURNING id::text`,
			fmt.Sprintf("vid%08d", i), f.now))
	}
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, f.video(ytID))
	week := 7 * 24 * time.Hour
	for i, fam := range fams {
		at := f.now
		if i == 0 {
			at = f.now.Add(-week) // the window's edge: counted
		}
		f.exec(`INSERT INTO video_reports (video_id, family_id, reason, reported_at) VALUES ($1::uuid, $2::uuid, 'outro', $3)`,
			videos[0], fam, at)
	}
	f.exec(`INSERT INTO video_reports (video_id, family_id, reason, reported_at) VALUES ($1::uuid, $2::uuid, 'outro', $3)`,
		videos[1], fams[0], f.now.Add(-week-time.Second))

	m, err := f.svc.Metrics(ctx)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"5", "5", "null", "5", "5", "null", "5", "null", "null", "null", "null"}
	if !slices.Equal(counts(m), want) {
		t.Fatalf("metrics %v, want %v (accounts, families, minors, active devices, videos, packs, reports 7d, then the four 30-day review measures)", counts(m), want)
	}
	if staff.SuppressedBelow != 5 {
		t.Fatalf("suppressed below %d", staff.SuppressedBelow)
	}
}

func TestReviewMeasuresAbsentUnderFiveCases(t *testing.T) {
	f := newFixture(t)
	var videos []string
	for i := range 5 {
		videos = append(videos, f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state,
			published_round, created_at, updated_at) VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'approved', 1, $2, $2) RETURNING id::text`,
			fmt.Sprintf("rev%08d", i), f.now))
	}
	approve := func(video string, round int, at time.Time, began *time.Time, computed *string) {
		f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band,
			computed_band, reviewed_at, began_at) VALUES ($1::uuid, $2, NULL, 'pedagogo', 'approve', 'bichos', '5-8', $3, $4, $5)`,
			video, round, computed, at, began)
	}
	measures := func() []string {
		m, err := f.svc.Metrics(ctx)
		if err != nil {
			t.Fatal(err)
		}
		return counts(m)[7:]
	}
	null4 := []string{"null", "null", "null", "null"}
	if got := measures(); !slices.Equal(got, null4) {
		t.Fatalf("an empty platform: %v", got)
	}

	// The window's edge is counted, as in the 7-day reports.
	edge := f.now.Add(-30 * 24 * time.Hour)
	began := edge.Add(-3 * time.Minute)
	for i := range 4 {
		approve(videos[i], 1, edge, &began, nil)
	}
	if got := measures()[0]; got != "null" {
		t.Fatalf("four timed approvals: median %s", got)
	}
	approve(videos[4], 1, edge, &began, nil)
	if got := measures()[0]; got != "180" {
		t.Fatalf("five timed approvals: median %s, want 180", got)
	}
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, reason, reviewed_at)
		VALUES ($1::uuid, 2, NULL, 'pedagogo', 'reject', 'Motivo.', $2)`, videos[0], edge.Add(-time.Second))
	if got := measures()[0]; got != "180" {
		t.Fatalf("a review just outside the window changed the median: %s", got)
	}

	// 5 reviews in the window, 1 of them a doubt: 20 percent.
	f.exec(`DELETE FROM video_reviews`)
	for i := range 4 {
		approve(videos[i], 1, f.now, nil, nil)
	}
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, reason, reviewed_at,
		checklist_version, checklist) VALUES ($1::uuid, 1, NULL, 'pedagogo', 'doubt', 'Não sei.', $2, '2026-11-20', '{}')`,
		videos[4], f.now)
	if got := measures()[1]; got != "20" {
		t.Fatalf("one doubt in five reviews: %s, want 20", got)
	}

	// Four videos with two approvals each: under five pairs, no split share.
	f.exec(`DELETE FROM video_reviews`)
	ate4, older := "ate-4", "5-8"
	for i := range 4 {
		approve(videos[i], 1, f.now, &began, &ate4)
		approve(videos[i], 1, f.now, &began, &older)
	}
	if got := measures()[3]; got != "null" {
		t.Fatalf("four paired videos: %s", got)
	}
	approve(videos[4], 1, f.now, &began, &ate4)
	approve(videos[4], 1, f.now, &began, &ate4)
	if got := measures()[3]; got != "80" {
		t.Fatalf("four of five paired videos split: %s, want 80", got)
	}
}
