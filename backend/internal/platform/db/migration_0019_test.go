package db_test

import (
	"context"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db"
)

func TestMigrationReviewContract(t *testing.T) {
	ctx := context.Background()
	pool := migratedBefore(t, "migrations/0019")
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, sql, args...); err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
	}
	text := func(sql string, args ...any) string {
		t.Helper()
		var s string
		if err := pool.QueryRow(ctx, sql, args...).Scan(&s); err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
		return s
	}
	count := func(sql string, args ...any) int {
		t.Helper()
		var n int
		if err := pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
		return n
	}

	const video = `INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state,
		round, published_round, theme, min_age_band, last_reviewed_at, review_due_at, created_at, updated_at)
		VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'approved', 2, 1, 'bichos', '5-8', now(), now(), now(), now()) RETURNING id::text`
	vid := text(video, "approved001")
	vid2 := text(video, "approved002")
	curator := text(`INSERT INTO accounts (email, adult_declared_at, created_at) VALUES ('bia@example.com', now(), now()) RETURNING id::text`)
	exec(`INSERT INTO platform_roles (account_id, role, display_role, granted_at) VALUES ($1::uuid, 'curator', 'mae-pai', now())`, curator)
	exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band, reviewed_at)
		VALUES ($1::uuid, 1, $2::uuid, 'mae-pai', 'approve', 'bichos', '5-8', now())`, vid, curator)

	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}

	// Reviews written before the migration have no computed band, reason or start.
	if n := count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid
		AND computed_band IS NULL AND band_reason IS NULL AND began_at IS NULL`, vid); n != 1 {
		t.Fatal("the seeded approval did not keep its new columns empty")
	}

	const review = `INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, reviewed_at,
		computed_band, band_reason) VALUES ($1::uuid, $2, $3::uuid, 'mae-pai', $4, now(), $5::text, $6::text)`
	for name, args := range map[string][]any{
		"a rejection with a computed band": {vid, 2, curator, "reject", "5-8", nil},
		"a reason without a computed band": {vid, 2, curator, "approve", nil, "porque sim"},
		"an approval with an unknown band": {vid, 2, curator, "approve", "13-15", nil},
	} {
		if _, err := pool.Exec(ctx, review, args...); err == nil {
			t.Errorf("%s was accepted", name)
		}
	}
	exec(review, vid, 2, curator, "approve", "5-8", "Tem susto leve.")

	const draft = `INSERT INTO review_drafts (curator_id, role, video_id, round, checklist_version, began_at, updated_at)
		VALUES ($1::uuid, $2::text, $3::uuid, $4, '2026-10-20', now(), now())`
	exec(draft, curator, "curator", vid, 2)
	if _, err := pool.Exec(ctx, draft, curator, "admin", vid, 3); err == nil {
		t.Error("a draft for another role was accepted")
	}

	// Losing the curator role removes the drafts with it.
	exec(`DELETE FROM platform_roles WHERE account_id = $1::uuid AND role = 'curator'`, curator)
	if n := count(`SELECT count(*) FROM review_drafts`); n != 0 {
		t.Fatalf("%d drafts survived the loss of the role", n)
	}

	exec(`INSERT INTO platform_roles (account_id, role, display_role, granted_at) VALUES ($1::uuid, 'curator', 'mae-pai', now())`, curator)
	exec(draft, curator, "curator", vid2, 1)
	exec(`DELETE FROM videos`)
	if n := count(`SELECT count(*) FROM review_drafts`); n != 0 {
		t.Fatalf("%d drafts survived the deletion of the videos", n)
	}
}
