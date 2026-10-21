package db_test

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
)

// migratedBefore applies, as Migrate does, every migration whose file name
// sorts before first, and records it, so a test can seed the rows a later
// migration must carry over.
func migratedBefore(t *testing.T, first string) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()
	pool := dbtest.Empty(t)
	if _, err := pool.Exec(ctx, `CREATE TABLE schema_migrations (
		version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`); err != nil {
		t.Fatal(err)
	}
	names, err := filepath.Glob("migrations/*.sql")
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(names)
	for _, name := range names {
		if name >= first {
			break
		}
		sql, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		// No arguments: pgx uses the simple protocol, which runs every
		// statement in the file.
		if _, err := pool.Exec(ctx, string(sql)); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO schema_migrations (version) VALUES ($1)`, name); err != nil {
			t.Fatal(err)
		}
	}
	return pool
}

func TestMigrationCurationGovernance(t *testing.T) {
	ctx := context.Background()
	pool := migratedBefore(t, "migrations/0017")
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

	later := time.Date(2027, 4, 1, 12, 0, 0, 0, time.UTC)
	const video = `INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, held_reason,
		round, published_round, theme, min_age_band, last_reviewed_at, review_due_at, created_at, updated_at)
		VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, $2, $3::text, 2, 1, 'bichos', '5-8', now(), $4, now(), now()) RETURNING id::text`
	approved := text(video, "approved001", "approved", nil, later)
	held := text(video, "heldvideo01", "held", "review", later)
	curator := text(`INSERT INTO accounts (email, adult_declared_at, created_at) VALUES ('bia@example.com', now(), now()) RETURNING id::text`)
	exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band, reviewed_at)
		VALUES ($1::uuid, 1, $2::uuid, 'mae-pai', 'approve', 'bichos', '5-8', now())`, approved, curator)

	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}

	// Every approved video is due for its revisit now and stays approved;
	// the others keep their dates.
	if n := count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND state = 'approved' AND review_due_at <= now()`, approved); n != 1 {
		t.Fatal("the approved video is not due for its revisit")
	}
	if n := count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND review_due_at = $2`, held, later); n != 1 {
		t.Fatal("a held video's date changed")
	}

	const review = `INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, reviewed_at,
		checklist_version, checklist) VALUES ($1::uuid, $2, NULL, 'mae-pai', $3, now(), $4::text, $5::text::jsonb)`
	const answers = `{"c01": "ok", "c04": "doubt"}`
	for name, args := range map[string][]any{
		"a doubt with its answers":         {approved, 2, "doubt", "2026-10-20", answers},
		"an approval with its answers":     {approved, 3, "approve", "2026-10-20", answers},
		"a rejection with its items":       {approved, 4, "reject", "2026-10-20", `["c04"]`},
		"an approval from before the list": {approved, 5, "approve", nil, nil},
		"a rejection from before the list": {approved, 6, "reject", nil, nil},
	} {
		if _, err := pool.Exec(ctx, review, args...); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}
	for name, args := range map[string][]any{
		"a doubt without answers":          {approved, 7, "doubt", nil, nil},
		"a version without answers":        {approved, 7, "approve", "2026-10-20", nil},
		"answers without a version":        {approved, 7, "approve", nil, answers},
		"an approval with a list of items": {approved, 7, "approve", "2026-10-20", `["c04"]`},
		"a rejection with no item":         {approved, 7, "reject", "2026-10-20", `[]`},
		"a rejection with answers":         {approved, 7, "reject", "2026-10-20", answers},
		"an unknown decision":              {approved, 7, "skip", nil, nil},
	} {
		if _, err := pool.Exec(ctx, review, args...); err == nil {
			t.Errorf("%s was accepted", name)
		}
	}

	for _, reason := range []string{"doubt", "audit"} {
		exec(`UPDATE videos SET held_reason = $2 WHERE id = $1::uuid`, held, reason)
	}
	if _, err := pool.Exec(ctx, `UPDATE videos SET held_reason = 'other' WHERE id = $1::uuid`, held); err == nil {
		t.Error("an unknown held reason was accepted")
	}

	// No foreign key: the proof outlives the account it names.
	const declare = `INSERT INTO curator_declarations (account_id, version, accepted_at) VALUES ($1::uuid, $2, now())`
	exec(declare, "11111111-1111-1111-1111-111111111111", "2026-10-20")
	if _, err := pool.Exec(ctx, declare, "11111111-1111-1111-1111-111111111111", "2026-10-20"); err == nil {
		t.Error("the same version was accepted twice")
	}

	const audit = `INSERT INTO approval_audits (video_id, round, auditor_id, verdict, reason, audited_at)
		VALUES ($1::uuid, $2, NULL, $3, $4::text, now())`
	exec(audit, approved, 1, "agree", nil)
	exec(audit, approved, 2, "disagree", "Tem publi no fim.")
	for name, args := range map[string][]any{
		"a second audit of a round":       {approved, 1, "agree", nil},
		"a disagreement without a reason": {approved, 3, "disagree", nil},
		"an unknown verdict":              {approved, 3, "maybe", nil},
	} {
		if _, err := pool.Exec(ctx, audit, args...); err == nil {
			t.Errorf("%s was accepted", name)
		}
	}

	// A legacy reviewer's account is erased: the cascade rewrites their
	// review without a checklist, and the new checks let it.
	exec(`DELETE FROM accounts WHERE id = $1::uuid`, curator)
	if n := count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid AND round = 1 AND curator_id IS NULL`, approved); n != 1 {
		t.Fatal("the erased curator's legacy review is gone")
	}
}
