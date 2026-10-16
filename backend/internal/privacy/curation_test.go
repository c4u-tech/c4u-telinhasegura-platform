package privacy_test

import (
	"strings"
	"testing"
)

// curationRows seeds ana as admin and pedagogo curator who granted bia's
// curator role, one video both suggested, and one review each.
func curationRows(f *fixture) (ana, bia, video string) {
	f.t.Helper()
	ana = f.account("ana@example.com")
	bia = f.account("bia@example.com")
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'admin', $2)`, ana, f.now)
	f.exec(`INSERT INTO platform_roles (account_id, role, display_role, verified_professional, granted_by, granted_at)
		VALUES ($1::uuid, 'curator', 'pedagogo', true, $1::uuid, $3), ($2::uuid, 'curator', 'mae-pai', false, $1::uuid, $3)`,
		ana, bia, f.now)
	video = f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, held_reason, created_at, updated_at)
		VALUES ('dQw4w9WgXcQ', 'Baby Shark', 'UC1', 'Canal', 300, 'held', 'review', $1, $1) RETURNING id::text`, f.now)
	f.exec(`INSERT INTO video_suggestions (video_id, account_id, suggested_at) VALUES ($1::uuid, $2::uuid, $4), ($1::uuid, $3::uuid, $4)`,
		video, ana, bia, f.now)
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band, reason, reviewed_at)
		VALUES ($1::uuid, 1, $2::uuid, 'pedagogo', 'reject', NULL, NULL, 'Tem propaganda.', $4),
		       ($1::uuid, 1, $3::uuid, 'mae-pai', 'approve', 'bichos', '5-8', NULL, $4)`, video, ana, bia, f.now)
	return ana, bia, video
}

func TestExportCuration(t *testing.T) {
	f := newFixture(t)
	ana, bia, _ := curationRows(f)

	e, err := f.svc.Export(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	a := e.Account
	if len(a.PlatformRoles) != 2 || a.PlatformRoles[0].Role != "admin" || a.PlatformRoles[0].DisplayRole != nil ||
		a.PlatformRoles[1].Role != "curator" || a.PlatformRoles[1].DisplayRole == nil || *a.PlatformRoles[1].DisplayRole != "pedagogo" ||
		!a.PlatformRoles[1].VerifiedProfessional || !a.PlatformRoles[1].GrantedAt.Equal(f.now) {
		t.Fatalf("roles %+v", a.PlatformRoles)
	}
	if len(a.Suggestions) != 1 || a.Suggestions[0].YouTubeID != "dQw4w9WgXcQ" || a.Suggestions[0].VideoTitle != "Baby Shark" ||
		!a.Suggestions[0].SuggestedAt.Equal(f.now) {
		t.Fatalf("suggestions %+v", a.Suggestions)
	}
	if r := a.Reviews; len(r) != 1 || r[0].YouTubeID != "dQw4w9WgXcQ" || r[0].Decision != "reject" || r[0].DisplayRole != "pedagogo" ||
		r[0].Reason == nil || *r[0].Reason != "Tem propaganda." || r[0].Theme != nil || r[0].MinAgeBand != nil || r[0].Round != 1 {
		t.Fatalf("reviews %+v", r)
	}
	js := f.exportJSON(ana)
	if strings.Contains(js, bia) || strings.Contains(js, "bia@example.com") {
		t.Fatal("the export carries another curator")
	}
	for _, key := range []string{`"platform_roles":[`, `"role":"curator"`, `"display_role":"pedagogo"`, `"display_role":null`,
		`"verified_professional":true`, `"granted_at":"2026-10-04T12:00:00Z"`, `"suggestions":[{"youtube_id":"dQw4w9WgXcQ"`,
		`"video_title":"Baby Shark"`, `"suggested_at":"2026-10-04T12:00:00Z"`, `"reviews":[{"youtube_id":"dQw4w9WgXcQ"`,
		`"round":1`, `"decision":"reject"`, `"theme":null`, `"min_age_band":null`, `"reason":"Tem propaganda."`,
		`"reviewed_at":"2026-10-04T12:00:00Z"`} {
		if !strings.Contains(js, key) {
			t.Errorf("missing %s in %s", key, js)
		}
	}

	// bia's curator role was granted by ana: ana's id is another account's.
	if js := f.exportJSON(bia); strings.Contains(js, ana) || strings.Contains(js, "ana@example.com") || strings.Contains(js, "granted_by") {
		t.Fatalf("bia's export carries her grantor: %s", js)
	}
}

func TestDeleteKeepsTheReviewLedger(t *testing.T) {
	f := newFixture(t)
	ana, bia, video := curationRows(f)

	if err := f.svc.DeleteAccount(ctx, ana, nil); err != nil {
		t.Fatal(err)
	}
	for q, want := range map[string]int{
		`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid`:    0,
		`SELECT count(*) FROM video_suggestions WHERE account_id = $1::uuid`: 0,
		`SELECT count(*) FROM video_reviews WHERE curator_id = $1::uuid`:     0,
	} {
		if n := f.count(q, ana); n != want {
			t.Errorf("%s: %d, want %d", q, n, want)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid AND curator_id IS NULL
		AND display_role = 'pedagogo' AND reason = 'Tem propaganda.'`, video); n != 1 {
		t.Fatal("the erased curator's review must stay, with its displayed role and no account")
	}
	if n := f.count(`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid AND granted_by IS NULL`, bia); n != 1 {
		t.Fatal("a role the erased admin granted must stay, without the grantor")
	}
	if n := f.count(`SELECT count(*) FROM video_suggestions WHERE account_id = $1::uuid`, bia); n != 1 {
		t.Fatal("the erasure removed another account's suggestion")
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE curator_id = $1::uuid AND display_role = 'mae-pai'`, bia); n != 1 {
		t.Fatal("the erasure removed another account's review")
	}
	if n := f.count(`SELECT count(*) FROM videos`); n != 1 {
		t.Fatal("the erasure removed a video")
	}
}
