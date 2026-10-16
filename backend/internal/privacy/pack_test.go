package privacy_test

import (
	"strings"
	"testing"
)

// packRows seeds ana (pedagogo) and bia (mae-pai) as curators, and a pack
// whose round 1 ana composed and bia approved, and whose round 2 bia
// composed and ana rejected.
func packRows(f *fixture) (ana, bia, pack string) {
	f.t.Helper()
	ana = f.account("ana@example.com")
	bia = f.account("bia@example.com")
	f.exec(`INSERT INTO platform_roles (account_id, role, display_role, verified_professional, granted_at)
		VALUES ($1::uuid, 'curator', 'pedagogo', true, $3), ($2::uuid, 'curator', 'mae-pai', false, $3)`, ana, bia, f.now)
	video := f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, round, published_round,
		theme, min_age_band, created_at, updated_at)
		VALUES ('dQw4w9WgXcQ', 'Baby Shark', 'UC1', 'Canal', 300, 'approved', 2, 1, 'bichos', 'ate-4', $1, $1) RETURNING id::text`, f.now)
	pack = f.id(`INSERT INTO packs (state, round, published_round, last_reviewed_at, created_at, updated_at)
		VALUES ('approved', 2, 1, $1, $1, $1) RETURNING id::text`, f.now)
	f.exec(`INSERT INTO pack_rounds (pack_id, round, title, cover_video_id, composer_id, composer_role, composed_at, outcome)
		VALUES ($1::uuid, 1, 'Bichos', $2::uuid, $3::uuid, 'pedagogo', $5, 'published'),
		       ($1::uuid, 2, 'Outros bichos', $2::uuid, $4::uuid, 'mae-pai', $5, 'rejected')`, pack, video, ana, bia, f.now)
	f.exec(`INSERT INTO pack_items (pack_id, round, position, video_id)
		VALUES ($1::uuid, 1, 1, $2::uuid), ($1::uuid, 2, 1, $2::uuid)`, pack, video)
	f.exec(`INSERT INTO pack_reviews (pack_id, round, curator_id, display_role, decision, reason, reviewed_at)
		VALUES ($1::uuid, 1, $3::uuid, 'mae-pai', 'approve', NULL, $4),
		       ($1::uuid, 2, $2::uuid, 'pedagogo', 'reject', 'Muito longo.', $4)`, pack, ana, bia, f.now)
	return ana, bia, pack
}

func TestExportPackRows(t *testing.T) {
	f := newFixture(t)
	ana, bia, pack := packRows(f)

	e, err := f.svc.Export(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	a := e.Account
	if r := a.PackReviews; len(r) != 1 || r[0].PackID != pack || r[0].Round != 2 || r[0].DisplayRole != "pedagogo" ||
		r[0].Decision != "reject" || r[0].Reason == nil || *r[0].Reason != "Muito longo." || !r[0].ReviewedAt.Equal(f.now) {
		t.Fatalf("pack reviews %+v", r)
	}
	if c := a.PackCompositions; len(c) != 1 || c[0].PackID != pack || c[0].Round != 1 || c[0].Title != "Bichos" ||
		!c[0].ComposedAt.Equal(f.now) {
		t.Fatalf("pack compositions %+v", c)
	}
	js := f.exportJSON(ana)
	for _, key := range []string{`"pack_reviews":[{"pack_id":"` + pack + `"`, `"display_role":"pedagogo","decision":"reject"`,
		`"reason":"Muito longo."`, `"pack_compositions":[{"pack_id":"` + pack + `","round":1,"title":"Bichos"`,
		`"composed_at":"2026-10-04T12:00:00Z"`} {
		if !strings.Contains(js, key) {
			t.Errorf("missing %s in %s", key, js)
		}
	}
	if strings.Contains(js, bia) || strings.Contains(js, "bia@example.com") || strings.Contains(js, "Outros bichos") {
		t.Fatal("the export carries another curator's rows")
	}
	plain := f.account("caio@example.com")
	if js := f.exportJSON(plain); !strings.Contains(js, `"pack_reviews":[]`) || !strings.Contains(js, `"pack_compositions":[]`) {
		t.Fatalf("an account with no pack rows must export empty lists: %s", js)
	}
}

func TestDeleteKeepsThePackLedger(t *testing.T) {
	f := newFixture(t)
	ana, _, pack := packRows(f)

	if err := f.svc.DeleteAccount(ctx, ana, nil); err != nil {
		t.Fatal(err)
	}
	for q, want := range map[string]int{
		`SELECT count(*) FROM pack_rounds WHERE pack_id = $1::uuid AND round = 1 AND composer_id IS NULL AND composer_role = 'pedagogo'`: 1,
		`SELECT count(*) FROM pack_reviews WHERE pack_id = $1::uuid AND round = 2 AND curator_id IS NULL
			AND display_role = 'pedagogo' AND reason = 'Muito longo.'`: 1,
		`SELECT count(*) FROM pack_reviews WHERE pack_id = $1::uuid AND round = 1 AND curator_id IS NOT NULL AND display_role = 'mae-pai'`: 1,
		`SELECT count(*) FROM packs WHERE id = $1::uuid AND state = 'approved' AND published_round = 1`:                                    1,
	} {
		if n := f.count(q, pack); n != want {
			t.Errorf("%s: %d, want %d", q, n, want)
		}
	}
}
