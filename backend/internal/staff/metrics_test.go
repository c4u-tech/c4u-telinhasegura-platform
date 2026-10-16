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
	for _, p := range []*int{m.Accounts, m.Families, m.Minors, m.ActiveDevices, m.PublishedVideos, m.PublishedPacks, m.Reports7d} {
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
	want := []string{"5", "5", "null", "5", "5", "null", "5"}
	if !slices.Equal(counts(m), want) {
		t.Fatalf("metrics %v, want %v (accounts, families, minors, active devices, videos, packs, reports 7d)", counts(m), want)
	}
	if staff.SuppressedBelow != 5 {
		t.Fatalf("suppressed below %d", staff.SuppressedBelow)
	}
}
