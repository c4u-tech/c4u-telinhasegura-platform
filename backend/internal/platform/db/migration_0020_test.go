package db_test

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db"
)

func TestMigrationModeratorViews(t *testing.T) {
	ctx := context.Background()
	pool := migratedBefore(t, "migrations/0020")
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

	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}

	const video = `INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, held_reason,
		created_at, updated_at) VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'held', 'doubt', now(), now()) RETURNING id::text`
	vid := text(video, "heldvideo01")
	const account = `INSERT INTO accounts (email, adult_declared_at, created_at) VALUES ($1, now(), now()) RETURNING id::text`
	mod := text(account, "mia@example.com")
	admin := text(account, "ana@example.com")
	exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', now())`, mod)
	exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'admin', now())`, admin)

	const view = `INSERT INTO moderator_views (moderator_id, role, video_id, round, played_to_end_at)
		VALUES ($1::uuid, $2::text, $3::uuid, $4, now())`
	exec(view, mod, "moderator", vid, 1)
	exec(view, admin, "admin", vid, 1)

	_, err := pool.Exec(ctx, view, mod, "curator", vid, 2)
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23514" || pgErr.ConstraintName != "moderator_views_role_check" {
		t.Errorf("a view under the curator role: want check violation, got %v", err)
	}
	// A view hangs off a role the account holds.
	_, err = pool.Exec(ctx, view, mod, "admin", vid, 2)
	if !errors.As(err, &pgErr) || pgErr.Code != "23503" {
		t.Errorf("a view under a role not held: want foreign key violation, got %v", err)
	}

	// Losing the role removes the views with it, and no one else's.
	exec(`DELETE FROM platform_roles WHERE account_id = $1::uuid AND role = 'moderator'`, mod)
	if n := count(`SELECT count(*) FROM moderator_views WHERE moderator_id = $1::uuid`, mod); n != 0 {
		t.Fatalf("%d views survived the loss of the role", n)
	}
	if n := count(`SELECT count(*) FROM moderator_views`); n != 1 {
		t.Fatalf("%d views left, want the admin's", n)
	}

	// The account's erasure removes them too.
	exec(`DELETE FROM accounts WHERE id = $1::uuid`, admin)
	if n := count(`SELECT count(*) FROM moderator_views`); n != 0 {
		t.Fatalf("%d views survived the erasure of the account", n)
	}

	exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', now())`, mod)
	exec(view, mod, "moderator", vid, 1)
	exec(`DELETE FROM videos`)
	if n := count(`SELECT count(*) FROM moderator_views`); n != 0 {
		t.Fatalf("%d views survived the deletion of the videos", n)
	}
}
