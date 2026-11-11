package screentime_test

import (
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
)

func TestUsageListsSevenDays(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	_, stranger := f.family("bia@example.com")
	c := f.minor(fam, "5-8")
	f.exec(`INSERT INTO screentime_days (minor_id, day, seconds) VALUES
		($1::uuid, '2026-10-05', 600), ($1::uuid, '2026-10-02', 300), ($1::uuid, '2026-09-28', 999)`, c.MinorID)
	got, err := f.svc.Usage(ctx, owner, c.MinorID)
	if err != nil {
		t.Fatal(err)
	}
	want := []screentime.DayUsage{{"2026-09-29", 0}, {"2026-09-30", 0}, {"2026-10-01", 0}, {"2026-10-02", 300},
		{"2026-10-03", 0}, {"2026-10-04", 0}, {"2026-10-05", 600}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%v", got)
	}
	if _, err := f.svc.Usage(ctx, stranger, c.MinorID); !errors.Is(err, screentime.ErrNotFound) {
		t.Fatalf("stranger: %v", err)
	}
}

func TestSweepAppliesRetention(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 300)
	old, recent := f.now.Add(-30*24*time.Hour-time.Minute), f.now.Add(-29*24*time.Hour)
	for _, at := range []time.Time{old, recent} {
		f.exec(`INSERT INTO plays (minor_id, video_id, started_at, last_beat_at, playing) VALUES ($1::uuid, $2::uuid, $3, $3, false)`,
			c.MinorID, v, at)
	}
	f.exec(`INSERT INTO screentime_days (minor_id, day) VALUES ($1::uuid, '2026-07-06'), ($1::uuid, '2026-07-08')`, c.MinorID)
	f.exec(`INSERT INTO screentime_extensions (minor_id, day, minutes, via, created_at) VALUES
		($1::uuid, '2026-07-06', 15, 'pin', $2), ($1::uuid, '2026-07-08', 15, 'pin', $2)`, c.MinorID, f.now)
	if err := f.svc.Sweep(ctx); err != nil {
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM plays WHERE started_at = $1`, recent); n != 1 || f.count(`SELECT count(*) FROM plays`) != 1 {
		t.Fatal("plays retention")
	}
	// 90 days before 2026-10-05 is 2026-07-07.
	if n := f.count(`SELECT count(*) FROM screentime_days WHERE day = '2026-07-08'`); n != 1 || f.count(`SELECT count(*) FROM screentime_days`) != 1 {
		t.Fatal("days retention")
	}
	if f.count(`SELECT count(*) FROM screentime_extensions`) != 1 {
		t.Fatal("extensions retention")
	}
}

// Resume points go with the play history, after 30 days without an
// update; sessions, used or not, are gone after a day.
func TestSweepClearsPositionsAndSessions(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	old, recent := f.video("dQw4w9WgXcQ", 50*60), f.video("aaaaaaaaaaa", 50*60)
	f.exec(`INSERT INTO play_positions (minor_id, video_id, position_seconds, updated_at) VALUES
		($1::uuid, $2::uuid, 600, $4), ($1::uuid, $3::uuid, 600, $5)`,
		c.MinorID, old, recent, f.now.Add(-30*24*time.Hour-time.Minute), f.now.Add(-29*24*time.Hour))
	for _, created := range []time.Time{f.now.Add(-25 * time.Hour), f.now.Add(-time.Hour)} {
		f.exec(`INSERT INTO family_sessions (minor_id, video_id, account_id, created_at, expires_at)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5)`, c.MinorID, old, owner, created, created.Add(10*time.Minute))
	}
	if err := f.svc.Sweep(ctx); err != nil {
		t.Fatal(err)
	}
	if f.count(`SELECT count(*) FROM play_positions WHERE video_id = $1::uuid`, recent) != 1 ||
		f.count(`SELECT count(*) FROM play_positions`) != 1 {
		t.Fatal("positions retention")
	}
	if f.count(`SELECT count(*) FROM family_sessions WHERE created_at = $1`, f.now.Add(-time.Hour)) != 1 ||
		f.count(`SELECT count(*) FROM family_sessions`) != 1 {
		t.Fatal("sessions retention")
	}
}
