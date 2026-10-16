package privacy_test

import (
	"strings"
	"testing"
)

// catalogRows seeds ana's family with bia as a guardian, the child Lia,
// one video bia hid for Lia and reported with a note.
func catalogRows(f *fixture) (ana, bia, fam, lia, video string) {
	f.t.Helper()
	ana = f.account("ana@example.com")
	bia = f.account("bia@example.com")
	fam = f.family(ana)
	f.join(fam, bia)
	lia = f.minor(fam, ana, "Lia")
	video = f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, round, published_round,
		theme, min_age_band, created_at, updated_at)
		VALUES ('dQw4w9WgXcQ', 'Baby Shark', 'UC1', 'Canal', 300, 'approved', 2, 1, 'bichos', 'ate-4', $1, $1) RETURNING id::text`, f.now)
	f.exec(`INSERT INTO video_hides (minor_id, video_id, hidden_by, hidden_at) VALUES ($1::uuid, $2::uuid, $3::uuid, $4)`,
		lia, video, bia, f.now)
	f.exec(`INSERT INTO video_reports (video_id, family_id, account_id, reason, note, reported_at)
		VALUES ($1::uuid, $2::uuid, $3::uuid, 'assustador', 'Tem um monstro.', $4)`, video, fam, bia, f.now)
	return ana, bia, fam, lia, video
}

func TestExportHidesAndReports(t *testing.T) {
	f := newFixture(t)
	ana, bia, _, lia, _ := catalogRows(f)

	e, err := f.svc.Export(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	fam := e.Family
	if fam == nil || len(fam.Hides) != 1 || fam.Hides[0].MinorID != lia || fam.Hides[0].YouTubeID != "dQw4w9WgXcQ" ||
		fam.Hides[0].VideoTitle != "Baby Shark" || !fam.Hides[0].HiddenAt.Equal(f.now) {
		t.Fatalf("hides %+v", fam)
	}
	if r := fam.Reports; len(r) != 1 || r[0].YouTubeID != "dQw4w9WgXcQ" || r[0].Reason != "assustador" ||
		r[0].Note == nil || *r[0].Note != "Tem um monstro." || !r[0].ReportedAt.Equal(f.now) {
		t.Fatalf("reports %+v", r)
	}
	js := f.exportJSON(ana)
	if strings.Contains(js, bia) {
		t.Fatal("the export carries another guardian's ID")
	}
	for _, key := range []string{`"hides":[{"minor_id":"` + lia + `"`, `"video_title":"Baby Shark"`,
		`"hidden_at":"2026-10-04T12:00:00Z"`, `"reports":[{"youtube_id":"dQw4w9WgXcQ"`, `"reason":"assustador"`,
		`"note":"Tem um monstro."`, `"reported_at":"2026-10-04T12:00:00Z"`} {
		if !strings.Contains(js, key) {
			t.Errorf("missing %s in %s", key, js)
		}
	}
}

func TestDeletingAChildOrAFamilyErasesItsHidesAndReports(t *testing.T) {
	f := newFixture(t)
	_, _, fam, lia, video := catalogRows(f)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'reports' WHERE id = $1::uuid`, video)

	f.exec(`DELETE FROM minors WHERE id = $1::uuid`, lia)
	if n := f.count(`SELECT count(*) FROM video_hides`); n != 0 {
		t.Fatalf("%d hides outlived the child", n)
	}
	if n := f.count(`SELECT count(*) FROM video_reports`); n != 1 {
		t.Fatalf("the family's report went with the child: %d", n)
	}
	f.exec(`DELETE FROM families WHERE id = $1::uuid`, fam)
	if n := f.count(`SELECT count(*) FROM video_reports`); n != 0 {
		t.Fatalf("%d reports outlived the family", n)
	}
	if n := f.count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND state = 'held'`, video); n != 1 {
		t.Fatal("the held video was released")
	}
}

func TestDeletingAnAccountKeepsItsReportWithoutTheNote(t *testing.T) {
	f := newFixture(t)
	_, bia, _, lia, video := catalogRows(f)

	if err := f.svc.DeleteAccount(ctx, bia, nil); err != nil {
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM video_reports WHERE video_id = $1::uuid AND account_id IS NULL AND note IS NULL
		AND reason = 'assustador'`, video); n != 1 {
		t.Fatal("the report was not kept without its author and note")
	}
	if n := f.count(`SELECT count(*) FROM video_hides WHERE minor_id = $1::uuid AND hidden_by IS NULL`, lia); n != 1 {
		t.Fatal("the hide was not kept without its author")
	}
}
