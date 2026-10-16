package privacy_test

import (
	"strings"
	"testing"
)

// screenTimeRows seeds ana's family with Lia, her rules, the zone, one
// day, one extension by bia and one play.
func screenTimeRows(f *fixture) (ana, bia, fam, lia string) {
	f.t.Helper()
	ana = f.account("ana@example.com")
	bia = f.account("bia@example.com")
	fam = f.family(ana)
	f.join(fam, bia)
	lia = f.minor(fam, ana, "Lia")
	video := f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, round, published_round,
		theme, min_age_band, created_at, updated_at)
		VALUES ('dQw4w9WgXcQ', 'Baby Shark', 'UC1', 'Canal', 300, 'approved', 2, 1, 'bichos', 'ate-4', $1, $1) RETURNING id::text`, f.now)
	f.exec(`INSERT INTO screentime_families (family_id, time_zone, set_at) VALUES ($1::uuid, 'America/Manaus', $2)`, fam, f.now)
	f.exec(`INSERT INTO screentime_rules (minor_id, daily_minutes, window_start, window_end, updated_by, updated_at)
		VALUES ($1::uuid, 45, 480, 1080, $2::uuid, $3)`, lia, bia, f.now)
	f.exec(`INSERT INTO screentime_days (minor_id, day, seconds, outside_seconds, extension_minutes)
		VALUES ($1::uuid, '2026-10-04', 1800, 0, 15)`, lia)
	f.exec(`INSERT INTO screentime_extensions (minor_id, day, minutes, via, account_id, created_at)
		VALUES ($1::uuid, '2026-10-04', 15, 'guardian', $2::uuid, $3)`, lia, bia, f.now)
	f.exec(`INSERT INTO plays (minor_id, video_id, started_at, last_beat_at, playing, seconds)
		VALUES ($1::uuid, $2::uuid, $3, $3, false, 300)`, lia, video, f.now)
	return ana, bia, fam, lia
}

func TestExportScreenTime(t *testing.T) {
	f := newFixture(t)
	ana, bia, _, lia := screenTimeRows(f)
	js := f.exportJSON(ana)
	if strings.Contains(js, bia) {
		t.Fatal("the export carries another guardian's ID")
	}
	for _, key := range []string{
		`"time_zone":"America/Manaus"`,
		`"screen_time_rules":[{"minor_id":"` + lia + `","daily_minutes":45,"window_start":"08:00","window_end":"18:00"`,
		`"screen_time_days":[{"minor_id":"` + lia + `","date":"2026-10-04","seconds":1800,"outside_seconds":0,"extension_minutes":15}]`,
		`"screen_time_extensions":[{"minor_id":"` + lia + `","date":"2026-10-04","minutes":15,"via":"guardian"`,
		`"plays":[{"minor_id":"` + lia + `","youtube_id":"dQw4w9WgXcQ","video_title":"Baby Shark","started_at":"2026-10-04T12:00:00Z","seconds":300}]`,
	} {
		if !strings.Contains(js, key) {
			t.Errorf("missing %s in %s", key, js)
		}
	}
}

func TestErasingScreenTime(t *testing.T) {
	f := newFixture(t)
	_, bia, fam, lia := screenTimeRows(f)
	if err := f.svc.DeleteAccount(ctx, bia, nil); err != nil {
		t.Fatal(err)
	}
	if f.count(`SELECT count(*) FROM screentime_rules WHERE updated_by IS NULL`) != 1 ||
		f.count(`SELECT count(*) FROM screentime_extensions WHERE account_id IS NULL`) != 1 {
		t.Fatal("the erased guardian's rows were not kept without them")
	}
	f.exec(`DELETE FROM minors WHERE id = $1::uuid`, lia)
	for _, table := range []string{"screentime_rules", "screentime_days", "screentime_extensions", "plays"} {
		if n := f.count(`SELECT count(*) FROM ` + table); n != 0 {
			t.Errorf("%d %s outlived the child", n, table)
		}
	}
	f.exec(`DELETE FROM families WHERE id = $1::uuid`, fam)
	if n := f.count(`SELECT count(*) FROM screentime_families`); n != 0 {
		t.Fatal("the zone outlived the family")
	}
}
